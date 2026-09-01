import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../dialogs/card_color_dialog.dart';
import '../dialogs/tag_dialog.dart';
import '../dialogs/tag_manager_dialog.dart';
import '../models/manidoc_project.dart';
import '../models/tag_definition.dart';
import '../models/workspace_info.dart';
import '../services/color_utils.dart';
import '../services/drive_service.dart';
import '../services/html_import.dart';
import '../services/local_cache_service.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import '../services/workspace_settings_service.dart';
import 'ai_agent_screen.dart';
import 'node_list_screen.dart';
import 'settings_screen.dart';
import 'workspace_select_screen.dart';

enum ProjectSort {
  modifiedDesc,
  modifiedAsc,
  nameAsc,
  nameDesc,
  createdDesc,
  tag,
}

class HomeScreen extends StatefulWidget {
  final WorkspaceInfo workspace;

  const HomeScreen({super.key, required this.workspace});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _driveService = DriveService();
  final _localService = LocalStorageService();
  final _syncService = SyncService();
  final _cacheService = LocalCacheService();
  final _settingsService = WorkspaceSettingsService();
  late final TabController _tabController;

  /// ワークスペースのタグ定義（名前 + 色）。workspace.settings.json から読む。
  List<TagDefinition> _workspaceTags = [];

  // ── 複数選択（一括色・一括タグ・色コピー/貼り付け） ──
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  String? _copiedFore;
  String? _copiedBack;
  bool get _hasCopiedColor => _copiedFore != null || _copiedBack != null;

  bool get _isWindows => Platform.isWindows;

  // ワークスペースは読み書き一本。以前は Windows(読み取り専用)と
  // Android(読み書き)に分けていたが、SAF で全体を書けるようになったため統合した。
  List<ManidocProject> _projects = [];
  List<ManidocProject> _localProjects = [];
  bool _loading = true;
  bool _loadingLocal = true;
  SyncStatus _syncStatus = SyncStatus.idle;
  ProjectSort _sort = ProjectSort.modifiedDesc;

  /// 読み込み中の進み具合。null なら読み込んでいない。
  SyncProgress? _progress;

  /// 読み込めなかった理由。無反応で終わらせないために必ず出す。
  String? _loadError;

  static const _sortPrefKey = 'projectSortMode';

  @override
  void initState() {
    super.initState();
    _loadSortPref();
    _tabController = TabController(length: 2, vsync: this);
    if (_isWindows) {
      _loadLocal();
    } else {
      _loadWithCacheFirst();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── タグ定義（ワークスペース設定） ──
  Future<void> _loadTags() async {
    try {
      final tags = await _settingsService.loadTags(widget.workspace, _isWindows);
      if (mounted) setState(() => _workspaceTags = tags);
    } catch (_) {
      // タグが読めなくても一覧表示は続ける
    }
  }

  TagDefinition? _tagDef(String name) {
    for (final t in _workspaceTags) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// タグ名 → 色（定義が無い・色なしなら null）
  Color? _tagColor(String name) {
    final def = _tagDef(name);
    if (def == null || def.color.isEmpty) return null;
    return colorFromHex(def.color);
  }

  // ── ソート設定 ──
  Future<void> _loadSortPref() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_sortPrefKey);
    if (name == null) return;
    final sort = ProjectSort.values
        .where((s) => s.name == name)
        .firstOrNull;
    if (sort != null && mounted) {
      setState(() => _sort = sort);
    }
  }

  Future<void> _changeSort(ProjectSort sort) async {
    setState(() => _sort = sort);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortPrefKey, sort.name);
  }

