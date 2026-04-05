import 'package:uuid/uuid.dart';
import 'manidoc_node.dart';

class ManidocProject {
  String id;
  String name;
  DateTime createdAt;
  DateTime lastModifiedAt;
  String description;
  String lastSelectedNodeId;
  int sortOrder;
  String themeCssFileName;
  String tag;
  List<ManidocNode> rootNodes;

  // Drive メタデータ（JSONに保存しない）
  String? driveFileId;
  String? driveFolderId;   // 新形式: UUIDプロジェクトフォルダID / 旧形式: ワークスペースフォルダID
  bool isReadOnly;
  bool hasProjectFolder;   // true=新形式(driveFolderIdがプロジェクトフォルダ) / false=旧形式

  // ローカルメタデータ（Windows用・JSONに保存しない）
  String? localFilePath;

  ManidocProject({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    this.description = '',
    this.lastSelectedNodeId = '',
    this.sortOrder = 0,
    this.themeCssFileName = '',
    this.tag = '',
    List<ManidocNode>? rootNodes,
    this.driveFileId,
    this.driveFolderId,
    this.isReadOnly = false,
    this.hasProjectFolder = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastModifiedAt = lastModifiedAt ?? DateTime.now(),
        rootNodes = rootNodes ?? [];

  factory ManidocProject.create(String name) => ManidocProject(
        id: const Uuid().v4(),
        name: name,
      );

  factory ManidocProject.fromJson(Map<String, dynamic> json) => ManidocProject(
        id: json['id'] as String? ?? const Uuid().v4(),
        name: json['name'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        lastModifiedAt: json['lastModifiedAt'] != null
            ? DateTime.tryParse(json['lastModifiedAt'] as String) ??
                DateTime.now()
            : DateTime.now(),
        description: json['description'] as String? ?? '',
        lastSelectedNodeId: json['lastSelectedNodeId'] as String? ?? '',
        sortOrder: json['sortOrder'] as int? ?? 0,
        themeCssFileName: json['themeCssFileName'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        rootNodes: (json['rootNodes'] as List<dynamic>?)
                ?.map((e) => ManidocNode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'lastModifiedAt': lastModifiedAt.toIso8601String(),
        'description': description,
        'lastSelectedNodeId': lastSelectedNodeId,
        'sortOrder': sortOrder,
        'themeCssFileName': themeCssFileName,
        'tag': tag,
        'rootNodes': rootNodes.map((e) => e.toJson()).toList(),
      };
}
