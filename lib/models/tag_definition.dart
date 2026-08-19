/// ワークスペースのタグ定義（名前 + 任意の色）。
/// デスクトップ版(openManidoc)の workspace.settings.json の tags[] と互換。
/// デスクトップ版は name / imagePath を持つ。ここではそれに color を足す。
/// imagePath などこのアプリが扱わないフィールドは [extra] に退避して往復させる。
class TagDefinition {
  static const _knownKeys = {'name', 'color'};

  String name;

  /// タイル背景色 '#rrggbb'。空文字なら色なし。
  String color;

  /// デスクトップ版が付ける未知フィールド(imagePath など)。保存時に落とさない。
  final Map<String, dynamic> extra;

  TagDefinition({
    required this.name,
    this.color = '',
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  factory TagDefinition.fromJson(Map<String, dynamic> json) => TagDefinition(
        name: json['name'] as String? ?? '',
        color: json['color'] as String? ?? '',
        extra: Map<String, dynamic>.from(json)
          ..removeWhere((key, _) => _knownKeys.contains(key)),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'name': name,
        if (color.isNotEmpty) 'color': color,
      };
}
