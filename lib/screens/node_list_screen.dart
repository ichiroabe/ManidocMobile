import 'package:flutter/material.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../services/drive_service.dart';
import '../widgets/node_tile.dart';
import 'node_editor_screen.dart';

class NodeListScreen extends StatefulWidget {
  final ManidocProject project;

  const NodeListScreen({super.key, required this.project});

  @override
  State<NodeListScreen> createState() => _NodeListScreenState();
}

class _NodeListScreenState extends State<NodeListScreen> {
  final _driveService = DriveService();
  bool _saving = false;

  Future<void> _save() async {
    if (widget.project.isReadOnly) return;
    setState(() => _saving = true);
    await _driveService.updateProject(widget.project);
    setState(() => _saving = false);
  }

  void _openNode(ManidocNode node) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NodeEditorScreen(
          project: widget.project,
          node: node,
          onSave: _save,
        ),
      ),
    );
  }

  void _addRootNode() async {
    final node = await _showAddNodeDialog();
    if (!mounted || node == null) return;
    setState(() => widget.project.rootNodes.add(node));
    await _save();
  }

  void _addChildNode(ManidocNode parent) async {
    final node = await _showAddNodeDialog();
    if (!mounted || node == null) return;
    setState(() => parent.children.add(node));
    await _save();
  }

  void _deleteNode(ManidocNode node) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除確認'),
        content: Text('「${node.title}」を削除しますか？\n子ノードも全て削除されます。'),
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
    if (confirmed != true) return;

    setState(() => _removeNodeFromTree(widget.project.rootNodes, node));
    await _save();
  }

  bool _removeNodeFromTree(List<ManidocNode> nodes, ManidocNode target) {
    final index = nodes.indexWhere((n) => n.id == target.id);
    if (index >= 0) {
      nodes.removeAt(index);
      return true;
    }
    for (final node in nodes) {
      if (_removeNodeFromTree(node.children, target)) return true;
    }
    return false;
  }

  Future<ManidocNode?> _showAddNodeDialog() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ノードを追加'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'タイトル',
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
            child: const Text('追加'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (title == null || title.isEmpty) return null;
    return ManidocNode.create(title);
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          if (project.isReadOnly)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 16),
                  SizedBox(width: 4),
                  Text('読み取り専用'),
                ],
              ),
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (!project.isReadOnly && !_saving)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'ルートノードを追加',
              onPressed: _addRootNode,
            ),
        ],
      ),
      body: project.rootNodes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.note_add_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('ノードがありません'),
                  if (!project.isReadOnly) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _addRootNode,
                      icon: const Icon(Icons.add),
                      label: const Text('ノードを追加'),
                    ),
                  ],
                ],
              ),
            )
          : ListView(
              children: project.rootNodes
                  .map((node) => NodeTile(
                        node: node,
                        depth: 0,
                        readOnly: project.isReadOnly,
                        onTap: _openNode,
                        onAddChild: _addChildNode,
                        onDelete: _deleteNode,
                      ))
                  .toList(),
            ),
      floatingActionButton: !project.isReadOnly
          ? FloatingActionButton(
              onPressed: _addRootNode,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}
