import 'dart:async';
import 'dart:io' show Platform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/manidoc_project.dart';
import '../models/workspace_info.dart';
import '../services/drive_service.dart';
import '../services/local_cache_service.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
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
  late final TabController _tabController;
  StreamSubscription? _connectivitySub;
  Timer? _syncDebounce;

  bool get _isWindows => Platform.isWindows;

  // ワークスペースは読み書き一本。以前は Windows(読み取り専用)と
  // Android(読み書き)に分けていたが、SAF で全体を書けるようになったため統合した。
  List<ManidocProject> _projects = [];
  List<ManidocProject> _localProjects = [];
  bool _loading = true;
  bool _loadingLocal = true;
  SyncStatus _syncStatus = SyncStatus.idle;
  ProjectSort _sort = ProjectSort.modifiedDesc;

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
      // オンライン復帰時に自動同期
      _connectivitySub =
          Connectivity().onConnectivityChanged.listen((result) {
        if (!result.contains(ConnectivityResult.none)) {
          // 不安定な接続での連続発火を防止（3秒デバウンス）
          _syncDebounce?.cancel();
          _syncDebounce = Timer(const Duration(seconds: 3), () {
            _syncFromDrive();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _connectivitySub?.cancel();
    _syncDebounce?.cancel();
    super.dispose();
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
    }
    return sorted;
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

    // 2. バックグラウンドでワークスペースから同期
    await _syncFromDrive();
  }

  // ── Drive同期（Android） ──
  Future<void> _syncFromDrive() async {
    if (_isWindows) return;
    if (!await _syncService.isOnline()) {
      if (mounted) setState(() => _syncStatus = SyncStatus.offline);
      return;
    }

    if (mounted) setState(() => _syncStatus = SyncStatus.syncing);

    try {
      // まずdirtyなプロジェクトをPush
      await _syncService.pushDirtyProjects(
          widget.workspace, SyncService.workspaceType);

      // ワークスペース全体をPull（_android など既存のサブフォルダ内も走査される）
      final projects = await _syncService.pullProjects(
        widget.workspace,
        widget.workspace.windowsFolderId,
        SyncService.workspaceType,
      );

      if (!mounted) return;
      setState(() {
        if (projects != null) {
          _projects = projects;
          _loading = false;
        }
        _syncStatus = SyncStatus.idle;
      });
    } catch (_) {
      if (mounted) setState(() => _syncStatus = SyncStatus.error);
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

    final project = ManidocProject.create(name);

    if (_isWindows) {
      final path = widget.workspace.localPath;
      if (path == null) return;
      final ok = await _localService.createProject(project, path);
      if (!mounted) return;
      if (ok) _loadLocal();
    } else {
      // 新規プロジェクトはワークスペース直下に作る（デスクトップ版と同じ場所）
      final workspaceFolderId = widget.workspace.windowsFolderId;
      project.driveFolderId = workspaceFolderId;

      if (await _syncService.isOnline()) {
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
        }
      } else {
        // オフライン: キャッシュのみに保存（dirty）
        project.isDirty = true;
        await _cacheService.saveProject(
            widget.workspace, SyncService.workspaceType, project);
        if (!mounted) return;
        setState(() {
          _projects.add(project);
        });
      }
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
      // ワークスペースからも削除（オンラインなら）
      if (project.driveFileId != null && await _syncService.isOnline()) {
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
      case SyncStatus.offline:
        icon = Icons.cloud_off_outlined;
        color = Colors.grey;
        tooltip = 'オフライン';
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

  Widget _buildProjectList(
    List<ManidocProject> projects,
    bool loading,
    bool readOnly,
  ) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
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
          return ListTile(
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_outlined),
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
            title: Text(project.name),
            subtitle: Text(
              _formatDate(project.lastModifiedAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            trailing: readOnly
                ? const Icon(Icons.lock_outline, size: 16, color: Colors.grey)
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'rename') _renameProject(project);
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
            onTap: () => _openProject(project),
          );
        },
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
          _isWindows
              ? _buildProjectList(_localProjects, _loadingLocal, false)
              : _buildProjectList(_projects, _loading, false),
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
          final showFab = _isWindows
              ? _tabController.index == 0
              : _tabController.index == 1;
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
