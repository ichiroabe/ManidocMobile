import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'security_helper.dart';

class GeminiService {
  static const _apiKeyPref = 'gemini_api_key';
  static const _modelPref = 'gemini_model';
  static const _defaultModel = 'gemini-2.5-flash-preview-04-17';

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
    return prefs.getString(_modelPref) ?? _defaultModel;
  }

  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _modelPref, model.trim().isEmpty ? _defaultModel : model.trim());
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

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
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

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

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

  /// 画像生成（gemini-2.5-flash-image） → base64 PNG を返す
  Future<String?> generateImage(String prompt) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) return null;

    const imageModel = 'gemini-2.5-flash-image';
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

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

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
