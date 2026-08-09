class WorkspaceInfo {
  final String name;
  // SAF のツリーURI（利用者が選んだフォルダへの永続的なアクセス権）
  final String treeUri;
  // ツリー内のドキュメントID
  final String windowsFolderId; // ワークスペース直下（Windows版が書く場所）
  final String androidFolderId; // _android（このアプリが書く場所）
  // ローカルフォルダパス（Windows Flutter用）
  final String? localPath;

  const WorkspaceInfo({
    required this.name,
    this.treeUri = '',
    this.windowsFolderId = '',
    this.androidFolderId = '',
    this.localPath,
  });

  factory WorkspaceInfo.fromJson(Map<String, dynamic> json) => WorkspaceInfo(
        name: json['name'] as String,
        treeUri: json['treeUri'] as String? ?? '',
        windowsFolderId: json['windowsFolderId'] as String? ?? '',
        androidFolderId: json['androidFolderId'] as String? ?? '',
        localPath: json['localPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'treeUri': treeUri,
        'windowsFolderId': windowsFolderId,
        'androidFolderId': androidFolderId,
        if (localPath != null) 'localPath': localPath,
      };
}
