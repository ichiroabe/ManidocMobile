import 'package:flutter_test/flutter_test.dart';
import 'package:manidoc_mobile/services/html_import.dart';

/// Webインポート(HTML→ツリー変換)の主要な変換を固定する。
void main() {
  test('title がプロジェクト名になり、見出しが階層ノードになる', () {
    const html = '''
<html>
  <head><title>サンプル記事</title></head>
  <body>
    <h1>大見出し</h1>
    <p>導入の段落。</p>
    <h2>小見出しA</h2>
    <p>Aの本文。</p>
    <h2>小見出しB</h2>
    <p>Bの本文。</p>
  </body>
</html>
''';
    final project = HtmlImport.parseHtml(html, fallbackName: 'fallback');
    expect(project.name, 'サンプル記事');
    // h1 が1つのルート、その下に h2 が2つ
    expect(project.rootNodes.length, 1);
    final root = project.rootNodes.single;
    expect(root.title, '大見出し');
    expect(root.article, contains('導入の段落'));
    expect(root.children.length, 2);
    expect(root.children[0].title, '小見出しA');
    expect(root.children[0].article, contains('Aの本文'));
    expect(root.children[1].title, '小見出しB');
  });

  test('相対画像URLは baseUrl で絶対URLに解決し、最初の画像を imagePath にする', () {
    const html = '''
<html><head><title>画像あり</title></head><body>
  <h1>見出し</h1>
  <p>本文<img src="/img/pic.png"></p>
</body></html>
''';
    final project = HtmlImport.parseHtml(html,
        baseUrl: 'https://example.com/articles/1');
    final root = project.rootNodes.single;
    expect(root.imagePath, 'https://example.com/img/pic.png');
  });

  test('title が無ければ fallbackName を使い、本文だけでもノードを作る', () {
    const html = '<html><body><p>見出しのない本文。</p></body></html>';
    final project = HtmlImport.parseHtml(html, fallbackName: 'https://x.test');
    expect(project.name, 'https://x.test');
    expect(project.rootNodes, isNotEmpty);
    expect(project.rootNodes.first.article, contains('見出しのない本文'));
  });

  test('table はヘッダー直後に区切り行を入れたMarkdown表になる', () {
    const html = '''
<html><body>
<h1>T</h1>
<table>
  <tr><th>モデル</th><th>メモリ</th></tr>
  <tr><td>7B</td><td>5〜8 GB</td></tr>
</table>
</body></html>
''';
    final project = HtmlImport.parseHtml(html, fallbackName: 'x');
    final article = project.rootNodes.single.article;
    // ヘッダー行の直後に区切り行(| --- | --- |)が必須。これが無いと
    // Markdownの表として描画されない(修正前のバグ)。
    expect(article, contains('| モデル | メモリ |'));
    expect(article, contains('| --- | --- |'));
    final headerIdx = article.indexOf('| モデル | メモリ |');
    final sepIdx = article.indexOf('| --- | --- |');
    final dataIdx = article.indexOf('| 7B | 5〜8 GB |');
    expect(headerIdx, lessThan(sepIdx));
    expect(sepIdx, lessThan(dataIdx));
  });

  test('table のセル内の | と改行は表を壊さないよう整形される', () {
    const html = '''
<html><body>
<h1>T</h1>
<table>
  <tr><th>A</th><th>B</th></tr>
  <tr><td>x | y</td><td>line1
line2</td></tr>
</table>
</body></html>
''';
    final project = HtmlImport.parseHtml(html, fallbackName: 'x');
    final article = project.rootNodes.single.article;
    expect(article, contains(r'x \| y'));
    expect(article, contains('| line1 line2 |'));
    expect(article, isNot(contains('line1\nline2')));
  });
}
