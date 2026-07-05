import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../models/workspace_info.dart';
import '../services/drive_service.dart';
import '../services/gemini_service.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import '../widgets/webview_editor.dart';

class NodeEditorScreen extends StatefulWidget {
  final ManidocProject project;
  final ManidocNode node;
  final Future<void> Function() onSave;
  final bool startInPreview;
  final WorkspaceInfo? workspace;

  const NodeEditorScreen({
    super.key,
    required this.project,
    required this.node,
    required this.onSave,
    this.startInPreview = false,
    this.workspace,
  });

  @override
  State<NodeEditorScreen> createState() => _NodeEditorScreenState();
}

class _NodeEditorScreenState extends State<NodeEditorScreen> {
  late TextEditingController _titleController;
  late TextEditingController _articleController;
  late ManidocNode _currentNode;

  bool _saving = false;
  bool _dirty = false;
  bool _editorReady = false;
  late bool _previewMode = widget.startInPreview;

  String? _imageUrl;
  Uint8List? _imageBytes;
  bool _imageUploading = false;

  final _driveService = DriveService();
  final _localService = LocalStorageService();
  final _gemini = GeminiService();
  final _syncService = SyncService();

  // Android編集時のTiptap WebView（Windowsは従来のTextField）
  final _webEditorKey = GlobalKey<WebViewEditorState>();

  bool get _isWindows => Platform.isWindows;
  bool get _webEditorActive => !_isWindows && !_previewMode;

  @override
  void initState() {
    super.initState();
    _currentNode = widget.node;
    _initForNode(_currentNode);
  }

