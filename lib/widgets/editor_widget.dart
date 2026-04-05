import 'dart:io' show Platform;
import 'package:flutter/material.dart';

/// プラットフォーム共通のエディタインターフェース
/// Android: WebViewEditor, Windows: TextFieldEditor
class EditorWidget extends StatefulWidget {
  final String initialContent;
  final bool readOnly;
  final VoidCallback? onContentChanged;

  const EditorWidget({
    super.key,
    required this.initialContent,
    this.readOnly = false,
    this.onContentChanged,
  });

  @override
  State<EditorWidget> createState() => EditorWidgetState();
}

class EditorWidgetState extends State<EditorWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    if (!widget.readOnly) {
      _controller.addListener(() => widget.onContentChanged?.call());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<String> getMarkdown() async => _controller.text;

  Future<void> setMarkdown(String markdown) async {
    _controller.text = markdown;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: null,
      expands: true,
      readOnly: widget.readOnly,
      style: TextStyle(
        fontFamily: Platform.isWindows ? 'Consolas' : null,
        fontSize: 14,
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(16),
        hintText: 'Markdownで記述...',
      ),
    );
  }
}
