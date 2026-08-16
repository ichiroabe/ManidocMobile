import 'dart:convert';
import 'dart:io';
import '../models/manidoc_project.dart';

/// Windows向け: ローカルフォルダでManidocプロジェクトを読み書きするサービス
class LocalStorageService {
  /// ワークスペース直下に置かれる、プロジェクトではないJSON。
  /// project.colors.json はデスクトップ版のタイル色のミラー。
  static const _reservedJsonNames = {
    'workspace.settings.json',
    'project.colors.json',
  };

  /// フォルダ内のプロジェクトJSON一覧を返す
  /// Manidoc形式: フォルダ直下に {UUID}.json + {UUID}/ サブフォルダ
  Future<List<LocalProjectInfo>> listProjectFiles(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return [];

    final results = <LocalProjectInfo>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final name = entity.uri.pathSegments.last;
        if (_reservedJsonNames.contains(name)) continue;
        final baseName = name.replaceAll('.json', '');
        final projDir = Directory('${dir.path}/$baseName');
        results.add(LocalProjectInfo(
          filePath: entity.path,
          projectFolderPath: await projDir.exists() ? projDir.path : null,
        ));
      }
    }
    return results;
  }

  /// プロジェクトJSONを読み込む
  Future<ManidocProject?> readProject(
    String filePath, {
    bool readOnly = false,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final jsonStr = await file.readAsString(encoding: utf8);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      // プロジェクト以外のJSONは開かない(開いて保存すると元ファイルを壊すため)
      if (!ManidocProject.looksLikeProject(json)) return null;
      final project = ManidocProject.fromJson(json);
      project.localFilePath = filePath;
      project.isReadOnly = readOnly;
      return project;
    } catch (_) {
      return null;
    }
  }

  /// 新規プロジェクトを保存
  /// workspace/
  ///   {UUID}.json
  ///   {UUID}/
  ///     images/
  ///     output/
  Future<bool> createProject(ManidocProject project, String folderPath) async {
    try {
      // プロジェクトフォルダ作成
      final projDir = Directory('$folderPath/${project.id}');
      await projDir.create(recursive: true);
      await Directory('${projDir.path}/images').create();
      await Directory('${projDir.path}/output').create();

      // JSON保存
      final filePath = '$folderPath/${project.id}.json';
      project.localFilePath = filePath;
      await File(filePath).writeAsString(
        jsonEncode(project.toJson()),
        encoding: utf8,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// プロジェクトを上書き保存
  Future<bool> updateProject(ManidocProject project) async {
    final path = project.localFilePath;
    if (path == null) return false;
    try {
      project.lastModifiedAt = DateTime.now();
      await File(path).writeAsString(
        jsonEncode(project.toJson()),
        encoding: utf8,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// プロジェクトを削除（JSONファイル + プロジェクトフォルダ）
  Future<void> deleteProject(ManidocProject project) async {
    final path = project.localFilePath;
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();

      // プロジェクトフォルダも削除
      final baseName = file.uri.pathSegments.last.replaceAll('.json', '');
      final projDir = Directory('${file.parent.path}/$baseName');
      if (await projDir.exists()) {
        await projDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  /// 画像ファイルをプロジェクトフォルダにコピー
  Future<String?> saveImage(
    File sourceFile,
    String fileName,
    String projectFolderPath,
  ) async {
    try {
      final imagesDir = Directory('$projectFolderPath/images');
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
      final destPath = '${imagesDir.path}/$fileName';
      await sourceFile.copy(destPath);
      return destPath;
    } catch (_) {
      return null;
    }
  }
}

class LocalProjectInfo {
  final String filePath;
  final String? projectFolderPath;

  LocalProjectInfo({
    required this.filePath,
    this.projectFolderPath,
  });
}
