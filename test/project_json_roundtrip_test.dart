import 'dart:convert';
import 'dart:ui' show Color;

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

  test('タイル色は Color として読める（一覧の行の色に使う）', () {
    final project =
        ManidocProject.fromJson(jsonDecode(desktopJson) as Map<String, dynamic>);
    // #1e88e5 / #ffffff（アルファ無しは不透明扱い）
    expect(project.cardBackColor, const Color(0xFF1E88E5));
    expect(project.cardForeColor, const Color(0xFFFFFFFF));
  });

  test('タイル色が無いプロジェクトは null（既定色にフォールバック）', () {
    final project = ManidocProject.create('色なし');
    expect(project.cardBackColor, isNull);
    expect(project.cardForeColor, isNull);
  });

  test('タイル色の hex を編集すると JSON に往復し、空文字でキーごと落ちる', () {
    final project = ManidocProject.create('色を編集');
    // 設定するとキーが増え、Color としても読める
    project.cardBackColorHex = '#1e88e5';
    project.cardForeColorHex = '#ffffff';
    expect(project.cardBackColorHex, '#1e88e5');
    expect(project.cardBackColor, const Color(0xFF1E88E5));
    final saved = project.toJson();
    expect(saved['cardBackColor'], '#1e88e5');
    expect(saved['cardForeColor'], '#ffffff');

    // 空文字にするとキーごと消える（本家 Manidoc が読むJSONを汚さない）
    project.cardBackColorHex = '';
    expect(project.cardBackColorHex, '');
    expect(project.cardBackColor, isNull);
    expect(project.toJson().containsKey('cardBackColor'), false);
  });

  test('壊れたタイル色は null として扱う', () {
    final project = ManidocProject.fromJson({
      'name': 'こわれた色',
      'rootNodes': <dynamic>[],
      'cardBackColor': 'not-a-color',
      'cardForeColor': '#12',
    });
    expect(project.cardBackColor, isNull);
    expect(project.cardForeColor, isNull);
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
