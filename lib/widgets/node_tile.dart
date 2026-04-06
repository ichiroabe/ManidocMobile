import 'package:flutter/material.dart';
import '../models/manidoc_node.dart';

class NodeTile extends StatelessWidget {
  final ManidocNode node;
  final int depth;
  final bool readOnly;
  final String? selectedNodeId;
  final void Function(ManidocNode) onTap;
  final void Function(ManidocNode)? onAddChild;
  final void Function(ManidocNode)? onDelete;
  final void Function(ManidocNode)? onRename;
  final void Function(ManidocNode)? onMoveUp;
  final void Function(ManidocNode)? onMoveDown;
  final void Function(ManidocNode)? onMoveToParent;

  const NodeTile({
    super.key,
    required this.node,
    required this.depth,
    required this.readOnly,
    this.selectedNodeId,
    required this.onTap,
    this.onAddChild,
    this.onDelete,
    this.onRename,
    this.onMoveUp,
    this.onMoveDown,
    this.onMoveToParent,
  });

  bool get _isSelected => selectedNodeId == node.id;

  @override
  Widget build(BuildContext context) {
    final hasChildren = node.children.isNotEmpty;
    final indent = depth * 16.0;

    if (!hasChildren) {
      return _wrapWithHighlight(context, _buildTile(context, indent));
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: indent + 16, right: 16),
      leading: const Icon(Icons.folder_open, size: 20),
      title: _wrapWithHighlight(
        context,
        GestureDetector(
          onTap: () => onTap(node),
          child: Text(node.title),
        ),
      ),
      initiallyExpanded: true,
      trailing: _buildTrailing(context),
      children: node.children
          .map((child) => NodeTile(
                node: child,
                depth: depth + 1,
                readOnly: readOnly,
                selectedNodeId: selectedNodeId,
                onTap: onTap,
                onAddChild: onAddChild,
                onDelete: onDelete,
                onRename: onRename,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                onMoveToParent: onMoveToParent,
              ))
          .toList(),
    );
  }

  Widget _wrapWithHighlight(BuildContext context, Widget child) {
    if (!_isSelected) return child;

    return _BlinkHighlight(child: child);
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
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('名前を変更'),
          ),
        ),
        const PopupMenuItem(
          value: 'add',
          child: ListTile(
            leading: Icon(Icons.add),
            title: Text('子ノードを追加'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'move_up',
          child: ListTile(
            leading: Icon(Icons.arrow_upward),
            title: Text('上に移動'),
          ),
        ),
        const PopupMenuItem(
          value: 'move_down',
          child: ListTile(
            leading: Icon(Icons.arrow_downward),
            title: Text('下に移動'),
          ),
        ),
        const PopupMenuItem(
          value: 'move_to',
          child: ListTile(
            leading: Icon(Icons.drive_file_move_outlined),
            title: Text('別の場所に移動'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onTap(node);
          case 'rename':
            onRename?.call(node);
          case 'add':
            onAddChild?.call(node);
          case 'move_up':
            onMoveUp?.call(node);
          case 'move_down':
            onMoveDown?.call(node);
          case 'move_to':
            onMoveToParent?.call(node);
          case 'delete':
            onDelete?.call(node);
        }
      },
    );
  }
}

class _BlinkHighlight extends StatefulWidget {
  final Widget child;
  const _BlinkHighlight({required this.child});

  @override
  State<_BlinkHighlight> createState() => _BlinkHighlightState();
}

class _BlinkHighlightState extends State<_BlinkHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: _animation.value),
            borderRadius: BorderRadius.circular(4),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
