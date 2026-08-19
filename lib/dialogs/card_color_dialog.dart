import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/color_utils.dart';

/// カラーピッカーの結果。hex は '#rrggbb'、空文字は「既定(テーマ色)」。
class CardColorResult {
  final String fore;
  final String back;
  const CardColorResult({required this.fore, required this.back});
}

/// プロジェクトタイルの文字色/背景色を選ぶダイアログ。
/// デスクトップ版(openManidoc)の showCardColorDialog 準拠。
/// 外部パッケージに依存せず、プリセットパレット + Hex 入力で選ぶ。
Future<CardColorResult?> showCardColorDialog(
  BuildContext context, {
  String initialFore = '',
  String initialBack = '',
}) {
  return showDialog<CardColorResult>(
    context: context,
    builder: (context) => _CardColorDialog(
      initialFore: initialFore,
      initialBack: initialBack,
    ),
  );
}

/// 選択用のプリセット色。よく使う色相 + 無彩色。
const List<String> _palette = [
  '#e53935', '#d81b60', '#8e24aa', '#5e35b1',
  '#3949ab', '#1e88e5', '#039be5', '#00acc1',
  '#00897b', '#43a047', '#7cb342', '#c0ca33',
  '#fdd835', '#ffb300', '#fb8c00', '#f4511e',
  '#6d4c41', '#757575', '#546e7a', '#000000',
  '#455a64', '#90a4ae', '#bdbdbd', '#ffffff',
];

class _CardColorDialog extends StatefulWidget {
  final String initialFore;
  final String initialBack;

  const _CardColorDialog({
    required this.initialFore,
    required this.initialBack,
  });

  @override
  State<_CardColorDialog> createState() => _CardColorDialogState();
}

class _CardColorDialogState extends State<_CardColorDialog> {
  late String _fore = widget.initialFore;
  late String _back = widget.initialBack;
  bool _editingBack = true; // 編集対象: true=背景色, false=文字色
  late final TextEditingController _hexController =
      TextEditingController(text: _current);

  String get _current => _editingBack ? _back : _fore;

  set _current(String hex) {
    if (_editingBack) {
      _back = hex;
    } else {
      _fore = hex;
    }
  }

  void _select(String hex) {
    setState(() {
      _current = hex;
      _hexController.text = hex;
    });
  }

  void _switchTarget(bool back) {
    setState(() {
      _editingBack = back;
      _hexController.text = _current;
    });
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('タイルの色'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPreview(context),
              const SizedBox(height: 6),
              _buildContrastLine(context),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('背景色')),
                  ButtonSegment(value: false, label: Text('文字色')),
                ],
                selected: {_editingBack},
                onSelectionChanged: (s) => _switchTarget(s.first),
              ),
              const SizedBox(height: 12),
              const Text('パレットから選ぶ'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hex in _palette) _buildSwatch(context, hex),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hexController,
                decoration: const InputDecoration(
                  labelText: 'Hex (#rrggbb)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
                  LengthLimitingTextInputFormatter(7),
                ],
                onChanged: (v) {
                  final c = colorFromHex(v);
                  if (c != null) setState(() => _current = hexFromColor(c));
                },
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('既定に戻す'),
                    onPressed: () => _select(''),
                  ),
                  if (_editingBack)
                    TextButton.icon(
                      icon: const Icon(Icons.contrast, size: 18),
                      label: const Text('文字色を自動'),
                      onPressed: () {
                        final bg = colorFromHex(_back);
                        if (bg == null) return;
                        setState(() =>
                            _fore = hexFromColor(contrastForegroundFor(bg)));
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, CardColorResult(fore: _fore, back: _back)),
          child: const Text('適用'),
        ),
      ],
    );
  }

  Widget _buildContrastLine(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final back = colorFromHex(_back) ?? scheme.surfaceContainerLow;
    final fore = colorFromHex(_fore) ?? contrastForegroundFor(back);
    final ratio = contrastRatio(fore, back);
    final (label, color) = ratio >= kReadableContrast
        ? ('読みやすい', scheme.primary)
        : ratio >= 3.0
            ? ('大きな文字向き', scheme.tertiary)
            : ('読みにくい', scheme.error);
    return Row(
      children: [
        Text('コントラスト比 ${ratio.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 8),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                )),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final back = colorFromHex(_back) ?? scheme.surfaceContainerLow;
    final fore = colorFromHex(_fore) ?? scheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: back,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('プロジェクト名',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: fore)),
          const SizedBox(height: 8),
          Text('2026-08-19',
              style: TextStyle(
                  fontSize: 12, color: fore.withValues(alpha: 0.75))),
        ],
      ),
    );
  }

  Widget _buildSwatch(BuildContext context, String hex) {
    final color = colorFromHex(hex) ?? Colors.transparent;
    final selected = _current.toLowerCase() == hex.toLowerCase();
    return Tooltip(
      message: hex,
      child: InkWell(
        onTap: () => _select(hex),
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}
