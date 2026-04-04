class WorkspaceInfo {
  final String name;
  final String windowsFolderId; // Google Drive フォルダID（Windowsデータ・読み取り専用）
  final String androidFolderId; // Google Drive フォルダID（Android専用・読み書き）

  const WorkspaceInfo({
    required this.name,
    required this.windowsFolderId,
    required this.androidFolderId,
  });

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) => WorkspaceInfo(
        name: json['name'] as String,
        windowsFolderId: json['windowsFolderId'] as String,
        androidFolderId: json['androidFolderId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'windowsFolderId': windowsFolderId,
        'androidFolderId': androidFolderId,
      };
}
