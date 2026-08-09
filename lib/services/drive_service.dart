import 'dart:convert';
import 'dart:io' as dart_io;
import 'dart:typed_data';

import '../models/manidoc_project.dart';
import 'saf_service.dart';

/// ワークスペースへのアクセス。中身は Storage Access Framework で、
/// Google Drive でも端末内フォルダでも同じコードで動く（OAuth 不要）。
///
/// 歴史的な経緯でクラス名と `driveFileId` などの呼称はそのまま残している。
/// 実体は「利用者が選んだツリーの中のドキュメントID」。
class DriveService {
  static final _saf = SafService();

  /// 現在開いているワークスペースのツリーURI。
  /// ワークスペースを開くときに設定する。
  static String? currentTree;

  static const _jsonMime = 'application/json';

  String? get _tree => currentTree;

  /// フォルダ内のプロジェクトJSON一覧（直下 + UUIDサブフォルダ内）
  ///
  /// 失敗は握りつぶさず投げる。「0件」と「読めなかった」を呼び出し側で
  /// 区別できないと、原因の分からない空一覧になるため。
  Future<List<ProjectFileInfo>> listProjectFiles(String folderId) async {
    final tree = _tree;
    if (tree == null) {
      throw StateError('ワークスペースが開かれていません');
    }

    final children = await _saf.listChildren(tree, doc: folderId);

    // 直下のJSON（旧形式: プロジェクト名.json）
    final direct = children
        .where((e) =>
            !e.isDir &&
            e.name.endsWith('.json') &&
            e.name != 'workspace.settings.json')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    // サブフォルダ（新形式: UUID/ の中に UUID.json）
    final subFolders = children.where((e) => e.isDir).toList();
    final subFolderMap = {for (final f in subFolders) f.name: f.id};

    final results = <ProjectFileInfo>[];

    for (final f in direct) {
      final baseName = f.name.replaceAll('.json', '');
      final projFolderId = subFolderMap[baseName];
      results.add(ProjectFileInfo(
        file: RemoteFile.fromEntry(f),
        parentFolderId: projFolderId ?? folderId,
        hasProjectFolder: projFolderId != null,
      ));
    }

    // UUIDフォルダ内のJSONも走査（古いAndroid形式）
    for (final folder in subFolders) {
      final inner = await _saf.listChildren(tree, doc: folder.id);
      for (final f in inner.where((e) => !e.isDir && e.name.endsWith('.json'))) {
        final alreadyAdded = results.any((r) => r.file.name == f.name);
        if (!alreadyAdded) {
          results.add(ProjectFileInfo(
            file: RemoteFile.fromEntry(f),
            parentFolderId: folder.id,
            hasProjectFolder: true,
          ));
        }
      }
    }

    return results;
  }

  // プロジェクトJSONを読み込む
  Future<ManidocProject?> readProject(
    RemoteFile file, {
    bool readOnly = false,
    String? folderId,
    bool hasProjectFolder = false,
  }) async {
    final tree = _tree;
    if (tree == null) return null;

    try {
      final bytes = await _saf.readBytes(tree, file.id);
      if (bytes == null) return null;
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      final project = ManidocProject.fromJson(json);
      project.driveFileId = file.id;
      project.driveFolderId = folderId;
      project.isReadOnly = readOnly;
      project.hasProjectFolder = hasProjectFolder;
      project.remoteModifiedAt = file.modifiedTime;
      return project;
    } catch (_) {
      return null;
    }
  }

