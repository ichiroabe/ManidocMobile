import 'package:flutter_test/flutter_test.dart';
import 'package:manidoc_mobile/models/tag_definition.dart';

/// タグ定義(名前 + 色)が JSON を往復し、デスクトップ版の未知フィールド
/// (imagePath など)を落とさないことを固定する。
void main() {
  test('name と color を往復し、色が空ならキーを出さない', () {
    final tag = TagDefinition(name: '設計', color: '#1e88e5');
    final json = tag.toJson();
    expect(json['name'], '設計');
    expect(json['color'], '#1e88e5');

    final back = TagDefinition.fromJson(json);
    expect(back.name, '設計');
    expect(back.color, '#1e88e5');

    // 色なしは color キーを出さない
    final noColor = TagDefinition(name: 'メモ');
    expect(noColor.toJson().containsKey('color'), false);
  });

  test('デスクトップ版の imagePath など未知フィールドは保持する', () {
    final json = {
      'name': '設計',
      'imagePath': '/path/to/thumb.png',
      'color': '#43a047',
    };
    final tag = TagDefinition.fromJson(json);
    expect(tag.name, '設計');
    expect(tag.color, '#43a047');

    final saved = tag.toJson();
    // 未知フィールドは往復で残る
    expect(saved['imagePath'], '/path/to/thumb.png');
    expect(saved['color'], '#43a047');
  });
}
