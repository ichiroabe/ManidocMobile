import 'package:flutter/material.dart';
import '../models/manidoc_node.dart';

class NodeTile extends StatelessWidget {
  final ManidocNode node;
  final int depth;
  final bool readOnly;
  final void Function(ManidocNode) onTap;
  final void Function(ManidocNode)? onAddChild;
  final void Function(ManidocNode)? onDelete;

  const NodeTile({
    super.key,
    required this.node,
    required this.depth,
    required this.readOnly,
    required this.onTap,
    this.onAddChild,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;
    final indent = depth * 16.0;

    if (!hasChildren) {
      return _buildTile(context, indent);
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: indent + 16, right: 16),
      leading: const Icon(Icons.folder_open, size: 20),
      title: GestureDetector(
        onTap: () => onTap(node),
        child: Text(node.title),
      ),
      initiallyExpanded: true,
      trailing: _buildTrailing(context),
      children: node.children
          .map((child) => NodeTile(
                node: child,
                depth: depth + 1,
                readOnly: readOnly,
                onTap: onTap,
                onAddChild: onAddChild,
                onDelete: onDelete,
              ))
          .toList(),
    );
  }

  Widget _buildTile(BuildContext context, double indent) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: indent + 16, right: 8),
      leading: const Icon(Icons.article_outlined, size: 20),
      title: Text(node.title),
      onTap: () => onTap(node),
      trailing: _buildTrailing(context),
    );
  }

  Widget? _buildTrailing(BuildContext context) {
    if (readOnly) return null;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('編集'),
          ),
        ),
        const PopupMenuItem(
          value: 'add',
          child: ListTile(
            leading: Icon(Icons.add),
            title: Text('子ノードを追加'),
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
      onSelected: (value) {
        if (value == 'edit') onTap(node);
        if (value == 'add') onAddChild?.call(node);
        if (value == 'delete') onDelete?.call(node);
      },
    );
  }
}