  List<ManidocProject> _sortedProjects(List<ManidocProject> projects) {
    final sorted = List<ManidocProject>.from(projects);
    switch (_sort) {
      case ProjectSort.modifiedDesc:
        sorted.sort((a, b) => b.lastModifiedAt.compareTo(a.lastModifiedAt));
      case ProjectSort.modifiedAsc:
        sorted.sort((a, b) => a.lastModifiedAt.compareTo(b.lastModifiedAt));
      case ProjectSort.nameAsc:
        sorted.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case ProjectSort.nameDesc:
        sorted.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      case ProjectSort.createdDesc:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ProjectSort.tag:
        // タグ名の昇順を一次キー（無タグは末尾）、その中は更新日時の新しい順。
        sorted.sort((a, b) {
          final ta = a.tag.trim();
          final tb = b.tag.trim();
          if (ta.isEmpty != tb.isEmpty) return ta.isEmpty ? 1 : -1;
          final c = ta.toLowerCase().compareTo(tb.toLowerCase());
          if (c != 0) return c;
          return b.lastModifiedAt.compareTo(a.lastModifiedAt);
        });
    }
    return sorted;
  }

  /// 一覧に出ているプロジェクトから、使われているタグの一覧を作る（昇順・重複なし）。
  List<String> _collectTags(List<ManidocProject> projects) {
    final names = <String>{
      for (final p in projects)
        if (p.tag.trim().isNotEmpty) p.tag.trim(),
    };
    final list = names.toList()..sort();
    return list;
  }

  // ── キャッシュ優先読み込み（Android） ──
  Future<void> _loadWithCacheFirst() async {
    // 1. まずキャッシュからすぐ表示
    final cached = await _cacheService.loadProjects(
        widget.workspace, SyncService.workspaceType);

    if (!mounted) return;
    setState(() {
      if (cached.isNotEmpty) {
        _projects = cached;
        _loading = false;
      }
    });

    // タグ定義も読む（一覧と並行）
    _loadTags();

    // 2. バックグラウンドでワークスペースから同期
    await _syncFromDrive();
  }

  // ── ワークスペース同期（Android） ──
  Future<void> _syncFromDrive() async {
    if (_isWindows) return;

    if (mounted) {
      setState(() {
        _syncStatus = SyncStatus.syncing;
        _loadError = null;
        _progress = const SyncProgress(SyncPhase.scanning);
      });
    }

    try {
      // まずdirtyなプロジェクトをPush
      await _syncService.pushDirtyProjects(
          widget.workspace, SyncService.workspaceType);

      // ワークスペース全体をPull（_android など既存のサブフォルダ内も走査される）
      final projects = await _syncService.pullProjects(
        widget.workspace,
        widget.workspace.windowsFolderId,
        SyncService.workspaceType,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (!mounted) return;
      // 画像を待たずに一覧を出す
      setState(() {
        _projects = projects;
        _loading = false;
        _syncStatus = SyncStatus.idle;
      });

      // 画像の取り込みは枚数次第で数分かかる。一覧を出した後に回す。
      await _syncService.cacheProjectImages(
        widget.workspace,
        SyncService.workspaceType,
        projects,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncStatus = SyncStatus.error;
        _loadError = e.toString();
      });
    } finally {
      // どの経路でも必ず読み込み表示を終わらせる
      if (mounted) {
        setState(() {
          _loading = false;
          _progress = null;
        });
      }
    }
  }

  // ── ローカル（Windows Flutter版） ──
  Future<void> _loadLocal() async {
    setState(() => _loadingLocal = true);
    final path = widget.workspace.localPath;
    if (path == null) {
      setState(() => _loadingLocal = false);
      return;
    }
    final files = await _localService.listProjectFiles(path);
    final projects = <ManidocProject>[];
    for (final info in files) {
      final project = await _localService.readProject(info.filePath);
      if (project != null) projects.add(project);
    }
    if (!mounted) return;
    setState(() {
      _localProjects = projects;
      _loadingLocal = false;
    });
    _loadTags();
  }

  Future<void> _createProject() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新規プロジェクト'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'プロジェクト名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: const Text('作成'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => nameController.dispose());

    if (name == null || name.isEmpty) return;

