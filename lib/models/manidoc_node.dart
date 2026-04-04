import 'package:uuid/uuid.dart';

class ManidocNode {
  String id;
  String title;
  String comment;
  String article;
  String imagePath;
  String aiPrompt;
  List<ManidocNode> children;

  ManidocNode({
    required this.id,
    required this.title,
    this.comment = '',
    this.article = '',
    this.imagePath = '',
    this.aiPrompt = '',
    List<ManidocNode>? children,
  }) : children = children ?? [];

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
      );

  Map<String, dynamic> toJson() => {
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
