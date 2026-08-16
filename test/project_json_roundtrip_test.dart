import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:manidoc_mobile/models/manidoc_node.dart';
import 'package:manidoc_mobile/models/manidoc_project.dart';

/// デスクトップ版(Manidoc / openManidoc)が付けるフィールドを、
/// このアプリで開いて保存しても落とさないことを固定する。
void main() {
  const desktopJson = '''
{
  "id": "11111111-2222-3333-4444-555555555555",
  "name": "色つきプロジェクト",
  "createdAt": "2026-08-16T10:00:00.000",
  "lastModifiedAt": "2026-08-16T10:00:00.000",
  "description": "",
  "lastSelectedNodeId": "",
  "sortOrder": 3,
  "themeCssFileName": "",
  "tag": "設計",
  "cardForeColor": "#ffffff",
  "cardBackColor": "#1e88e5",
  "rootNodes": [
    {
      "id": "aaaa",
      "title": "はじめに",
      "article": "本文",
      "comment": "",
      "imagePath": "",
      "aiPrompt": "",
      "titleSpeaker": 8,
      "articleSpeaker": 3,
      "children": []
    }
  ]
}
''';

  test('タイル色とノード別話者は保存しても消えない', () {
    final project =
        ManidocProject.fromJson(jsonDecode(desktopJson) as Map<String, dynamic>);

    // 既知のフィールドは従来どおり読める
    expect(project.name, '色つきプロジェクト');
    expect(project.tag, '設計');
    expect(project.rootNodes.single.title, 'はじめに');

    final saved = project.toJson();
    expect(saved['cardForeColor'], '#ffffff');
    expect(saved['cardBackColor'], '#1e88e5');

    final savedNode = (saved['rootNodes'] as List).single as Map<String, dynamic>;
    expect(savedNode['titleSpeaker'], 8);
    expect(savedNode['articleSpeaker'], 3);

    // 既知フィールドが未知フィールドに上書きされていない
    expect(saved['name'], '色つきプロジェクト');
    expect(savedNode['article'], '本文');
  });

  test('編集した内容は未知フィールドを保ったまま反映される', () {
    final project =
        ManidocProject.fromJson(jsonDecode(desktopJson) as Map<String, dynamic>);
    project.name = '改名した';
    project.rootNodes.add(ManidocNode.create('追加したノード'));

    final saved = project.toJson();
    expect(saved['name'], '改名した');
    expect((saved['rootNodes'] as List).length, 2);
    expect(saved['cardBackColor'], '#1e88e5');
  });

  test('project.colors.json のような別用途のJSONはプロジェクトと見なさない', () {
    const mirror = '{"11111111": {"fore": "#ffffff", "back": "#1e88e5"}}';
    expect(
        ManidocProject.looksLikeProject(
            jsonDecode(mirror) as Map<String, dynamic>),
        false);
    expect(
        ManidocProject.looksLikeProject(
            jsonDecode(desktopJson) as Map<String, dynamic>),
        true);
  });
}
