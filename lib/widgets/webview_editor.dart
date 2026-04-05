import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Android用 WebView (Toast UI Editor) ラッパー
class WebViewEditor extends StatefulWidget {
  final String initialContent;
  final bool readOnly;
  final VoidCallback? onContentChanged;

  const WebViewEditor({
    super.key,
    required this.initialContent,
    this.readOnly = false,
    this.onContentChanged,
  });

  @override
  State<WebViewEditor> createState() => WebViewEditorState();
}

class WebViewEditorState extends State<WebViewEditor> {
  late WebViewController _controller;
  bool _ready = false;

  bool get isReady => _ready;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'ContentChanged',
        onMessageReceived: (_) => widget.onContentChanged?.call(),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) async {
          _ready = true;
          final escaped = jsonEncode(widget.initialContent);
          final isReadOnly = widget.readOnly ? 'true' : 'false';
          await _controller.runJavaScript('initEditor($escaped, $isReadOnly)');
        },
      ))
      ..loadFlutterAsset('assets/editor.html');
  }

  Future<String> getMarkdown() async {
    final result =
        await _controller.runJavaScriptReturningResult('getMarkdown()');
    final raw = result.toString();
    try {
      return jsonDecode(raw) as String;
    } catch (_) {
      return raw.replaceAll(RegExp(r'^"|"$'), '');
    }
  }

  Future<void> setMarkdown(String markdown) async {
    final escaped = jsonEncode(markdown);
    await _controller.runJavaScript('setMarkdown($escaped)');
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
