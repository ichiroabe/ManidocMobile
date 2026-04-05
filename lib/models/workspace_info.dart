class WorkspaceInfo {
  final String name;
  // Google Drive フォルダID（Android用）
  final String windowsFolderId;
  final String androidFolderId;
  // ローカルフォルダパス（Windows Flutter用）
  final String? localPath;

  const WorkspaceInfo({
    required this.name,
    this.windowsFolderId = '',
    this.androidFolderId = '',
    this.localPath,
  });

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) => WorkspaceInfo(
        name: json['name'] as String,
        windowsFolderId: json['windowsFolderId'] as String? ?? '',
        androidFolderId: json['androidFolderId'] as String? ?? '',
        localPath: json['localPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'windowsFolderId': windowsFolderId,
        'androidFolderId': androidFolderId,
        if (localPath != null) 'localPath': localPath,
      };
}
