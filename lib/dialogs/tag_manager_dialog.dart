import 'package:flutter/material.dart';

import '../models/tag_definition.dart';
import '../services/color_utils.dart';
import 'card_color_dialog.dart';

/// 🏷 タグ管理ダイアログ。ワークスペースのタグを 追加/改名/色設定/削除 する。
/// デスクトップ版(openManidoc)の TagManagerDialog 準拠（画像の代わりに色を持つ）。
/// 保存したら編集後の一覧を返す（キャンセルは null）。
Future<List<TagDefinition>?> showTagManagerDialog(
  BuildContext context,
  List<TagDefinition> current,
) {
  // 編集用にコピーを渡す
  final tags = [
    for (final t in current)
      TagDefinition(name: t.name, color: t.color, extra: {...t.extra})
  ];
  return showDialog<List<TagDefinition>>(
    context: context,
    builder: (context) => _TagManager(tags: tags),
  );
}

class _TagManager extends StatefulWidget {
  final List<TagDefinition> tags;
  const _TagManager({required this.tags});

  @override
  State<_TagManager> createState() => _TagManagerState();
}

class _TagManagerState extends State<_TagManager> {
  late final List<TagDefinition> _tags = widget.tags;
  final Map<int, TextEditingController> _controllers = {};

  TextEditingController _ctrl(int i) => _controllers.putIfAbsent(
      i, () => TextEditingController(text: _tags[i].name));

  void _rebuildControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickColor(int i) async {
    final hex = await showSingleColorDialog(
      context,
      initial: _tags[i].color,
      title: 'タグ「${_tags[i].name}」の色',
    );
    if (hex == null) return;
    setState(() => _tags[i].color = hex);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('タグ管理'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          children: [
            Expanded(
              child: _tags.isEmpty
                  ? const Center(child: Text('タグがありません'))
                  : ListView.builder(
                      itemCount: _tags.length,
                      itemBuilder: (context, i) {
                        final tag = _tags[i];
                        final color = colorFromHex(tag.color);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              // 色スウォッチ（タップで色選択）
                              InkWell(
                                onTap: () => _pickColor(i),
                                customBorder: const CircleBorder(),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color ??
                                        scheme.surfaceContainerHighest,
                                    shape: BoxShape.circle,
                                    border:
                                        Border.all(color: scheme.outlineVariant),
                                  ),
                                  child: color == null
                                      ? Icon(Icons.colorize,
                                          size: 16,
                                          color: scheme.onSurfaceVariant)
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _ctrl(i),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) => tag.name = v,
                                ),
                              ),
                              IconButton(
                                tooltip: '削除',
                                iconSize: 20,
                                color: scheme.error,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => setState(() {
                                  _tags.removeAt(i);
                                  _rebuildControllers();
                                }),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _tags.add(TagDefinition(name: ''));
                  _rebuildControllers();
                }),
                icon: const Icon(Icons.add),
                label: const Text('タグを追加'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            // 空名は捨てる
            final result = _tags
                .where((t) => t.name.trim().isNotEmpty)
                .map((t) => TagDefinition(
                    name: t.name.trim(), color: t.color, extra: t.extra))
                .toList();
            Navigator.pop(context, result);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
