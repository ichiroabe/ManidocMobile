import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'security_helper.dart';

class GeminiService {
  static const _apiKeyPref = 'gemini_api_key';
  static const _modelPref = 'gemini_model';
  static const _imageModelPref = 'gemini_image_model';
  static const _modelsCachePref = 'gemini_models_cache';
  static const _imageModelsCachePref = 'gemini_image_models_cache';
  static const _defaultModel = 'gemini-2.5-flash';
  static const _defaultImageModel = 'gemini-2.5-flash-image';

  /// v1.0.0 までの既定値。プレビュー版は提供終了で 404 になるため、
  /// 保存済みでも安定版へ寄せる。
  static const _legacyPreviewModel = 'gemini-2.5-flash-preview-04-17';

  /// 応答が返らないまま待ち続けないように必ず打ち切る。
  /// 一覧取得で固まると「取得できない」としか見えなくなる。
  static const _listTimeout = Duration(seconds: 20);
  static const _generateTimeout = Duration(seconds: 120);
  static const _imageTimeout = Duration(seconds: 180);

  Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = prefs.getString(_apiKeyPref);
    if (encrypted == null || encrypted.isEmpty) return null;
    final decrypted = SecurityHelper.decrypt(encrypted);
    return decrypted.isNotEmpty ? decrypted : null;
  }

  Future<void> setApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key.isEmpty) {
      await prefs.remove(_apiKeyPref);
      return;
    }
    await prefs.setString(_apiKeyPref, SecurityHelper.encrypt(key));
  }

  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modelPref);
    if (saved == null || saved.isEmpty || saved == _legacyPreviewModel) {
      return _defaultModel;
    }
    return saved;
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _modelPref, model.trim().isEmpty ? _defaultModel : model.trim());
  }

  Future<String> getImageModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_imageModelPref);
    return (saved == null || saved.isEmpty) ? _defaultImageModel : saved;
  }

  Future<void> setImageModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_imageModelPref,
        model.trim().isEmpty ? _defaultImageModel : model.trim());
  }

  /// 最後に取得できたモデル一覧。AIタブのモデル選択は毎回取りに行かず
  /// これを使う（未取得なら空。設定画面か選択メニューから取得できる）。
  Future<List<String>> getCachedModels() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_modelsCachePref) ?? const [];
  }

  Future<List<String>> getCachedImageModels() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_imageModelsCachePref) ?? const [];
  }

  Future<void> _cacheModels(List<String> text, List<String> image) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_modelsCachePref, text);
    await prefs.setStringList(_imageModelsCachePref, image);
  }

  /// APIキーで実際に使えるモデル一覧。テキスト用と画像用に振り分けて返す。
  /// 成功したら端末内に控えておく。
  Future<({List<String> text, List<String> image})> listModels(
      String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) throw Exception('APIキーが入力されていません');

    final names = <String>[];
    String? pageToken;
    // 1ページあたり数十件。トークンが尽きるまで辿る(暴走防止に5ページで打ち切り)
    for (var page = 0; page < 5; page++) {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models'
        '?key=$key&pageSize=100'
        '${pageToken == null ? '' : '&pageToken=$pageToken'}',
      );
      final response = await http.get(url).timeout(_listTimeout);
      if (response.statusCode != 200) _throwHttp(response);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final models = json['models'];
      if (models is List) {
        for (final item in models) {
          if (item is! Map<String, dynamic>) continue;
          // このアプリは generateContent しか呼ばないので、それ以外は候補にしない
          final methods = item['supportedGenerationMethods'];
          if (methods is List && !methods.contains('generateContent')) continue;
          final raw = item['name'];
          if (raw is! String || raw.isEmpty) continue;
          names.add(raw.startsWith('models/') ? raw.substring(7) : raw);
        }
      }
      final next = json['nextPageToken'];
      if (next is! String || next.isEmpty) break;
      pageToken = next;
    }

    // レスポンスに「画像を出力できる」という印が無いため名前で判別するしかない。
    // 命名が変わったらここが外れる。
    bool isImage(String n) => n.contains('image');
    bool isTextChat(String n) =>
        !isImage(n) &&
        !n.contains('embedding') &&
        !n.contains('aqa') &&
        !n.contains('tts');

    final text = names.where(isTextChat).toList()..sort(_compareModelNames);
    final image = names.where(isImage).toList()..sort(_compareModelNames);
    await _cacheModels(text, image);
    return (text: text, image: image);
  }

  /// APIエラーは本文に理由が入っている。`HTTP 403` だけでは何も分からない。
  Never _throwHttp(http.Response response) {
    var detail = '';
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          final status = error['status'];
          final message = error['message'];
          detail = [
            if (status is String && status.isNotEmpty) status,
            if (message is String && message.isNotEmpty) message,
          ].join(': ');
        }
      }
    } catch (_) {
      // 本文がJSONでないこともある
    }
    throw Exception(
        'HTTP ${response.statusCode}${detail.isEmpty ? '' : ' — $detail'}');
  }

  /// 安定版を先に、preview/experimental や日付入りスナップショットを後ろに寄せる
  static int _compareModelNames(String a, String b) {
    bool unstable(String n) =>
        n.contains('preview') ||
        n.contains('exp') ||
        RegExp(r'-\d{2,}$').hasMatch(n);
    final ua = unstable(a);
    final ub = unstable(b);
    if (ua != ub) return ua ? 1 : -1;
    return a.compareTo(b);
  }

  /// REST API でコンテンツ生成（tools なし）
  Future<String?> generate(String prompt) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return null;

    final model = await getModel();
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
    );

    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
    });

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(_generateTimeout);
    if (response.statusCode != 200) _throwHttp(response);
    return _extractText(response.body);
  }

  Future<String?> continueText(String article) => generate(
        '以下の文章の続きを自然な形で書いてください。出力は続き部分のみ。\n\n$article',
      );

  Future<String?> summarize(String article) => generate(
        '以下の文章を簡潔に要約してください。\n\n$article',
      );

  Future<String?> refine(String article) => generate(
        '以下の文章を読みやすく整えてください。文体・内容は変えないでください。\n\n$article',
      );

  Future<String?> custom(String instruction, String article) => generate(
        '$instruction\n\n$article',
      );

  /// Google Search Grounding 付きで生成
  Future<String?> generateWithGrounding(String prompt) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return null;

    final model = await getModel();
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
    );

    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'tools': [
        {'google_search': {}}
      ],
    });

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(_generateTimeout);
    if (response.statusCode != 200) _throwHttp(response);

    final text = _extractText(response.body);
    if (text == null || text.isEmpty) return null;

    // 検索ソースを末尾に追記
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return text;
    final candidate = candidates[0] as Map<String, dynamic>;
    final meta = candidate['groundingMetadata'] as Map<String, dynamic>?;
    final chunks = meta?['groundingChunks'] as List?;
    if (chunks != null && chunks.isNotEmpty) {
      final sb = StringBuffer(text);
      sb.write('\n\n---\n**検索ソース:**\n');
      int idx = 1;
      for (final chunk in chunks) {
        final web =
            (chunk as Map<String, dynamic>)['web'] as Map<String, dynamic>?;
        final title = web?['title'] as String? ?? '';
        final uri = web?['uri'] as String? ?? '';
        if (uri.isNotEmpty) {
          sb.write('$idx. [$title]($uri)\n');
          idx++;
        }
      }
      return sb.toString();
    }
    return text;
  }

  /// 画像生成（既定 gemini-2.5-flash-image・設定で変更可） → base64 PNG を返す
  Future<String?> generateImage(String prompt) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return null;

    final imageModel = await getImageModel();
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$imageModel:generateContent?key=$key',
    );

    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'responseModalities': ['IMAGE', 'TEXT']},
    });

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(_imageTimeout);
    if (response.statusCode != 200) _throwHttp(response);

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts = candidates[0]['content']?['parts'] as List?;
    if (parts == null) return null;
    for (final part in parts) {
      final inline = (part as Map<String, dynamic>)['inlineData'] as Map<String, dynamic>?;
      if (inline != null) {
        return inline['data'] as String?; // base64
      }
    }
    return null;
  }

  String? _extractText(String responseBody) {
    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts = candidates[0]['content']?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;
    for (final part in parts) {
      final t = (part as Map<String, dynamic>)['text'] as String?;
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }
}
