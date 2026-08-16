import 'package:uuid/uuid.dart';

class ManidocNode {
  /// このクラスが明示的に扱うJSONキー。これ以外は [extra] へ退避して往復させる。
  static const _knownKeys = {
    'id',
    'title',
    'comment',
    'article',
    'imagePath',
    'aiPrompt',
    'children',
  };

  String id;
  String title;
  String comment;
  String article;
  String imagePath;
  String aiPrompt;
  List<ManidocNode> children;

  /// デスクトップ版が付ける未知フィールド(ノード別の読み上げ話者 titleSpeaker など)。
  /// このアプリでは使わないが、保存時に落とさないようそのまま書き戻す。
  final Map<String, dynamic> extra;

  ManidocNode({
    required this.id,
    required this.title,
    this.comment = '',
    this.article = '',
    this.imagePath = '',
    this.aiPrompt = '',
    List<ManidocNode>? children,
    Map<String, dynamic>? extra,
  })  : children = children ?? [],
        extra = extra ?? {};

  factory ManidocNode.create(String title) => ManidocNode(
        id: const Uuid().v4(),
        title: title,
      );

  factory ManidocNode.fromJson(Map<String, dynamic> json) => ManidocNode(
        id: json['id'] as String? ?? const Uuid().v4(),
        title: json['title'] as String? ?? '',
        comment: json['comment'] as String? ?? '',
        article: json['article'] as String? ?? '',
        imagePath: json['imagePath'] as String? ?? '',
        aiPrompt: json['aiPrompt'] as String? ?? '',
        children: (json['children'] as List<dynamic>?)
                ?.map((e) => ManidocNode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        extra: Map<String, dynamic>.from(json)
          ..removeWhere((key, _) => _knownKeys.contains(key)),
      );

  // 未知フィールドを先に展開し、既知フィールドで上書きする
  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'title': title,
        'comment': comment,
        'article': article,
        'imagePath': imagePath,
        'aiPrompt': aiPrompt,
        'children': children.map((e) => e.toJson()).toList(),
      };

  ManidocNode? findById(String nodeId) {
    if (id == nodeId) return this;
    for (final child in children) {
      final found = child.findById(nodeId);
      if (found != null) return found;
    }
    return null;
  }
}
