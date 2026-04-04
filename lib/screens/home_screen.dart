import 'package:flutter/material.dart';
import '../models/manidoc_project.dart';
import '../models/workspace_info.dart';
import '../services/drive_service.dart';
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
  late final TabController _tabController;

  List<ManidocProject> _windowsProjects = [];
  List<ManidocProject> _androidProjects = [];
  bool _loadingWindows = true;
  bool _loadingAndroid = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadWindows();
    _loadAndroid();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWindows() async {
    setState(() => _loadingWindows = true);
    final files = await _driveService
        .listProjectFiles(widget.workspace.windowsFolderId);
    final projects = <ManidocProject>[];
    for (final info in files) {
      final project = await _driveService.readProject(
        info.file,
        readOnly: true,
        folderId: info.parentFolderId,
        hasProjectFolder: info.hasProjectFolder,
      );
      if (project != null) projects.add(project);
    }
    if (!mounted) return;
    setState(() {
      _windowsProjects = projects;
      _loadingWindows = false;
    });
  }

  Future<void> _loadAndroid() async {
    setState(() => _loadingAndroid = true);
    final files = await _driveService
        .listProjectFiles(widget.workspace.androidFolderId);
    final projects = <ManidocProject>[];
    for (final info in files) {
      final project = await _driveService.readProject(
        info.file,
        readOnly: false,
        folderId: info.parentFolderId,
        hasProjectFolder: info.hasProjectFolder,
      );
      if (project != null) projects.add(project);
    }
    if (!mounted) return;
    setState(() {
      _androidProjects = projects;
      _loadingAndroid = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => nameController.dispose());

    if (name == null || name.isEmpty) return;

    final project = ManidocProject.create(name);
    project.driveFolderId = widget.workspace.androidFolderId;

    final fileId = await _driveService.createProject(
      project,
      widget.workspace.androidFolderId,
    );
    if (!mounted) return;
    if (fileId != null) {
      project.driveFileId = fileId;
      _loadAndroid();
    }
  }

  void _openProject(ManidocProject project) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NodeListScreen(project: project),
      ),
    ).then((_) {
      if (!project.isReadOnly) _loadAndroid();
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
    if (!mounted || name == null || name.isEmpty || name == project.name) return;
    project.name = name;
    await _driveService.updateProject(project);
    if (!mounted) return;
    _loadAndroid();
  }

  Future<void> _deleteProject(ManidocProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${project.name}」を削除しますか？\n（Google Drive上のファイルも削除されます）'),
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
    if (project.driveFileId != null) {
      await _driveService.deleteFile(project.driveFileId!);
    }
    if (!mounted) return;
    _loadAndroid();
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
      onRefresh: readOnly ? _loadWindows : _loadAndroid,
      child: ListView.builder(
        itemCount: projects.length,
        itemBuilder: (context, i) {
          final project = projects[i];
          return ListTile(
            leading: const Icon(Icons.folder_outlined),
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
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('削除', style: TextStyle(color: Colors.red)),
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
            Tab(icon: Icon(Icons.computer), text: 'Windows'),
            Tab(icon: Icon(Icons.phone_android), text: 'Android'),
            Tab(icon: Icon(Icons.smart_toy_outlined), text: 'AI'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProjectList(_windowsProjects, _loadingWindows, true),
          _buildProjectList(_androidProjects, _loadingAndroid, false),
          AiAgentScreen(
            workspace: widget.workspace,
            onProjectCreated: () {
              _loadAndroid();
              _tabController.animateTo(1); // switch to Android tab
            },
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: _tabController,
        builder: (context, _) {
          if (_tabController.index != 1) return const SizedBox.shrink();
          // AI tab manages its own navigation
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