    await _saveNewProject(ManidocProject.create(name));
  }

  /// 作成済み・取り込み済みのプロジェクトをワークスペースへ保存する。
  /// 新規作成・Webインポートで共通。[open] が true なら保存後に開く。
  Future<void> _saveNewProject(ManidocProject project,
      {bool open = false}) async {
    if (_isWindows) {
      final path = widget.workspace.localPath;
      if (path == null) return;
      final ok = await _localService.createProject(project, path);
      if (!mounted) return;
      if (ok) {
        _loadLocal();
        if (open) _openProject(project);
      }
    } else {
      // 新規プロジェクトはワークスペース直下に作る（デスクトップ版と同じ場所）
      final workspaceFolderId = widget.workspace.windowsFolderId;
      project.driveFolderId = workspaceFolderId;

      final fileId = await _driveService.createProject(
        project,
        workspaceFolderId,
      );
      if (!mounted) return;

      if (fileId != null) {
        project.driveFileId = fileId;
        // キャッシュにも保存
        await _cacheService.saveProject(
            widget.workspace, SyncService.workspaceType, project);
        _syncFromDrive();
        if (open) _openProject(project);
      } else {
        // ワークスペースに書けなかった: 端末内にだけ残して次の同期に回す
        project.isDirty = true;
        await _cacheService.saveProject(
            widget.workspace, SyncService.workspaceType, project);
        if (!mounted) return;
        setState(() {
          _projects.add(project);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ワークスペースに作成できませんでした。'
                '端末内にのみ保存しています。'),
            duration: Duration(seconds: 5),
          ),
        );
        if (open) _openProject(project);
      }
    }
  }

  /// 🌐 WebページのURLを取り込んでプロジェクト化する（openManidoc 準拠）。
  /// 見出し(h1〜h6)を階層ノードに、本文をMarkdown風の記事に変換する。
  Future<void> _importWeb() async {
    final controller = TextEditingController(text: 'https://');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Webページを取り込む'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('取り込む'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (!mounted || url == null || url.isEmpty || url == 'https://') return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('取り込んでいます…'), duration: Duration(seconds: 3)),
    );
    try {
      final project = await HtmlImport.importUrl(url);
      if (!mounted) return;
      await _saveNewProject(project, open: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${project.name}」を取り込みました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取り込みに失敗しました: $e')),
      );
    }
  }

  void _openProject(ManidocProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NodeListScreen(
          project: project,
          workspace: _isWindows ? null : widget.workspace,
        ),
      ),
    ).then((_) {
      if (_isWindows) {
        _loadLocal();
      } else {
        // キャッシュから再読み込み＋バックグラウンド同期
        _loadWithCacheFirst();
      }
    });
  }

  Future<void> _renameProject(ManidocProject project) async {
    final controller = TextEditingController(text: project.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('名前を変更'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'プロジェクト名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('変更'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (!mounted || name == null || name.isEmpty || name == project.name) {
      return;
    }
    project.name = name;

    if (_isWindows) {
      await _localService.updateProject(project);
      if (!mounted) return;
      _loadLocal();
    } else {
      final result = await _syncService.saveProject(
          widget.workspace, SyncService.workspaceType, project);
      if (!mounted) return;
      if (result == SaveResult.conflict) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('このプロジェクトは別の端末で更新されています。'
                '上書きを避けたため、変更は端末内にのみ保存しました。'),
            duration: Duration(seconds: 6),
          ),
        );
      }
      setState(() {});
    }
  }

  /// 変更したプロジェクトを保存する（名前変更・タグ・色の各編集で共通）。
  Future<void> _persistEdit(ManidocProject project) async {
    if (_isWindows) {
      await _localService.updateProject(project);
      if (!mounted) return;
      _loadLocal();
    } else {
      final result = await _syncService.saveProject(
          widget.workspace, SyncService.workspaceType, project);
      if (!mounted) return;
      if (result == SaveResult.conflict) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('このプロジェクトは別の端末で更新されています。'
                '上書きを避けたため、変更は端末内にのみ保存しました。'),
            duration: Duration(seconds: 6),
          ),
        );
      }
      setState(() {});
    }
  }

  List<ManidocProject> get _currentProjects =>
      _isWindows ? _localProjects : _projects;

  /// タグ候補: 定義済みタグ + 実際に使われているタグ（昇順・重複なし）
  List<String> _allTagNames() {
    final names = <String>{
      for (final t in _workspaceTags)
        if (t.name.trim().isNotEmpty) t.name.trim(),
      ..._collectTags(_currentProjects),
    };
    final list = names.toList()..sort();
    return list;
  }

  /// タグの色をプロジェクトのタイルへ適用する。背景色をタグ色にし、
  /// 文字色は読みやすい方（白/黒）を自動で入れる。色なしなら既定へ戻す。
  void _applyTagColorToProject(ManidocProject project, String tagColorHex) {
    final bg = colorFromHex(tagColorHex);
    if (bg == null) {
      project.cardBackColorHex = '';
      project.cardForeColorHex = '';
    } else {
      project.cardBackColorHex = tagColorHex;
      project.cardForeColorHex = hexFromColor(contrastForegroundFor(bg));
    }
  }

  /// 複数プロジェクトを保存する（1件ずつ保存し、最後に一度だけ再読込）。
  Future<void> _persistMany(List<ManidocProject> projects) async {
    if (projects.isEmpty) return;
    var conflict = false;
    for (final project in projects) {
      if (_isWindows) {
        await _localService.updateProject(project);
      } else {
        final result = await _syncService.saveProject(
            widget.workspace, SyncService.workspaceType, project);
        if (result == SaveResult.conflict) conflict = true;
      }
    }
    if (!mounted) return;
    if (conflict) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('一部のプロジェクトは別の端末で更新されていたため、'
              '変更は端末内にのみ保存しました。'),
          duration: Duration(seconds: 6),
        ),
      );
    }
    if (_isWindows) {
      _loadLocal();
    } else {
      setState(() {});
    }
  }

  /// 未定義のタグ名なら定義に追加して settings.json に保存する（openManidoc 準拠）。
  Future<void> _ensureTagRegistered(String name) async {
    final n = name.trim();
    if (n.isEmpty || _tagDef(n) != null) return;
    final updated = [..._workspaceTags, TagDefinition(name: n)];
    await _settingsService.saveTags(widget.workspace, _isWindows, updated);
    if (mounted) setState(() => _workspaceTags = updated);
  }

  /// 🏷 タグを編集する（openManidoc 準拠）。タグに色があればタイルにも反映する。
  Future<void> _editTag(ManidocProject project) async {
    final tag = await showTagDialog(context, project.tag, _allTagNames());
    if (!mounted || tag == null || tag == project.tag) return;
    project.tag = tag;
    // タグに色が定義されていればタイルへ適用する
    final color = _tagColor(tag);
    if (color != null) _applyTagColorToProject(project, hexFromColor(color));
    await _ensureTagRegistered(tag);
    await _persistEdit(project);
  }

  /// 🎨 タイルの色（文字色/背景色）を編集する（openManidoc 準拠）。
  Future<void> _editCardColor(ManidocProject project) async {
    final result = await showCardColorDialog(
      context,
      initialFore: project.cardForeColorHex,
      initialBack: project.cardBackColorHex,
    );
    if (!mounted || result == null) return;
    if (result.fore == project.cardForeColorHex &&
        result.back == project.cardBackColorHex) {
      return;
    }
    project.cardForeColorHex = result.fore;
    project.cardBackColorHex = result.back;
    await _persistEdit(project);
  }

  /// 🏷 タグ管理（追加/改名/色設定/削除）。保存すると各タグの色を、
  /// そのタグが付いた全プロジェクトのタイルへ即反映する。
  Future<void> _openTagManager() async {
    final edited = await showTagManagerDialog(context, _workspaceTags);
    if (!mounted || edited == null) return;

    // まず設定を保存
    await _settingsService.saveTags(widget.workspace, _isWindows, edited);
    if (!mounted) return;
    setState(() => _workspaceTags = edited);

    // 各タグの色を、そのタグが付いた全プロジェクトへ反映する
    final colorByTag = {for (final t in edited) t.name: t.color};
    final changed = <ManidocProject>[];
    for (final p in _currentProjects) {
      if (p.tag.isEmpty) continue;
      final hex = colorByTag[p.tag];
      if (hex == null || hex.isEmpty) continue;
      final fore = hexFromColor(contrastForegroundFor(colorFromHex(hex)!));
      if (p.cardBackColorHex == hex && p.cardForeColorHex == fore) continue;
      _applyTagColorToProject(p, hex);
      changed.add(p);
    }
    await _persistMany(changed);
  }

  // ── 色のコピー / 貼り付け ──
  void _copyColor(ManidocProject project) {
    setState(() {
      _copiedFore = project.cardForeColorHex;
      _copiedBack = project.cardBackColorHex;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('色をコピーしました'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _pasteColor(ManidocProject project) async {
    if (!_hasCopiedColor) return;
    // 選択モードで対象自身も選択中なら、選択した全件へ適用する
    final targets = _selectionMode && _selectedIds.contains(project.id)
        ? _selectedProjects
        : [project];
    for (final p in targets) {
      p.cardForeColorHex = _copiedFore ?? '';
      p.cardBackColorHex = _copiedBack ?? '';
    }
    await _persistMany(targets);
  }

  // ── 複数選択 ──
  List<ManidocProject> get _selectedProjects =>
      _currentProjects.where((p) => _selectedIds.contains(p.id)).toList();

  void _enterSelection(ManidocProject project) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..add(project.id);
    });
  }

  void _toggleSelect(ManidocProject project) {
    setState(() {
      if (!_selectedIds.remove(project.id)) _selectedIds.add(project.id);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 選択中のプロジェクトへ色を一括設定する。
  Future<void> _bulkColor() async {
    final targets = _selectedProjects;
    if (targets.isEmpty) return;
    final first = targets.first;
    final result = await showCardColorDialog(
      context,
      initialFore: first.cardForeColorHex,
      initialBack: first.cardBackColorHex,
    );
    if (!mounted || result == null) return;
    for (final p in targets) {
      p.cardForeColorHex = result.fore;
      p.cardBackColorHex = result.back;
    }
    await _persistMany(targets);
    if (mounted) _exitSelection();
  }

  /// 選択中のプロジェクトへタグを一括設定する。タグ色があればタイルへも反映。
  Future<void> _bulkTag() async {
    final targets = _selectedProjects;
    if (targets.isEmpty) return;
    final tag = await showTagDialog(context, '', _allTagNames());
    if (!mounted || tag == null) return;
    final color = _tagColor(tag);
    for (final p in targets) {
      p.tag = tag;
      if (color != null) _applyTagColorToProject(p, hexFromColor(color));
    }
    await _ensureTagRegistered(tag);
    await _persistMany(targets);
    if (mounted) _exitSelection();
  }

  Future<void> _deleteProject(ManidocProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text(_isWindows
            ? '「${project.name}」を削除しますか？\n（ローカルファイルも削除されます）'
            : '「${project.name}」を削除しますか？\n（Google Drive上のファイルも削除されます）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    if (_isWindows) {
      await _localService.deleteProject(project);
      if (!mounted) return;
      _loadLocal();
    } else {
      // キャッシュから削除
      await _cacheService.deleteProject(
          widget.workspace, SyncService.workspaceType, project.id);
      // ワークスペースからも削除
      if (project.driveFileId != null) {
        await _driveService.deleteFile(project.driveFileId!);
      }
      if (!mounted) return;
      setState(() {
        _projects.removeWhere((p) => p.id == project.id);
      });
    }
  }

  Widget _buildSyncIndicator() {
    if (_isWindows) return const SizedBox.shrink();

    IconData icon;
    Color color;
    String tooltip;

    switch (_syncStatus) {
      case SyncStatus.idle:
        final dirtyCount = _projects.where((p) => p.isDirty).length;
        if (dirtyCount > 0) {
          icon = Icons.cloud_upload_outlined;
          color = Colors.orange;
          tooltip = '未同期: $dirtyCount件';
        } else {
          icon = Icons.cloud_done_outlined;
          color = Colors.green;
          tooltip = '同期済み';
        }
      case SyncStatus.syncing:
        return const Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case SyncStatus.error:
        icon = Icons.cloud_off_outlined;
        color = Colors.red;
        tooltip = '同期エラー';
    }

    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: _syncFromDrive,
    );
  }

  /// 進み具合の文言。「何をしていて、あと何件か」が分かるようにする。
  String _progressLabel(SyncProgress p) {
    switch (p.phase) {
      case SyncPhase.scanning:
        return 'フォルダを調べています…';
      case SyncPhase.reading:
        return 'プロジェクトを読み込んでいます  ${p.done} / ${p.total}';
      case SyncPhase.images:
        return '画像を取り込んでいます  ${p.done} / ${p.total}';
    }
  }

  /// 初回読み込み中（一覧がまだ無い）の表示
  Widget _buildLoadingView() {
    final p = _progress;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LinearProgressIndicator(
              value: (p != null && p.total > 0) ? p.done / p.total : null,
            ),
            const SizedBox(height: 16),
            Text(
              p == null ? '読み込んでいます…' : _progressLabel(p),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Google ドライブのフォルダは、件数が多いと数分かかることがあります。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一覧を出した後の、裏で進んでいる処理の帯
  Widget _buildProgressStrip() {
    final p = _progress;
    if (p == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(
          minHeight: 2,
          value: p.total > 0 ? p.done / p.total : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _progressLabel(p),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 読み込めなかったときの表示。原因を出して、やり直せるようにする。
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('ワークスペースを読み込めませんでした'),
            const SizedBox(height: 8),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'フォルダへのアクセス権が外れている場合は、'
              'ワークスペースを登録し直してください。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _syncFromDrive,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectList(
    List<ManidocProject> projects,
    bool loading,
    bool readOnly,
  ) {
    if (loading) {
      return _buildLoadingView();
    }
    if (projects.isEmpty && _loadError != null) {
      return _buildErrorView();
    }
    if (projects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(readOnly ? 'プロジェクトがありません' : 'まだプロジェクトがありません'),
            if (!readOnly) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _createProject,
                icon: const Icon(Icons.add),
                label: const Text('作成する'),
              ),
            ],
          ],
        ),
      );
    }
    final sorted = _sortedProjects(projects);
    return RefreshIndicator(
      onRefresh: _isWindows
          ? _loadLocal
          : (readOnly ? _syncFromDrive : _syncFromDrive),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80),
        itemCount: sorted.length,
        itemBuilder: (context, i) {
          final project = sorted[i];
          // デスクトップ版のタイル色に合わせて行の色を決める。
          // 無ければ従来どおりテーマの既定色にフォールバックする。
          final backColor = project.cardBackColor;
          final foreColor = project.cardForeColor;
          final defaultFore = Theme.of(context).colorScheme.onSurface;
          final iconColor = foreColor ?? defaultFore;
          final subtitleColor =
              (foreColor ?? Theme.of(context).colorScheme.onSurfaceVariant)
                  .withValues(alpha: 0.75);
          final selected = _selectedIds.contains(project.id);
          return ListTile(
            selected: selected,
            selectedTileColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
            tileColor: backColor,
            leading: _selectionMode
                ? Checkbox(
                    value: selected,
                    onChanged: readOnly ? null : (_) => _toggleSelect(project),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_outlined, color: iconColor),
                      if (project.isDirty) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
            title: Text(
              project.name,
              style: foreColor != null ? TextStyle(color: foreColor) : null,
            ),
            subtitle: Row(
              children: [
                Text(
                  _formatDate(project.lastModifiedAt),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: subtitleColor),
                ),
                if (project.tag.trim().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(child: _buildTagChip(context, project, foreColor)),
                ],
              ],
            ),
            trailing: readOnly
                ? Icon(Icons.lock_outline, size: 16, color: iconColor)
                : _selectionMode
                    ? null
                    : PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: iconColor),
                        onSelected: (value) {
                          if (value == 'rename') _renameProject(project);
                          if (value == 'tag') _editTag(project);
                          if (value == 'color') _editCardColor(project);
                          if (value == 'copyColor') _copyColor(project);
                          if (value == 'pasteColor') _pasteColor(project);
                          if (value == 'select') _enterSelection(project);
                          if (value == 'delete') _deleteProject(project);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('名前を変更'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'tag',
                            child: ListTile(
                              leading: Icon(Icons.local_offer_outlined),
                              title: Text('タグを編集'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'color',
                            child: ListTile(
                              leading: Icon(Icons.palette_outlined),
                              title: Text('色を変更'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'copyColor',
                            child: ListTile(
                              leading: Icon(Icons.copy_outlined),
                              title: Text('色をコピー'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'pasteColor',
                            enabled: _hasCopiedColor,
                            child: const ListTile(
                              leading: Icon(Icons.paste_outlined),
                              title: Text('色を貼り付け'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'select',
                            child: ListTile(
                              leading: Icon(Icons.check_box_outlined),
                              title: Text('選択'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading:
                                  Icon(Icons.delete_outline, color: Colors.red),
                              title: Text('削除',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ),
                        ],
                      ),
            onTap: _selectionMode
                ? () => _toggleSelect(project)
                : () => _openProject(project),
            onLongPress: (readOnly || _selectionMode)
                ? null
                : () => _enterSelection(project),
          );
        },
      ),
    );
  }

  /// 🏷 タグのチップ。
  /// タグに色が定義されていれば「背景=タグ色 / 文字=コントラストの高い白か黒」の
  /// ベタ塗りにする。こうしないとタイル背景色がタグ色と同じ場合に文字が埋もれて
  /// タグ名が見えなくなる。色が無ければタイルの文字色・テーマ色に馴染ませる。
  Widget _buildTagChip(
      BuildContext context, ManidocProject project, Color? foreColor) {
    final scheme = Theme.of(context).colorScheme;
    final tagColor = _tagColor(project.tag.trim());
    final Color bg;
    final Color fg;
    if (tagColor != null) {
      // ベタ塗り: タイル背景と同色でも必ず読める
      bg = tagColor;
      fg = contrastForegroundFor(tagColor);
    } else {
      // 色未定義: タイルの文字色（無ければテーマ色）に薄く馴染ませる
      final base = foreColor ?? scheme.primary;
      bg = base.withValues(alpha: 0.15);
      fg = foreColor ?? scheme.onSurface;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tagColor != null
              ? fg.withValues(alpha: 0.25)
              : (foreColor ?? scheme.primary).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_offer, size: 11, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              project.tag.trim(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: fg),
            ),
          ),
        ],
      ),
    );
  }

  /// 選択モード中の操作バー（件数・全選択・解除・一括色・一括タグ・閉じる）
  Widget _buildSelectionBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = _selectedIds.length;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '選択を終了',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: _exitSelection,
          ),
          Text('$count 件', style: const TextStyle(fontWeight: FontWeight.bold)),
          // ボタンが多いと狭い画面で溢れるため、横スクロールできるようにする
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '全選択',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.select_all),
                    onPressed: () => setState(() {
                      _selectedIds
                        ..clear()
                        ..addAll(_currentProjects.map((p) => p.id));
                    }),
                  ),
                  IconButton(
                    tooltip: '選択解除',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.deselect),
                    onPressed: count == 0
                        ? null
                        : () => setState(() => _selectedIds.clear()),
                  ),
                  IconButton(
                    tooltip: '色をまとめて設定',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.palette_outlined),
                    onPressed: count == 0 ? null : _bulkColor,
                  ),
                  IconButton(
                    tooltip: 'タグをまとめて設定',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.local_offer_outlined),
                    onPressed: count == 0 ? null : _bulkTag,
                  ),
                  if (_hasCopiedColor)
                    IconButton(
                      tooltip: '色を貼り付け',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.paste_outlined),
                      onPressed: count == 0
                          ? null
                          : () async {
                              final targets = _selectedProjects;
                              for (final p in targets) {
                                p.cardForeColorHex = _copiedFore ?? '';
                                p.cardBackColorHex = _copiedBack ?? '';
                              }
                              await _persistMany(targets);
                              if (mounted) _exitSelection();
                            },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortButton() {
    const labels = {
      ProjectSort.modifiedDesc: '更新日時（新しい順）',
      ProjectSort.modifiedAsc: '更新日時（古い順）',
      ProjectSort.nameAsc: '名前（昇順）',
      ProjectSort.nameDesc: '名前（降順）',
      ProjectSort.createdDesc: '作成日時（新しい順）',
      ProjectSort.tag: 'タグ',
    };
    return PopupMenuButton<ProjectSort>(
      icon: const Icon(Icons.sort),
      tooltip: '並べ替え',
      onSelected: _changeSort,
      itemBuilder: (_) => ProjectSort.values
          .map(
            (sort) => PopupMenuItem(
              value: sort,
              child: Row(
                children: [
                  Icon(
                    Icons.check,
                    size: 18,
                    color: sort == _sort ? null : Colors.transparent,
                  ),
                  const SizedBox(width: 8),
                  Text(labels[sort]!),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.workspace.name),
        leading: IconButton(
          icon: const Icon(Icons.workspaces_outlined),
          onPressed: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(
                builder: (_) => const WorkspaceSelectScreen()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: 'Webインポート',
            onPressed: _importWeb,
          ),
          if (!_isWindows || widget.workspace.localPath != null)
            IconButton(
              icon: const Icon(Icons.style_outlined),
              tooltip: 'タグ管理',
              onPressed: _openTagManager,
            ),
          _buildSortButton(),
          _buildSyncIndicator(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.folder_outlined), text: 'プロジェクト'),
            Tab(icon: Icon(Icons.smart_toy_outlined), text: 'AI'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Column(
            children: [
              // 一覧を出した後も裏で画像などを取り込んでいる間は帯を出す
              if (!_isWindows && !_loading) _buildProgressStrip(),
              if (_selectionMode) _buildSelectionBar(context),
              Expanded(
                child: _isWindows
                    ? _buildProjectList(_localProjects, _loadingLocal, false)
                    : _buildProjectList(_projects, _loading, false),
              ),
            ],
          ),
          AiAgentScreen(
            workspace: widget.workspace,
            onProjectCreated: () {
              if (_isWindows) {
                _loadLocal();
              } else {
                _syncFromDrive();
              }
              _tabController.animateTo(0);
            },
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          // プロジェクトタブだけ。AIタブに出すと送信ボタンと重なる。
          // （3タブ時代の index==1 が「Android(読み書き)」タブを指していた名残）
          final showFab = _tabController.index == 0 && !_selectionMode;
          if (!showFab) return const SizedBox.shrink();
          return FloatingActionButton.extended(
            onPressed: _createProject,
            icon: const Icon(Icons.add),
            label: const Text('新規プロジェクト'),
          );
        },
      ),
    );
  }
}