  // 新規プロジェクトを保存（Windows版と同じフォルダ構造）
  // workspace/
  //   {UUID}.json     ← ワークスペース直下
  //   {UUID}/         ← ワークスペース直下（JSONと兄弟）
  //     images/
  //     output/
  Future<String?> createProject(
    ManidocProject project,
    String folderId,
  ) async {
    final tree = _tree;
    if (tree == null) return null;

    final projFolderId =
        await _saf.createDir(tree, parent: folderId, name: project.id);
    if (projFolderId == null) return null;

    for (final subName in ['images', 'output']) {
      await _saf.createDir(tree, parent: projFolderId, name: subName);
    }

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(project.toJson())));
    final fileId = await _saf.createFile(
      tree,
      parent: folderId,
      name: '${project.id}.json',
      mime: _jsonMime,
      bytes: bytes,
    );

    project.driveFolderId = projFolderId;
    project.hasProjectFolder = true;
    return fileId;
  }

  /// ワークスペース側のファイルの現在の更新時刻。存在しなければ null。
  Future<DateTime?> remoteModifiedAt(String fileId) async {
    final tree = _tree;
    if (tree == null) return null;
    try {
      return (await _saf.stat(tree, fileId))?.modified;
    } catch (_) {
      return null;
    }
  }

  // プロジェクトを上書き保存
  Future<bool> updateProject(ManidocProject project) async {
    final tree = _tree;
    if (tree == null || project.driveFileId == null) return false;

    try {
      project.lastModifiedAt = DateTime.now();
      final bytes =
          Uint8List.fromList(utf8.encode(jsonEncode(project.toJson())));
      final ok = await _saf.writeBytes(tree, project.driveFileId!, bytes);
      if (ok) {
        // 次回の衝突判定の基準を、いま書いた結果に更新する
        project.remoteModifiedAt =
            await remoteModifiedAt(project.driveFileId!);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // ファイルを削除
  Future<void> deleteFile(String fileId) async {
    final tree = _tree;
    if (tree == null) return;
    try {
      await _saf.delete(tree, fileId);
    } catch (_) {}
  }

  // 任意のフォルダを作成
  Future<String?> createFolder(String name, {String? parentId}) async {
    final tree = _tree;
    if (tree == null) return null;
    return _saf.createDir(tree, parent: parentId, name: name);
  }

  /// フォルダ直下の一覧。1件ずつ引くと通信回数が嵩むので、
  /// 名前→IDの表を作りたい側はこれを使う。
  Future<List<RemoteFile>> listFolder(String folderId) async {
    final tree = _tree;
    if (tree == null) return [];
    try {
      final children = await _saf.listChildren(tree, doc: folderId);
      return children.map(RemoteFile.fromEntry).toList();
    } catch (_) {
      return [];
    }
  }

  // フォルダ内のファイルを名前で検索してIDを返す
  Future<String?> findFileIdByName(String folderId, String name) async {
    final tree = _tree;
    if (tree == null) return null;
    try {
      final children = await _saf.listChildren(tree, doc: folderId);
      for (final e in children) {
        if (e.name == name) return e.id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ファイルのバイトをダウンロード
  Future<List<int>?> downloadFileBytes(String fileId) async {
    final tree = _tree;
    if (tree == null) return null;
    try {
      return await _saf.readBytes(tree, fileId);
    } catch (_) {
      return null;
    }
  }

  // サブフォルダを取得または作成
  Future<String?> getOrCreateSubFolder(String name, {String? parentId}) async {
    final tree = _tree;
    if (tree == null || parentId == null) return null;

    try {
      final children = await _saf.listChildren(tree, doc: parentId);
      for (final e in children) {
        if (e.isDir && e.name == name) return e.id;
      }
      return await _saf.createDir(tree, parent: parentId, name: name);
    } catch (_) {
      return null;
    }
  }

  // 画像ファイルをアップロード → ドキュメントIDを返す
  Future<String?> uploadImage(
      dart_io.File file, String fileName, String folderId) async {
    final tree = _tree;
    if (tree == null) return null;

    try {
      final bytes = await file.readAsBytes();
      return await _saf.createFile(
        tree,
        parent: folderId,
        name: fileName,
        mime: 'image/png',
        bytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }

  // Android用フォルダを取得または作成
  Future<String?> getOrCreateAndroidFolder(String parentFolderId) =>
      getOrCreateSubFolder('_android', parentId: parentFolderId);
}

/// ワークスペース内のファイル1件。以前は googleapis の drive.File だった。
class RemoteFile {
  final String id;
  final String name;
  final DateTime? modifiedTime;

  const RemoteFile({required this.id, required this.name, this.modifiedTime});

  factory RemoteFile.fromEntry(SafEntry e) =>
      RemoteFile(id: e.id, name: e.name, modifiedTime: e.modified);
}

class ProjectFileInfo {
  final RemoteFile file;
  final String parentFolderId;
  final bool hasProjectFolder;
  ProjectFileInfo({
    required this.file,
    required this.parentFolderId,
    required this.hasProjectFolder,
  });
}
