import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';

/// WebページやHTML文字列をManidocのツリーへ変換する。
/// デスクトップ版(openManidoc)の HtmlImport 準拠。
/// h1〜h6を階層ノードに、それ以外のテキストをMarkdown風の本文に変換する。
///
/// デスクトップ版は画像を images/ フォルダへ取り込むが、モバイル版のノード
/// 表示は http(s) の画像URLをそのまま Image.network で描画できるため、
/// 画像は解決した絶対URLを imagePath / 本文にそのまま入れる（ダウンロード不要）。
class HtmlImport {
  /// WebページのURLをプロジェクト化する。
  static Future<ManidocProject> importUrl(String url) async {
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('ページの取得に失敗しました (${response.statusCode})');
    }
    final content = utf8.decode(response.bodyBytes, allowMalformed: true);
    return parseHtml(content, fallbackName: url, baseUrl: url);
  }

  /// HTML文字列をプロジェクトへ変換する（ネットワーク不要・テスト可能）。
  /// [baseUrl] があれば相対画像URLを絶対URLに解決する。
  static ManidocProject parseHtml(
    String content, {
    String fallbackName = '',
    String? baseUrl,
  }) {
    final doc = html_parser.parse(content);
    final title = doc.querySelector('title')?.text.trim();
    final project = ManidocProject.create(
        (title == null || title.isEmpty) ? fallbackName : title);
    final base = baseUrl != null ? Uri.tryParse(baseUrl) : null;
    _parseInto(project, content, (src) {
      if (base == null) return src;
      try {
        return base.resolve(src).toString();
      } catch (_) {
        return src;
      }
    });
    return project;
  }

  static void _parseInto(
    ManidocProject project,
    String htmlContent,
    String? Function(String src) resolveImage,
  ) {
    final doc = html_parser.parse(htmlContent);
    final body = doc.body;
    if (body == null) return;

    final stack = <(int, ManidocNode)>[];
    ManidocNode? current;
    final buffer = StringBuffer();
    var firstImageForNode = true;

    void flush() {
      final text = buffer.toString().trim();
      if (current != null) {
        current!.article = text;
      } else if (text.isNotEmpty) {
        project.rootNodes.add(ManidocNode.create('はじめに')..article = text);
      }
      buffer.clear();
    }

    void setImage(String rel) {
      final node = current;
      if (node != null && firstImageForNode && node.imagePath.isEmpty) {
        node.imagePath = rel;
        firstImageForNode = false;
      } else {
        buffer.writeln('![]($rel)\n');
      }
    }

    void images(dom.Element element) {
      final imgs = element.localName == 'img'
          ? [element]
          : element.querySelectorAll('img');
      for (final img in imgs) {
        final src = img.attributes['src'];
        if (src == null || src.isEmpty || src.startsWith('data:')) continue;
        final rel = resolveImage(src);
        if (rel != null) setImage(rel);
      }
    }

    void walk(dom.Element element) {
      for (final child in element.children) {
        final tag = child.localName ?? '';
        final headingMatch = RegExp(r'^h([1-6])$').firstMatch(tag);
        if (headingMatch != null) {
          flush();
          final level = int.parse(headingMatch.group(1)!);
          final node = ManidocNode.create(child.text.trim());
          while (stack.isNotEmpty && stack.last.$1 >= level) {
            stack.removeLast();
          }
          if (stack.isEmpty) {
            project.rootNodes.add(node);
          } else {
            stack.last.$2.children.add(node);
          }
          stack.add((level, node));
          current = node;
          firstImageForNode = true;
          continue;
        }
        switch (tag) {
          case 'p':
            final text = child.text.trim();
            if (text.isNotEmpty) buffer.writeln('$text\n');
            images(child);
          case 'ul':
            for (final li in child.querySelectorAll('li')) {
              buffer.writeln('- ${li.text.trim()}');
            }
            buffer.writeln();
          case 'ol':
            var i = 1;
            for (final li in child.querySelectorAll('li')) {
              buffer.writeln('${i++}. ${li.text.trim()}');
            }
            buffer.writeln();
          case 'pre':
            buffer.writeln('```\n${child.text.trimRight()}\n```\n');
          case 'table':
            for (final row in child.querySelectorAll('tr')) {
              final cells = row
                  .querySelectorAll('th,td')
                  .map((c) => c.text.trim())
                  .toList();
              buffer.writeln('| ${cells.join(' | ')} |');
            }
            buffer.writeln();
          case 'img':
            images(child);
          case 'script':
          case 'style':
          case 'nav':
          case 'footer':
          case 'header':
            break; // 本文と無関係な要素はスキップ
          default:
            walk(child); // div/section/article等は中へ
        }
      }
    }

    walk(body);
    flush();
    if (project.rootNodes.isEmpty) {
      project.rootNodes.add(ManidocNode.create(project.name));
    }
  }
}