  void _initForNode(ManidocNode node) {
    _titleController = TextEditingController(text: node.title);
    _imageUrl = node.imagePath.isNotEmpty ? node.imagePath : null;
    _imageBytes = null;

    if (!_isWindows && _imageUrl != null) {
      _resolveAndLoadImage(_imageUrl!);
    }

    _articleController = TextEditingController(text: node.article);
    _editorReady = true;
    _dirty = false;

    widget.project.lastSelectedNodeId = node.id;

    if (!widget.project.isReadOnly) {
      _titleController.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
      _articleController.addListener(() {
        if (!_dirty) setState(() => _dirty = true);
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _articleController.dispose();
    super.dispose();
  }

  Future<void> _resolveAndLoadImage(String url) async {
    try {
      if (url.startsWith('drive:')) {
        // 旧形式: 後方互換
        final fileId = url.substring(6);
        final bytes = await _driveService.downloadFileBytes(fileId);
        if (bytes != null && mounted) {
          setState(() => _imageBytes = Uint8List.fromList(bytes));
        }
        return;
      }
      if (url.startsWith('images/')) {
        final fileName = url.substring('images/'.length);

        // キャッシュを優先で読み込み
        if (widget.workspace != null) {
          final type = widget.project.isReadOnly ? 'windows' : 'android';
          final cached = await _syncService.loadCachedImage(
            widget.workspace!, type, widget.project.id, fileName);
          if (cached != null && mounted) {
            setState(() => _imageBytes = cached);
            return;
          }
        }

        // キャッシュになければDriveからダウンロード
        final folderId = widget.project.driveFolderId;
        if (folderId == null) return;
        String projectFolderId = folderId;
        if (!widget.project.hasProjectFolder) {
          final sub = await _driveService.getOrCreateSubFolder(
              widget.project.id, parentId: folderId);
          if (sub != null) projectFolderId = sub;
        }
        final imagesFolderId = await _driveService.getOrCreateSubFolder(
            'images', parentId: projectFolderId);
        if (imagesFolderId == null) return;
        final fileId = await _driveService.findFileIdByName(
            imagesFolderId, fileName);
        if (fileId == null) return;
        final bytes = await _driveService.downloadFileBytes(fileId);
        if (bytes != null && mounted) {
          final uint8bytes = Uint8List.fromList(bytes);
          setState(() => _imageBytes = uint8bytes);
          // ダウンロードした画像をキャッシュに保存
          if (widget.workspace != null) {
            final type = widget.project.isReadOnly ? 'windows' : 'android';
            await _syncService.cacheImage(
              widget.workspace!, type, widget.project.id, fileName, uint8bytes);
          }
        }
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // ページめくりナビゲーション（深さ優先）
  // ─────────────────────────────────────────
  List<ManidocNode> _flattenDepthFirst() {
    final result = <ManidocNode>[];
    void walk(ManidocNode n) {
      result.add(n);
      for (final c in n.children) {
        walk(c);
      }
    }
    for (final r in widget.project.rootNodes) {
      walk(r);
    }
    return result;
  }

  Future<void> _navigateSibling(bool forward) async {
    final flat = _flattenDepthFirst();
    final idx = flat.indexWhere((n) => n.id == _currentNode.id);
    if (idx < 0) return;
    final nextIdx = forward ? idx + 1 : idx - 1;
    if (nextIdx < 0 || nextIdx >= flat.length) return;
    await _switchToNode(flat[nextIdx]);
  }

  /// ノードリンク（#node:ID）タップでそのノードへジャンプ
  Future<void> _jumpToNode(String nodeId) async {
    final flat = _flattenDepthFirst();
    final idx = flat.indexWhere((n) => n.id == nodeId);
    if (idx < 0 || flat[idx].id == _currentNode.id) return;
    await _switchToNode(flat[idx]);
  }

  /// ページめくり・ノードリンク共通の切替処理（必要なら保存してから移動）
  Future<void> _switchToNode(ManidocNode target) async {
    if (_dirty && !widget.project.isReadOnly) {
      await _save();
    }

    if (!mounted) return;

    // コントローラーを破棄して新しいノードに切り替え
    _titleController.dispose();
    _articleController.dispose();

    setState(() {
      _currentNode = target;
      _previewMode = true;
      _initForNode(_currentNode);
    });
  }

  /// 「[[」補完用のノード一覧（id/タイトル/親階層パス）をJSONで返す
  String _nodeListJson() {
    final items = <Map<String, String>>[];
    void walk(List<ManidocNode> nodes, String parentPath) {
      for (final n in nodes) {
        items.add({'id': n.id, 'title': n.title, 'path': parentPath});
        final childPath = parentPath.isEmpty ? n.title : '$parentPath > ${n.title}';
        walk(n.children, childPath);
      }
    }
    walk(widget.project.rootNodes, '');
    return jsonEncode(items);
  }

  Future<String> _getMarkdown() async {
    // WebViewエディタ表示中はデバウンス中の未反映分があり得るため直接取得
    final web = _webEditorActive ? _webEditorKey.currentState : null;
    if (web != null && web.isReady) {
      final md = await web.getMarkdown();
      _articleController.text = md;
      return md;
    }
    return _articleController.text;
  }

  Future<void> _setMarkdown(String markdown) async {
    _articleController.text = markdown;
    final web = _webEditorActive ? _webEditorKey.currentState : null;
    if (web != null && web.isReady) {
      await web.setMarkdown(markdown);
    }
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    if (widget.project.isReadOnly || !_dirty || !_editorReady) return;
    setState(() => _saving = true);

    final markdown = await _getMarkdown();
    final title = _titleController.text.trim();
    if (title.isNotEmpty) _currentNode.title = title;
    _currentNode.article = markdown;
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
          await _setMarkdown(newContent);
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
        node: _currentNode,
        currentImageUrl: _imageUrl,
        workspace: widget.workspace,
        onImageSet: (url, bytes) {
          setState(() {
            _imageUrl = url;
            _imageBytes = bytes;
            _currentNode.imagePath = url ?? '';
            _dirty = true;
          });
        },
      ),
    );
  }

  void _wrapSelection(String left, String right) {
    final sel = _articleController.selection;
    final text = _articleController.text;
    if (!sel.isValid) {
      final insert = '$left$right';
      _articleController.text = text + insert;
      _articleController.selection = TextSelection.collapsed(
        offset: text.length + left.length,
      );
      return;
    }
    final start = sel.start;
    final end = sel.end;
    final selected = text.substring(start, end);
    final newText = text.replaceRange(start, end, '$left$selected$right');
    _articleController.text = newText;
    _articleController.selection = TextSelection(
      baseOffset: start + left.length,
      extentOffset: start + left.length + selected.length,
    );
  }

  void _insertLinePrefix(String prefix) {
    final sel = _articleController.selection;
    final text = _articleController.text;
    final pos = sel.isValid ? sel.start : text.length;
    int lineStart = text.lastIndexOf('\n', pos - 1) + 1;
    final newText = text.replaceRange(lineStart, lineStart, prefix);
    _articleController.text = newText;
    _articleController.selection = TextSelection.collapsed(
      offset: pos + prefix.length,
    );
  }

  void _insertAtCursor(String snippet, {int? cursorOffset}) {
    final sel = _articleController.selection;
    final text = _articleController.text;
    final pos = sel.isValid ? sel.start : text.length;
    final newText = text.replaceRange(pos, sel.isValid ? sel.end : pos, snippet);
    _articleController.text = newText;
    _articleController.selection = TextSelection.collapsed(
      offset: pos + (cursorOffset ?? snippet.length),
    );
  }

  Widget _buildToolbar() {
    final items = <Widget>[
      _tbBtn('H1', 'H1', () => _insertLinePrefix('# ')),
      _tbBtn('H2', 'H2', () => _insertLinePrefix('## ')),
      _tbBtn('H3', 'H3', () => _insertLinePrefix('### ')),
      _tbIcon(Icons.format_bold, '太字', () => _wrapSelection('**', '**')),
      _tbIcon(Icons.format_italic, '斜体', () => _wrapSelection('*', '*')),
      _tbIcon(Icons.format_strikethrough, '取消線', () => _wrapSelection('~~', '~~')),
      _tbIcon(Icons.format_list_bulleted, '箇条書き', () => _insertLinePrefix('- ')),
      _tbIcon(Icons.format_list_numbered, '番号付き', () => _insertLinePrefix('1. ')),
      _tbIcon(Icons.check_box_outlined, 'チェック', () => _insertLinePrefix('- [ ] ')),
      _tbIcon(Icons.format_quote, '引用', () => _insertLinePrefix('> ')),
      _tbIcon(Icons.code, 'コード', () => _wrapSelection('`', '`')),
      _tbIcon(Icons.data_object, 'コードブロック',
          () => _insertAtCursor('\n```\n\n```\n', cursorOffset: 5)),
      _tbIcon(Icons.link, 'リンク',
          () => _insertAtCursor('[](url)', cursorOffset: 1)),
      _tbIcon(Icons.horizontal_rule, '区切り線',
          () => _insertAtCursor('\n---\n')),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: items,
      ),
    );
  }

  Widget _tbBtn(String label, String tip, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Tooltip(
        message: tip,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 36),
          ),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _tbIcon(IconData icon, String tip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tip,
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildEditor() {
    if (_previewMode) {
      return Markdown(
        data: _articleController.text,
        padding: const EdgeInsets.all(16),
        selectable: true,
        onTapLink: (text, href, title) {
          if (href != null && href.startsWith('#node:')) {
            _jumpToNode(href.substring('#node:'.length));
          }
        },
      );
    }
    if (!_isWindows) {
      // Android: Tiptap WYSIWYGエディタ（ツールバーはWebView内）
      return WebViewEditor(
        key: _webEditorKey,
        initialContent: _articleController.text,
        readOnly: widget.project.isReadOnly,
        onContentChanged: (md) => _articleController.text = md,
        nodeListJson: _nodeListJson(),
        onNodeLinkTap: _jumpToNode,
      );
    }
    return Column(
      children: [
        if (!widget.project.isReadOnly) _buildToolbar(),
        if (!widget.project.isReadOnly) const Divider(height: 1),
        Expanded(
          child: TextField(
            controller: _articleController,
            maxLines: null,
            expands: true,
            readOnly: widget.project.isReadOnly,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 14),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
              hintText: 'Markdownで記述...',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.project.isReadOnly;

    return Scaffold(
      appBar: AppBar(
        title: readOnly
            ? Text(_currentNode.title)
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
          IconButton(
            icon: Icon(_previewMode ? Icons.edit_outlined : Icons.visibility_outlined),
            tooltip: _previewMode ? '編集' : 'プレビュー',
            onPressed: () async {
              if (_webEditorActive) {
                // 編集→プレビュー: デバウンス中の内容を取り込んでから切替
                await _getMarkdown();
              }
              if (!mounted) return;
              setState(() => _previewMode = !_previewMode);
            },
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v.abs() < 300) return;
          _navigateSibling(v < 0); // 左スワイプ=次, 右スワイプ=前
        },
        child: Column(
          children: [
            Expanded(child: _buildEditor()),
            if (_imageUrl != null && _imageUrl!.isNotEmpty)
              _buildImagePreview(),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    final url = _imageUrl!;
    final Widget imageWidget;
    if (_imageBytes != null) {
      imageWidget = Image.memory(_imageBytes!, fit: BoxFit.contain);
    } else if (url.startsWith('drive:') || url.startsWith('images/')) {
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
          GestureDetector(
            onDoubleTap: () => _showFullScreenImage(imageWidget),
            child: imageWidget,
          ),
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
                    _currentNode.imagePath = '';
                    _dirty = true;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showFullScreenImage(Widget imageWidget) {
    showDialog(
      context: context,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Center(child: imageWidget),
        ),
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
  final WorkspaceInfo? workspace;

  const _ImageBottomSheet({
    required this.project,
    required this.node,
    required this.currentImageUrl,
    required this.onImageSet,
    this.workspace,
  });

  @override
  State<_ImageBottomSheet> createState() => _ImageBottomSheetState();
}

class _ImageBottomSheetState extends State<_ImageBottomSheet> {
  final _gemini = GeminiService();
  final _driveService = DriveService();
  final _localService = LocalStorageService();
  final _syncService = SyncService();
  final _aiPromptController = TextEditingController();
  bool _loading = false;
  String? _errorMsg;

  bool get _isWindows => Platform.isWindows;

  @override
  void dispose() {
    _aiPromptController.dispose();
    super.dispose();
  }

  Future<void> _pickFromSource(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: source, imageQuality: 90);
      if (xfile == null) return;
      await _uploadAndSet(File(xfile.path));
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    }
  }

  Future<void> _pickImageWindows() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      await _saveAndSetImage(File(path));
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    }
  }

  /// Windows: ローカルフォルダに画像を保存
  Future<void> _saveAndSetImage(File file) async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final bytes = await file.readAsBytes();

      final localPath = widget.project.localFilePath;
      if (localPath != null) {
        final baseName = File(localPath).uri.pathSegments.last.replaceAll('.json', '');
        final projDir = '${File(localPath).parent.path}/$baseName';
        final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.png';
        final savedPath = await _localService.saveImage(file, fileName, projDir);
        if (savedPath != null && mounted) {
          widget.onImageSet(savedPath, bytes);
          Navigator.pop(context);
          return;
        }
      }

      if (mounted) {
        widget.onImageSet(file.path, bytes);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Android: Driveにアップロード（オフライン時はキャッシュに保存してdirty）
  Future<void> _uploadAndSet(File file) async {
    setState(() { _loading = true; _errorMsg = null; });

    try {
      final bytes = await file.readAsBytes();
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.png';
      final imageUrl = 'images/$fileName';
      final online = await _syncService.isOnline();

      if (online) {
        // オンライン: Driveにアップロード
        final folderId = widget.project.driveFolderId;
        bool uploaded = false;

        if (folderId != null) {
          String projectFolderId = folderId;
          if (!widget.project.hasProjectFolder) {
            projectFolderId = await _driveService.getOrCreateSubFolder(
                widget.project.id, parentId: folderId) ?? folderId;
          }
          final imagesFolderId = await _driveService.getOrCreateSubFolder(
            'images', parentId: projectFolderId);
          if (imagesFolderId != null) {
            final fileId = await _driveService.uploadImage(
              file, fileName, imagesFolderId);
            uploaded = fileId != null;
          }
        }

        if (!uploaded) {
          setState(() => _errorMsg = 'Drive にアップロードできませんでした');
          return;
        }
      }

      // キャッシュに保存（オンライン・オフライン共通）
      if (widget.workspace != null) {
        final type = widget.project.isReadOnly ? 'windows' : 'android';
        await _syncService.cacheImage(
          widget.workspace!, type, widget.project.id, fileName, bytes);
      }

      if (!online) {
        // オフライン: プロジェクトをdirtyにして次回同期時にアップロード
        widget.project.isDirty = true;
      }

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

      if (_isWindows) {
        await _saveAndSetImage(tmpFile);
      } else {
        await _uploadAndSet(tmpFile);
      }
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

                if (_isWindows)
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _pickImageWindows,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('ファイルから選択'),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : () => _pickFromSource(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('カメラで撮影'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _loading ? null : () => _pickFromSource(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('ギャラリーから'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),

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
// AIアシスタント ボトムシート
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
