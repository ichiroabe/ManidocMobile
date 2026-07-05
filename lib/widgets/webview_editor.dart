import 'dart:convert';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Android用 WebView (Tiptap) ラッパー
///
/// バンドルは Manidoc デスクトップの EditorWeb/src/core.js を共有しており、
/// Markdown直列化仕様がデスクトップ版と常に一致する。
/// 再生成: Manidoc/EditorWeb で `node build.mjs mobile` →
/// dist-mobile/* を assets/tiptap/ へコピー。
class WebViewEditor extends StatefulWidget {
  final String initialContent;
  final bool readOnly;

  /// エディタ内容が変わるたび（500msデバウンス）最新のMarkdownを通知
  final ValueChanged<String>? onContentChanged;

  /// 「[[」補完に出すノード一覧（[{id,title,path}] のJSON文字列）
  final String? nodeListJson;

  /// ノードリンク（#node:ID）タップ時にノードIDを通知
  final ValueChanged<String>? onNodeLinkTap;

  const WebViewEditor({
    super.key,
    required this.initialContent,
    this.readOnly = false,
    this.onContentChanged,
    this.nodeListJson,
    this.onNodeLinkTap,
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
        onMessageReceived: (msg) =>
            widget.onContentChanged?.call(msg.message),
      )
      ..addJavaScriptChannel(
        'NodeLinkClicked',
        onMessageReceived: (msg) =>
            widget.onNodeLinkTap?.call(msg.message),
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) async {
          final escaped = jsonEncode(widget.initialContent);
          final isReadOnly = widget.readOnly ? 'true' : 'false';
          await _controller.runJavaScript('initEditor($escaped, $isReadOnly)');
          if (widget.nodeListJson != null) {
            await _controller.runJavaScript('setNodeList(${widget.nodeListJson})');
          }
          if (mounted) setState(() => _ready = true);
        },
      ))
      ..loadFlutterAsset('assets/tiptap/editor.html');
  }

  Future<String> getMarkdown() async {
    if (!_ready) return widget.initialContent;
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
    // 祖先のGestureDetector（ページめくり横スワイプ検出）とのジェスチャー調停で
    // タッチがWebViewに届かず縦スクロール不能になるため、WebView側が
    // 全ジェスチャーを即時に取る
    return WebViewWidget(
      controller: _controller,
      gestureRecognizers: {
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
    );
  }
}
