import 'dart:async';
import 'dart:io' show Platform;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
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

  bool get _isWindows => Platform.isWindows;

  List<ManidocProject> _windowsProjects = [];
  List<ManidocProject> _androidProjects = [];
  List<ManidocProject> _localProjects = [];
  bool _loadingWindows = true;
  bool _loadingAndroid = true;
  bool _loadingLocal = true;
  SyncStatus _syncStatus = SyncStatus.idle;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      _tabController = TabController(length: 2, vsync: this);
      _loadLocal();
    } else {
      _tabController = TabController(length: 3, vsync: this);
      _loadWithCacheFirst();
      // オンライン復帰時に自動同期
      _connectivitySub =
          Connectivity().onConnectivityChanged.listen((result) {
        if (!result.contains(ConnectivityResult.none)) {
          _syncFromDrive();
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  // ── キャッシュ優先読み込み（Android） ──
  Future<void> _loadWithCacheFirst() async {
    // 1. まずキャッシュからすぐ表示
    final cachedWindows =
        await _cacheService.loadProjects(widget.workspace, 'windows');
    final cachedAndroid =
        await _cacheService.loadProjects(widget.workspace, 'android');

    if (!mounted) return;
    setState(() {
      if (cachedWindows.isNotEmpty) {
        _windowsProjects = cachedWindows;
        _loadingWindows = false;
      }
      if (cachedAndroid.isNotEmpty) {
        _androidProjects = cachedAndroid;
        _loadingAndroid = false;
      }
    });

    // 2. バックグラウンドでDriveから同期
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
      await _syncService.pushDirtyProjects(widget.workspace, 'android');

      // DriveからPull
      final windows = await _syncService.pullProjects(
        widget.workspace,
        widget.workspace.windowsFolderId,
        'windows',
      );
      final android = await _syncService.pullProjects(
        widget.workspace,
        widget.workspace.androidFolderId,
        'android',
      );

      if (!mounted) return;
      setState(() {
        if (windows != null) {
          _windowsProjects = windows;
          _loadingWindows = false;
        }
        if (android != null) {
          _androidProjects = android;
          _loadingAndroid = false;
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
      project.driveFolderId = widget.workspace.androidFolderId;

      if (await _syncService.isOnline()) {
        final fileId = await _driveService.createProject(
          project,
          widget.workspace.androidFolderId,
        );
        if (!mounted) return;
        if (fileId != null) {
          project.driveFileId = fileId;
          // キャッシュにも保存
          await _cacheService.saveProject(
              widget.workspace, 'android', project);
          _syncFromDrive();
        }
      } else {
        // オフライン: キャッシュのみに保存（dirty）
        project.isDirty = true;
        await _cacheService.saveProject(
            widget.workspace, 'android', project);
        if (!mounted) return;
        setState(() {
          _androidProjects.add(project);
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
      await _syncService.saveProject(widget.workspace, 'android', project);
      if (!mounted) return;
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
          widget.workspace, 'android', project.id);
      // Driveからも削除（オンラインなら）
      if (project.driveFileId != null && await _syncService.isOnline()) {
        await _driveService.deleteFile(project.driveFileId!);
      }
      if (!mounted) return;
      setState(() {
        _androidProjects.removeWhere((p) => p.id == project.id);
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
        final dirtyCount =
            _androidProjects.where((p) => p.isDirty).length;
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
    return RefreshIndicator(
      onRefresh: _isWindows
          ? _loadLocal
          : (readOnly ? _syncFromDrive : _syncFromDrive),
      child: ListView.builder(
        itemCount: projects.length,
        itemBuilder: (context, i) {
          final project = projects[i];
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
          tabs: _isWindows
              ? const [
                  Tab(icon: Icon(Icons.folder_outlined), text: 'プロジェクト'),
                  Tab(icon: Icon(Icons.smart_toy_outlined), text: 'AI'),
                ]
              : const [
                  Tab(icon: Icon(Icons.computer), text: 'Windows'),
                  Tab(icon: Icon(Icons.phone_android), text: 'Android'),
                  Tab(icon: Icon(Icons.smart_toy_outlined), text: 'AI'),
                ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _isWindows
            ? [
                _buildProjectList(_localProjects, _loadingLocal, false),
                AiAgentScreen(
                  workspace: widget.workspace,
                  onProjectCreated: () {
                    _loadLocal();
                    _tabController.animateTo(0);
                  },
                ),
              ]
            : [
                _buildProjectList(_windowsProjects, _loadingWindows, true),
                _buildProjectList(_androidProjects, _loadingAndroid, false),
                AiAgentScreen(
                  workspace: widget.workspace,
                  onProjectCreated: () {
                    _syncFromDrive();
                    _tabController.animateTo(1);
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
