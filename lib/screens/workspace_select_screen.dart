import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/workspace_info.dart';
import '../services/drive_service.dart';
import '../services/saf_service.dart';
import '../services/workspace_service.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class WorkspaceSelectScreen extends StatefulWidget {
  const WorkspaceSelectScreen({super.key});

  @override
  State<WorkspaceSelectScreen> createState() => _WorkspaceSelectScreenState();
}

class _WorkspaceSelectScreenState extends State<WorkspaceSelectScreen> {
  final _workspaceService = WorkspaceService();
  final _driveService = DriveService();
  final _saf = SafService();
  List<WorkspaceInfo> _workspaces = [];
  bool _loading = true;

  bool get _isWindows => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final workspaces = await _workspaceService.getWorkspaces();
    setState(() {
      _workspaces = workspaces;
      _loading = false;
    });
  }

  void _openWorkspace(WorkspaceInfo workspace) async {
    if (!_isWindows) {
      // v1.0.x（Drive API 版）で登録したワークスペースにはツリーURIが無い。
      // 黙って空のプロジェクト一覧を出すと原因が分からないので明示する。
      if (workspace.treeUri.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('このワークスペースは旧バージョンで登録されたものです。'
                '削除して追加し直してください。'),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      if (!await _saf.hasPermission(workspace.treeUri)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('フォルダへのアクセス権が失われています。追加し直してください。'),
          ),
        );
        return;
      }
      // 以降の読み書きはすべてこのツリー配下で行う
      DriveService.currentTree = workspace.treeUri;
    }
    await _workspaceService.setLastWorkspaceName(workspace.name);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(workspace: workspace),
      ),
    );
  }

  Future<void> _addWorkspace() async {
    if (_isWindows) {
      await _addWorkspaceWindows();
    } else {
      await _addWorkspaceAndroid();
    }
  }

  /// Windows: file_pickerでローカルフォルダを選択
  Future<void> _addWorkspaceWindows() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'ワークスペースフォルダを選択',
    );
    if (result == null) return;

    // フォルダ名をワークスペース名に
    final name = result.split(RegExp(r'[/\\]')).last;
    final workspace = WorkspaceInfo(
      name: name,
      localPath: result,
    );
    await _workspaceService.addWorkspace(workspace);
    _load();
  }

  /// Android: システムのフォルダ選択。Google Drive でも端末内でも同じ手順で選べる。
  /// 選んだフォルダがワークスペース（Windows版が書く場所）で、
  /// このアプリの書き込み先はその中の _android。
  Future<void> _addWorkspaceAndroid() async {
    final pick = await _saf.pickTree();
    if (pick == null) return;

    DriveService.currentTree = pick.tree;
    final androidFolderId =
        await _driveService.getOrCreateAndroidFolder(pick.doc);
    if (androidFolderId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('_android フォルダを作成できませんでした')),
      );
      return;
    }

    final workspace = WorkspaceInfo(
      name: pick.name.isEmpty ? 'ワークスペース' : pick.name,
      treeUri: pick.tree,
      windowsFolderId: pick.doc,
      androidFolderId: androidFolderId,
    );
    await _workspaceService.addWorkspace(workspace);
    _load();
  }

  Future<void> _removeWorkspace(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${_workspaces[index].name}」を削除しますか？\n'
            '${_isWindows ? '（ローカルファイルは削除されません）' : '（Google Drive 上のデータは削除されません）'}'),
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
    if (confirmed == true) {
      await _workspaceService.removeWorkspace(index);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ワークスペース'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workspaces.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.folder_off_outlined,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('ワークスペースがありません'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _addWorkspace,
                        icon: const Icon(Icons.add),
                        label: const Text('追加する'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _workspaces.length,
                  itemBuilder: (context, i) {
                    final ws = _workspaces[i];
                    return ListTile(
                      leading: const Icon(Icons.workspaces_outlined),
                      title: Text(ws.name),
                      subtitle: _isWindows && ws.localPath != null
                          ? Text(ws.localPath!,
                              style: Theme.of(context).textTheme.bodySmall)
                          : null,
                      onTap: () => _openWorkspace(ws),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeWorkspace(i),
                      ),
                    );
                  },
                ),
      floatingActionButton: _workspaces.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _addWorkspace,
              icon: const Icon(Icons.add),
              label: const Text('追加'),
            )
          : null,
    );
  }
}
