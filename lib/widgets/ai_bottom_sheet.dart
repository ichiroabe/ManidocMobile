import 'package:flutter/material.dart';
import '../services/gemini_service.dart';

class AiBottomSheet extends StatefulWidget {
  final String currentArticle;
  final void Function(String result) onInsert;

  const AiBottomSheet({
    super.key,
    required this.currentArticle,
    required this.onInsert,
  });

  @override
  State<AiBottomSheet> createState() => _AiBottomSheetState();
}

class _AiBottomSheetState extends State<AiBottomSheet> {
  final _gemini = GeminiService();
  final _customController = TextEditingController();
  String? _result;
  bool _loading = false;
  String? _error;

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    final apiKey = await _gemini.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _error = 'Gemini APIキーが設定されていません。\n設定画面から登録してください。';
        _loading = false;
      });
      return;
    }
    final result = await action();
    setState(() {
      _result = result;
      _loading = false;
      if (result == null) _error = '生成に失敗しました。';
    });
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'AIアシスタント',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _loading
                        ? null
                        : () => _run(
                              () => _gemini.continueText(widget.currentArticle),
                            ),
                    child: const Text('続きを書く'),
                  ),
                  FilledButton.tonal(
                    onPressed: _loading
                        ? null
                        : () => _run(
                              () => _gemini.summarize(widget.currentArticle),
                            ),
                    child: const Text('要約する'),
                  ),
                  FilledButton.tonal(
                    onPressed: _loading
                        ? null
                        : () => _run(
                              () => _gemini.refine(widget.currentArticle),
                            ),
                    child: const Text('文章を整える'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customController,
                      decoration: const InputDecoration(
                        hintText: 'カスタム指示...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _loading || _customController.text.trim().isEmpty
                        ? null
                        : () => _run(
                              () => _gemini.custom(
                                _customController.text.trim(),
                                widget.currentArticle,
                              ),
                            ),
                    child: const Text('送信'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red))
              else if (_result != null) ...[
                Text(
                  '生成結果',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_result!),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => setState(() => _result = null),
                      child: const Text('破棄'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        widget.onInsert(_result!);
                        Navigator.pop(context);
                      },
                      child: const Text('挿入'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
