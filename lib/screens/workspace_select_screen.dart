import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/workspace_info.dart';
import '../services/drive_service.dart';
import '../services/workspace_service.dart';
import '../widgets/folder_picker_dialog.dart';
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

  /// Android: Driveフォルダピッカー
  Future<void> _addWorkspaceAndroid() async {
    String? windowsFolderId;
    String? windowsFolderName;
    String? androidFolderId;
    String? androidFolderName;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('ワークスペースを追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Windowsフォルダ（読み取り専用）',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await showDialog<({String? id, String name})>(
                      context: ctx,
                      builder: (_) => const FolderPickerDialog(),
                    );
                    if (result != null && result.id != null) {
                      setDialogState(() {
                        windowsFolderId = result.id;
                        windowsFolderName = result.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(windowsFolderName ?? 'フォルダを選ぶ'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Androidフォルダ（読み書き）',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await showDialog<({String? id, String name})>(
                      context: ctx,
                      builder: (_) => const FolderPickerDialog(),
                    );
                    if (result != null && result.id != null) {
                      setDialogState(() {
                        androidFolderId = result.id;
                        androidFolderName = result.name;
                      });
                    }
                  },
                  icon: const Icon(Icons.folder_outlined),
                  label: Text(androidFolderName ?? 'フォルダを選ぶ'),
                ),
                const SizedBox(height: 4),
                Text(
                  '※ 未選択の場合、Windowsフォルダ内に _android フォルダを自動作成します',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: windowsFolderId == null
                  ? null
                  : () async {
                      String? finalAndroidId = androidFolderId ??
                          await _driveService.getOrCreateAndroidFolder(
                            windowsFolderId!,
                          );
                      if (finalAndroidId == null) {
                        return;
                      }
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx, true);
                      final workspace = WorkspaceInfo(
                        name: windowsFolderName!,
                        windowsFolderId: windowsFolderId!,
                        androidFolderId: finalAndroidId,
                      );
                      await _workspaceService.addWorkspace(workspace);
                      _load();
                    },
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
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
