import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../services/drive_service.dart';
import '../services/gemini_service.dart';

class NodeEditorScreen extends StatefulWidget {
  final ManidocProject project;
  final ManidocNode node;
  final Future<void> Function() onSave;

  const NodeEditorScreen({
    super.key,
    required this.project,
    required this.node,
    required this.onSave,
  });

  @override
  State<NodeEditorScreen> createState() => _NodeEditorScreenState();
}

class _NodeEditorScreenState extends State<NodeEditorScreen> {
  late WebViewController _webController;
  late TextEditingController _titleController;
  bool _saving = false;
  bool _dirty = false;
  bool _editorReady = false;

  // 画像（Drive上のURL or ローカルファイルパス）
  String? _imageUrl;
  Uint8List? _imageBytes; // ローカル表示用バイト列（Drive URLは認証不可のため）
  bool _imageUploading = false;

  final _driveService = DriveService();
  final _gemini = GeminiService();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.node.title);
    _imageUrl = widget.node.imagePath.isNotEmpty ? widget.node.imagePath : null;

    // Drive画像は起動時にバイトをダウンロード
    if (_imageUrl != null && _imageUrl!.startsWith('drive:')) {
      final fileId = _imageUrl!.substring(6);
      _driveService.downloadFileBytes(fileId).then((bytes) {
        if (bytes != null && mounted) {
          setState(() => _imageBytes = Uint8List.fromList(bytes));
        }
      });
    }

    if (!widget.project.isReadOnly) {
      _titleController.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ContentChanged',
        onMessageReceived: (_) {
          if (!_dirty) setState(() => _dirty = true);
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) async {
          _editorReady = true;
          final escaped = jsonEncode(widget.node.article);
          final isReadOnly = widget.project.isReadOnly ? 'true' : 'false';
          await _webController
              .runJavaScript('initEditor($escaped, $isReadOnly)');
        },
      ))
      ..loadFlutterAsset('assets/editor.html');
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<String> _getMarkdown() async {
    final result = await _webController
        .runJavaScriptReturningResult('getMarkdown()');
    final raw = result.toString();
    try {
      return jsonDecode(raw) as String;
    } catch (_) {
      return raw.replaceAll(RegExp(r'^"|"$'), '');
    }
  }

  Future<void> _save() async {
    if (widget.project.isReadOnly || !_dirty || !_editorReady) return;
    setState(() => _saving = true);

    final markdown = await _getMarkdown();
    final title = _titleController.text.trim();
    if (title.isNotEmpty) widget.node.title = title;
    widget.node.article = markdown;
    await widget.onSave();

    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });
  }

  void _openAiPanel() async {
    final markdown = await _getMarkdown();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AiBottomSheet(
        currentArticle: markdown,
        onInsert: (result) async {
          final current = await _getMarkdown();
          final newContent = current.isEmpty ? result : '$current\n\n$result';
          final escaped = jsonEncode(newContent);
          await _webController.runJavaScript('setMarkdown($escaped)');
          if (!_dirty) setState(() => _dirty = true);
        },
      ),
    );
  }

  void _openImagePanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ImageBottomSheet(
        project: widget.project,
        node: widget.node,
        currentImageUrl: _imageUrl,
        onImageSet: (url, bytes) {
          setState(() {
            _imageUrl = url;
            _imageBytes = bytes;
            widget.node.imagePath = url ?? '';
            _dirty = true;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.project.isReadOnly;

    return Scaffold(
      appBar: AppBar(
        title: readOnly
            ? Text(widget.node.title)
            : TextField(
                controller: _titleController,
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'タイトル',
                ),
              ),
        actions: [
          if (readOnly)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.lock_outline, size: 18),
            ),
          if (!readOnly)
            IconButton(
              icon: Icon(
                Icons.image_outlined,
                color: _imageUrl != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: '画像',
              onPressed: _openImagePanel,
            ),
          if (!readOnly)
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'AIアシスタント',
              onPressed: _openAiPanel,
            ),
          if (_saving || _imageUploading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (!readOnly)
            IconButton(
              icon: Icon(
                Icons.save_outlined,
                color: _dirty ? Theme.of(context).colorScheme.primary : null,
              ),
              tooltip: '保存',
              onPressed: _dirty ? _save : null,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _webController)),
          // 画像プレビュー（設定されている場合）
          if (_imageUrl != null && _imageUrl!.isNotEmpty)
            _buildImagePreview(),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    final url = _imageUrl!;
    final Widget imageWidget;
    if (_imageBytes != null) {
      imageWidget = Image.memory(_imageBytes!, fit: BoxFit.contain);
    } else if (url.startsWith('drive:')) {
      // Driveからダウンロード中
      imageWidget = const Center(child: CircularProgressIndicator());
    } else if (url.startsWith('data:')) {
      imageWidget = Image.memory(base64Decode(url.split(',').last), fit: BoxFit.contain);
    } else if (url.startsWith('http')) {
      imageWidget = Image.network(url, fit: BoxFit.contain);
    } else {
      imageWidget = Image.file(File(url), fit: BoxFit.contain);
    }

    return Container(
      height: 180,
      width: double.infinity,
      color: Colors.black12,
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageWidget,
          if (!widget.project.isReadOnly)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.black45),
                onPressed: () {
                  setState(() {
                    _imageUrl = null;
                    widget.node.imagePath = '';
                    _dirty = true;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 画像ボトムシート
// ─────────────────────────────────────────────
class _ImageBottomSheet extends StatefulWidget {
  final ManidocProject project;
  final ManidocNode node;
  final String? currentImageUrl;
  final void Function(String?, Uint8List?) onImageSet;

  const _ImageBottomSheet({
    required this.project,
    required this.node,
    required this.currentImageUrl,
    required this.onImageSet,
  });

  @override
  State<_ImageBottomSheet> createState() => _ImageBottomSheetState();
}

class _ImageBottomSheetState extends State<_ImageBottomSheet> {
  final _gemini = GeminiService();
  final _driveService = DriveService();
  final _picker = ImagePicker();
  final _aiPromptController = TextEditingController();
  bool _loading = false;
  String? _errorMsg;

  @override
  void dispose() {
    _aiPromptController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (picked == null) return;
      await _uploadAndSet(File(picked.path));
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    }
  }

  Future<void> _uploadAndSet(File file) async {
    setState(() { _loading = true; _errorMsg = null; });

    try {
      final bytes = await file.readAsBytes();
      final folderId = widget.project.driveFolderId;
      String? imageUrl;

      if (folderId != null) {
        // 旧形式（hasProjectFolder=false）はプロジェクトIDのサブフォルダを先に作成
        String projectFolderId = folderId;
        if (!widget.project.hasProjectFolder) {
          projectFolderId = await _driveService.getOrCreateSubFolder(
              widget.project.id, parentId: folderId) ?? folderId;
        }
        final imagesFolderId = await _driveService.getOrCreateSubFolder(
          'images', parentId: projectFolderId);
        if (imagesFolderId != null) {
          final fileName =
              'img_${DateTime.now().millisecondsSinceEpoch}.png';
          final fileId = await _driveService.uploadImage(
            file, fileName, imagesFolderId);
          if (fileId != null) {
            // Drive URLは認証なしで表示不可のためfileIdのみ保存
            imageUrl = 'drive:$fileId';
          }
        }
      }

      imageUrl ??= file.path;

      if (mounted) {
        widget.onImageSet(imageUrl, bytes);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateAiImage() async {
    final prompt = _aiPromptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() { _loading = true; _errorMsg = null; });
    try {
      final base64Str = await _gemini.generateImage(prompt);
      if (base64Str == null) throw Exception('画像データが取得できませんでした');

      final bytes = base64Decode(base64Str);
      final tmpDir = Directory.systemTemp;
      final tmpFile = File(
          '${tmpDir.path}/ai_img_${DateTime.now().millisecondsSinceEpoch}.png');
      await tmpFile.writeAsBytes(bytes);
      await _uploadAndSet(tmpFile);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = _friendlyError(e);
          _loading = false;
        });
      }
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('429') || s.contains('quota')) {
      return 'リクエスト制限に達しました。しばらく待ってから再試行してください。';
    }
    if (s.contains('404') || s.contains('NOT_FOUND')) {
      return '画像生成モデルが見つかりません。有料プランのAPIキーが必要です。';
    }
    return s.length > 150 ? '${s.substring(0, 150)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                Text('画像を設定',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),

                // カメラ・ギャラリー
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('カメラで撮影'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('ギャラリーから'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

                // AI画像生成
                Text('AIで画像を生成',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text('どんな画像を作りたいか説明してください',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _aiPromptController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '例: 青空と桜の木、水彩画風',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _loading ? null : _generateAiImage,
                  child: const Text('AIで画像を生成'),
                ),

                if (_loading) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMsg!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],

                // 現在の画像クリア
                if (widget.currentImageUrl != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  OutlinedButton.icon(
                    onPressed: () {
                      widget.onImageSet(null, null);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('画像を削除',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AIアシスタント ボトムシート（既存）
// ─────────────────────────────────────────────
class _AiBottomSheet extends StatefulWidget {
  final String currentArticle;
  final Future<void> Function(String) onInsert;

  const _AiBottomSheet({
    required this.currentArticle,
    required this.onInsert,
  });

  @override
  State<_AiBottomSheet> createState() => _AiBottomSheetState();
}

class _AiBottomSheetState extends State<_AiBottomSheet> {
  final _geminiService = GeminiService();
  final _customController = TextEditingController();
  final _searchController = TextEditingController();
  bool _loading = false;
  String? _result;

  Future<void> _run(String prompt) async {
    setState(() { _loading = true; _result = null; });
    try {
      final result = await _geminiService.custom(prompt, widget.currentArticle);
      if (!mounted) return;
      setState(() { _loading = false; _result = result; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _result = '⚠ $e'; });
    }
  }

  Future<void> _runWithSearch(String query) async {
    setState(() { _loading = true; _result = null; });
    try {
      final prompt = widget.currentArticle.isEmpty
          ? query
          : '$query\n\n参考情報:\n${widget.currentArticle}';
      final result = await _geminiService.generateWithGrounding(prompt);
      if (!mounted) return;
      setState(() { _loading = false; _result = result; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _result = '⚠ $e'; });
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('続きを書く'),
                      onPressed: _loading
                          ? null
                          : () => _run('この文章の続きを書いてください。'),
                    ),
                    ActionChip(
                      label: const Text('要約する'),
                      onPressed: _loading
                          ? null
                          : () => _run('この文章を簡潔に要約してください。'),
                    ),
                    ActionChip(
                      label: const Text('改善する'),
                      onPressed: _loading
                          ? null
                          : () => _run('この文章をより読みやすく改善してください。'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.search, size: 18, color: Colors.blue),
                    const SizedBox(width: 6),
                    Text('Web検索して回答',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: Colors.blue)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: '検索クエリ・質問を入力',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading
                          ? null
                          : () {
                              final q = _searchController.text.trim();
                              if (q.isNotEmpty) _runWithSearch(q);
                            },
                      child: const Text('検索'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 4),
                Text('カスタム指示',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customController,
                        decoration: const InputDecoration(
                          hintText: 'カスタム指示を入力',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading
                          ? null
                          : () => _run(_customController.text.trim()),
                      child: const Text('実行'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_loading) const Center(child: CircularProgressIndicator()),
                if (_result != null) ...[
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(_result!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      await widget.onInsert(_result!);
                      if (context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('本文に追加'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
