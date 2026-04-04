import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/drive_service.dart';

class FolderPickerDialog extends StatefulWidget {
  const FolderPickerDialog({super.key});

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  final _driveService = DriveService();
  final _history = <({String? id, String name})>[];
  String? _currentFolderId;
  String _currentName = 'マイドライブ';
  List<drive.File> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders(null, 'マイドライブ');
  }

  Future<void> _loadFolders(String? folderId, String name) async {
    setState(() => _loading = true);
    final folders = await _driveService.listFolders(parentId: folderId);
    setState(() {
      _currentFolderId = folderId;
      _currentName = name;
      _folders = folders;
      _loading = false;
    });
  }

  void _navigateInto(drive.File folder) {
    _history.add((id: _currentFolderId, name: _currentName));
    _loadFolders(folder.id, folder.name ?? '');
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新しいフォルダ'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'フォルダ名',
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
            child: const Text('作成'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (name == null || name.isEmpty) return;

    final id = await _driveService.createFolder(
      name,
      parentId: _currentFolderId,
    );
    if (id == null) return;
    await _loadFolders(_currentFolderId, _currentName);
  }

  void _navigateBack() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    _loadFolders(prev.id, prev.name);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            title: Text(_currentName),
            automaticallyImplyLeading: false,
            leading: _history.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _navigateBack,
                  )
                : null,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_folders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('フォルダがありません'),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _folders.length,
                itemBuilder: (context, i) {
                  final folder = _folders[i];
                  return ListTile(
                    leading: const Icon(Icons.folder, color: Color(0xFFFFC107)),
                    title: Text(folder.name ?? ''),
                    trailing: IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _navigateInto(folder),
                    ),
                    onTap: () => Navigator.pop(
                      context,
                      (id: folder.id, name: folder.name ?? ''),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              onPressed: () => _createFolder(),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('新しいフォルダを作成'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton.icon(
              onPressed: _currentFolderId != null
                  ? () => Navigator.pop(
                        context,
                        (id: _currentFolderId, name: _currentName),
                      )
                  : null,
              icon: const Icon(Icons.check),
              label: Text('「$_currentName」を選択'),
            ),
          ),
        ],
      ),
    );
  }
}
