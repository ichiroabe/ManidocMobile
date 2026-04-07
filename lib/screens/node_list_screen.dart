import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../models/workspace_info.dart';
import '../services/local_storage_service.dart';
import '../services/sync_service.dart';
import '../widgets/node_tile.dart';
import 'node_editor_screen.dart';

class NodeListScreen extends StatefulWidget {
  final ManidocProject project;
  final WorkspaceInfo? workspace; // Android用（オフライン同期に使用）

  const NodeListScreen({super.key, required this.project, this.workspace});

  @override
  State<NodeListScreen> createState() => _NodeListScreenState();
}

class _NodeListScreenState extends State<NodeListScreen> {
  final _syncService = SyncService();
  final _localService = LocalStorageService();
  bool _saving = false;
  String? _selectedNodeId;

  bool get _isWindows => Platform.isWindows;

  Future<void> _save() async {
    if (widget.project.isReadOnly) return;
    setState(() => _saving = true);
    if (_isWindows) {
      await _localService.updateProject(widget.project);
    } else if (widget.workspace != null) {
      await _syncService.saveProject(
          widget.workspace!, 'android', widget.project);
    }
    setState(() => _saving = false);
  }

  void _openNode(ManidocNode node) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NodeEditorScreen(
          project: widget.project,
          node: node,
          onSave: _save,
          workspace: widget.workspace,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _selectedNodeId = widget.project.lastSelectedNodeId);
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

  void _renameNode(ManidocNode node) async {
    final controller = TextEditingController(text: node.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ノード名を変更'),
        content: TextField(
          controller: controller,
          autofocus: true,
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
            child: const Text('変更'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (newTitle == null || newTitle.isEmpty || newTitle == node.title) return;
    setState(() => node.title = newTitle);
    await _save();
  }

  void _moveNodeUp(ManidocNode node) async {
    final siblings = _findSiblings(node);
    if (siblings == null) return;
    final index = siblings.indexWhere((n) => n.id == node.id);
    if (index <= 0) return;
    setState(() {
      siblings.removeAt(index);
      siblings.insert(index - 1, node);
    });
    await _save();
  }

  void _moveNodeDown(ManidocNode node) async {
    final siblings = _findSiblings(node);
    if (siblings == null) return;
    final index = siblings.indexWhere((n) => n.id == node.id);
    if (index < 0 || index >= siblings.length - 1) return;
    setState(() {
      siblings.removeAt(index);
      siblings.insert(index + 1, node);
    });
    await _save();
  }

  /// 左スワイプ: 1つ下の階層へ（直上の兄弟の子にする）
  void _indentNode(ManidocNode node) async {
    final siblings = _findSiblings(node);
    if (siblings == null) return;
    final index = siblings.indexWhere((n) => n.id == node.id);
    if (index <= 0) return; // 先頭ノードはインデント不可
    final newParent = siblings[index - 1];
    setState(() {
      siblings.removeAt(index);
      newParent.children.add(node);
    });
    await _save();
  }

  /// 右スワイプ: 1つ上の階層へ（親の兄弟リストに移動）
  void _outdentNode(ManidocNode node) async {
    // ルートノードはアウトデント不可
    if (widget.project.rootNodes.any((n) => n.id == node.id)) return;
    final parent = _findParent(widget.project.rootNodes, node);
    if (parent == null) return;
    final parentSiblings = _findSiblings(parent);
    if (parentSiblings == null) return;
    final parentIndex = parentSiblings.indexWhere((n) => n.id == parent.id);
    setState(() {
      parent.children.removeWhere((n) => n.id == node.id);
      parentSiblings.insert(parentIndex + 1, node);
    });
    await _save();
  }

  ManidocNode? _findParent(List<ManidocNode> nodes, ManidocNode target) {
    for (final n in nodes) {
      if (n.children.any((c) => c.id == target.id)) return n;
      final found = _findParent(n.children, target);
      if (found != null) return found;
    }
    return null;
  }

  void _moveToOtherParent(ManidocNode node) async {
    // 移動先候補を収集（自分自身と自分の子孫は除外）
    final candidates = <_MoveTarget>[];
    // ルート（親なし）を候補に追加
    candidates.add(_MoveTarget(name: '（ルート）', parent: null));
    _collectMoveCandidates(widget.project.rootNodes, candidates, node, 0);

    final selected = await showDialog<_MoveTarget>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移動先を選択'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (_, i) {
              final c = candidates[i];
              return ListTile(
                leading: Icon(c.parent == null
                    ? Icons.home_outlined
                    : Icons.folder_open),
                title: Text(c.name),
                contentPadding:
                    EdgeInsets.only(left: (c.depth * 16.0) + 16),
                onTap: () => Navigator.pop(ctx, c),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
    if (selected == null) return;

    setState(() {
      // 元の場所から削除
      _removeNodeFromTree(widget.project.rootNodes, node);
      // 新しい場所に追加
      if (selected.parent == null) {
        widget.project.rootNodes.add(node);
      } else {
        selected.parent!.children.add(node);
      }
    });
    await _save();
  }

  void _collectMoveCandidates(List<ManidocNode> nodes,
      List<_MoveTarget> candidates, ManidocNode exclude, int depth) {
    for (final n in nodes) {
      if (n.id == exclude.id) continue;
      if (_isDescendantOf(n, exclude)) continue;
      candidates.add(_MoveTarget(name: n.title, parent: n, depth: depth));
      _collectMoveCandidates(n.children, candidates, exclude, depth + 1);
    }
  }

  bool _isDescendantOf(ManidocNode node, ManidocNode ancestor) {
    for (final child in ancestor.children) {
      if (child.id == node.id) return true;
      if (_isDescendantOf(node, child)) return true;
    }
    return false;
  }

  List<ManidocNode>? _findSiblings(ManidocNode node) {
    // ルートレベルを確認
    if (widget.project.rootNodes.any((n) => n.id == node.id)) {
      return widget.project.rootNodes;
    }
    return _findSiblingsIn(widget.project.rootNodes, node);
  }

  List<ManidocNode>? _findSiblingsIn(
      List<ManidocNode> nodes, ManidocNode target) {
    for (final n in nodes) {
      if (n.children.any((c) => c.id == target.id)) return n.children;
      final found = _findSiblingsIn(n.children, target);
      if (found != null) return found;
    }
    return null;
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
              padding: const EdgeInsets.only(bottom: 80),
              children: project.rootNodes
                  .map((node) => NodeTile(
                        node: node,
                        depth: 0,
                        readOnly: project.isReadOnly,
                        selectedNodeId: _selectedNodeId,
                        onTap: _openNode,
                        onAddChild: _addChildNode,
                        onDelete: _deleteNode,
                        onRename: _renameNode,
                        onMoveUp: _moveNodeUp,
                        onMoveDown: _moveNodeDown,
                        onMoveToParent: _moveToOtherParent,
                        onIndent: _indentNode,
                        onOutdent: _outdentNode,
                      ))
                  .toList(),
            ),
    );
  }
}

class _MoveTarget {
  final String name;
  final ManidocNode? parent;
  final int depth;

  _MoveTarget({required this.name, this.parent, this.depth = 0});
}
