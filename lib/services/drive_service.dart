import 'dart:convert';
import 'dart:io' as dart_io;
import 'package:googleapis/drive/v3.dart' as drive;
import '../models/manidoc_project.dart';
import 'auth_service.dart';

class DriveService {
  final _auth = AuthService();

  Future<drive.DriveApi?> _getApi() async {
    final client = await _auth.getAuthClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  // フォルダ一覧を取得
  Future<List<drive.File>> listFolders({String? parentId}) async {
    final api = await _getApi();
    if (api == null) return [];

    final q = parentId != null
        ? "'$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        : "mimeType = 'application/vnd.google-apps.folder' and 'root' in parents and trashed = false";

    try {
      final result = await api.files.list(
        q: q,
        $fields: 'files(id, name)',
        orderBy: 'name',
      );
      return result.files ?? [];
    } catch (_) {
      return [];
    }
  }

  // フォルダ内のプロジェクトJSON一覧（直下 + UUIDサブフォルダ内）
  Future<List<ProjectFileInfo>> listProjectFiles(String folderId) async {
    final api = await _getApi();
    if (api == null) return [];

    try {
      // 直下のJSONファイル（旧形式: プロジェクト名.json）
      final direct = await api.files.list(
        q: "'$folderId' in parents "
            "and name != 'workspace.settings.json' "
            "and name contains '.json' "
            "and trashed = false",
        $fields: 'files(id, name, modifiedTime)',
        orderBy: 'name',
      );

      // サブフォルダ一覧（新形式: UUID/ フォルダ内の UUID.json）
      final subFolders = await api.files.list(
        q: "'$folderId' in parents "
            "and mimeType = 'application/vnd.google-apps.folder' "
            "and trashed = false",
        $fields: 'files(id, name)',
      );

      // サブフォルダをUUID名→IDのマップに変換
      final subFolderMap = <String, String>{};
      for (final folder in (subFolders.files ?? [])) {
        if (folder.id != null && folder.name != null) {
          subFolderMap[folder.name!] = folder.id!;
        }
      }

      final results = <ProjectFileInfo>[];

      // 直下のJSONファイル: 対応するUUIDフォルダがあればhasProjectFolder=true
      for (final f in (direct.files ?? [])) {
        final baseName = f.name?.replaceAll('.json', '') ?? '';
        final projFolderId = subFolderMap[baseName];
        results.add(ProjectFileInfo(
          file: f,
          parentFolderId: projFolderId ?? folderId,
          hasProjectFolder: projFolderId != null,
        ));
      }

      // UUIDフォルダ内のJSONも走査（古いAndroid形式: JSON がフォルダ内にある場合）
      for (final folder in (subFolders.files ?? [])) {
        if (folder.id == null) continue;
        final inner = await api.files.list(
          q: "'${folder.id}' in parents "
              "and name contains '.json' "
              "and trashed = false",
          $fields: 'files(id, name, modifiedTime)',
        );
        for (final f in (inner.files ?? [])) {
          // 直下JSONと重複しないように（同名JSONが直下にある場合はスキップ）
          final alreadyAdded = results.any((r) => r.file.name == f.name);
          if (!alreadyAdded) {
            results.add(ProjectFileInfo(
              file: f,
              parentFolderId: folder.id!,
              hasProjectFolder: true,
            ));
          }
        }
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  // プロジェクトJSONを読み込む
  Future<ManidocProject?> readProject(
    drive.File file, {
    bool readOnly = false,
    String? folderId,
    bool hasProjectFolder = false,
  }) async {
    final api = await _getApi();
    if (api == null || file.id == null) return null;

    try {
      final media = await api.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = await media.stream.expand((b) => b).toList();
      final jsonStr = utf8.decode(bytes);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final project = ManidocProject.fromJson(json);
      project.driveFileId = file.id;
      project.driveFolderId = folderId;
      project.isReadOnly = readOnly;
      project.hasProjectFolder = hasProjectFolder;
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
    final api = await _getApi();
    if (api == null) return null;

    try {
      // 1. {UUID}/ フォルダをワークスペース直下に作成
      final projFolder = drive.File()
        ..name = project.id
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [folderId];
      final projFolderResult = await api.files.create(projFolder);
      final projFolderId = projFolderResult.id!;

      // 2. images/ と output/ をプロジェクトフォルダ内に作成
      for (final subName in ['images', 'output']) {
        final sub = drive.File()
          ..name = subName
          ..mimeType = 'application/vnd.google-apps.folder'
          ..parents = [projFolderId];
        await api.files.create(sub);
      }

      // 3. {UUID}.json をワークスペース直下に作成（{UUID}/の外）
      final bytes = utf8.encode(jsonEncode(project.toJson()));
      final file = drive.File()
        ..name = '${project.id}.json'
        ..parents = [folderId]   // ← ワークスペース直下
        ..mimeType = 'application/json';
      final media = drive.Media(Stream.value(bytes), bytes.length);
      final result = await api.files.create(file, uploadMedia: media);

      // プロジェクトフォルダID（images/の親）を保存
      project.driveFolderId = projFolderId;
      project.hasProjectFolder = true;
      return result.id;
    } catch (e) {
      rethrow;
    }
  }

  // プロジェクトを上書き保存
  Future<bool> updateProject(ManidocProject project) async {
    final api = await _getApi();
    if (api == null || project.driveFileId == null) return false;

    try {
      project.lastModifiedAt = DateTime.now();
      final bytes = utf8.encode(jsonEncode(project.toJson()));
      final file = drive.File()..name = '${project.id}.json';
      final media = drive.Media(Stream.value(bytes), bytes.length);
      await api.files.update(file, project.driveFileId!, uploadMedia: media);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ファイルを削除
  Future<void> deleteFile(String fileId) async {
    final api = await _getApi();
    if (api == null) return;
    try {
      await api.files.delete(fileId);
    } catch (_) {}
  }

  // 任意のフォルダを作成
  Future<String?> createFolder(String name, {String? parentId}) async {
    final api = await _getApi();
    if (api == null) return null;

    try {
      final folder = drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder';
      if (parentId != null) folder.parents = [parentId];
      final created = await api.files.create(folder);
      return created.id;
    } catch (_) {
      return null;
    }
  }

  // フォルダ内のファイルを名前で検索してIDを返す
  Future<String?> findFileIdByName(String folderId, String name) async {
    final api = await _getApi();
    if (api == null) return null;
    try {
      final escaped = name.replaceAll("'", "\\'");
      final result = await api.files.list(
        q: "'$folderId' in parents and name = '$escaped' and trashed = false",
        $fields: 'files(id)',
      );
      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.id;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ファイルのバイトをダウンロード
  Future<List<int>?> downloadFileBytes(String fileId) async {
    final api = await _getApi();
    if (api == null) return null;
    try {
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      return await media.stream.expand((b) => b).toList();
    } catch (_) {
      return null;
    }
  }

  // サブフォルダを取得または作成
  Future<String?> getOrCreateSubFolder(String name, {String? parentId}) async {
    final api = await _getApi();
    if (api == null || parentId == null) return null;

    try {
      final result = await api.files.list(
        q: "'$parentId' in parents "
            "and name = '$name' "
            "and mimeType = 'application/vnd.google-apps.folder' "
            "and trashed = false",
        $fields: 'files(id)',
      );

      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.id;
      }

      final folder = drive.File()
        ..name = name
        ..parents = [parentId]
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await api.files.create(folder);
      return created.id;
    } catch (_) {
      return null;
    }
  }

  // 画像ファイルをアップロード → Drive file ID を返す
  Future<String?> uploadImage(
      dart_io.File file, String fileName, String folderId) async {
    final api = await _getApi();
    if (api == null) return null;

    try {
      final bytes = await file.readAsBytes();
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId]
        ..mimeType = 'image/png';
      final media = drive.Media(Stream.value(bytes), bytes.length);
      final result = await api.files.create(driveFile, uploadMedia: media);
      return result.id;
    } catch (_) {
      return null;
    }
  }

  // Android用フォルダを取得または作成
  Future<String?> getOrCreateAndroidFolder(String parentFolderId) async {
    final api = await _getApi();
    if (api == null) return null;

    try {
      final result = await api.files.list(
        q: "'$parentFolderId' in parents "
            "and name = '_android' "
            "and mimeType = 'application/vnd.google-apps.folder' "
            "and trashed = false",
        $fields: 'files(id)',
      );

      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.id;
      }

      final folder = drive.File()
        ..name = '_android'
        ..parents = [parentFolderId]
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await api.files.create(folder);
      return created.id;
    } catch (_) {
      return null;
    }
  }
}

class ProjectFileInfo {
  final drive.File file;
  final String parentFolderId;
  final bool hasProjectFolder;
  ProjectFileInfo({
    required this.file,
    required this.parentFolderId,
    required this.hasProjectFolder,
  });
}
