import 'package:flutter/material.dart';

/// 🏷 タグ設定ダイアログ。既存タグから選ぶか、新規入力する。
/// デスクトップ版(openManidoc)の showTagDialog 準拠。
/// 確定したタグ文字列を返す(キャンセルは null)。空文字=タグなし。
Future<String?> showTagDialog(
  BuildContext context,
  String currentTag,
  List<String> existingTags,
) {
  final controller = TextEditingController(text: currentTag);
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('タグ設定'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'タグ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (existingTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('既存のタグ',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in existingTags)
                      ActionChip(
                        label: Text(tag),
                        onPressed: () => setState(() => controller.text = tag),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          if (currentTag.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('タグなし'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
