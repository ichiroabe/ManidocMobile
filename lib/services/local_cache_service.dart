import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/manidoc_project.dart';
import '../models/workspace_info.dart';

/// ワークスペース単位でプロジェクトJSONをローカルにキャッシュするサービス
class LocalCacheService {
  /// キャッシュルートディレクトリを取得
  Future<Directory> _cacheRoot() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/manidoc_cache');
  }

  /// ワークスペース用のキャッシュディレクトリ
  Future<Directory> _workspaceDir(WorkspaceInfo workspace, String type) async {
    final root = await _cacheRoot();
    // ワークスペース名をフォルダ名に使う（安全な名前に変換）
    final safeName = workspace.name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final dir = Directory('${root.path}/$safeName/$type');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// プロジェクト一覧をキャッシュから読み込み
  Future<List<ManidocProject>> loadProjects(
    WorkspaceInfo workspace,
    String type, // 'windows' or 'android'
  ) async {
    final dir = await _workspaceDir(workspace, type);
    final projects = <ManidocProject>[];

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final jsonStr = await entity.readAsString(encoding: utf8);
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          final project = ManidocProject.fromJson(json);
          // キャッシュメタデータを復元
          final meta = json['_cache'] as Map<String, dynamic>?;
          if (meta != null) {
            project.driveFileId = meta['driveFileId'] as String?;
            project.driveFolderId = meta['driveFolderId'] as String?;
            project.isReadOnly = meta['isReadOnly'] as bool? ?? false;
            project.hasProjectFolder =
                meta['hasProjectFolder'] as bool? ?? false;
            project.isDirty = meta['isDirty'] as bool? ?? false;
          }
          projects.add(project);
        } catch (_) {
          // 壊れたキャッシュはスキップ
        }
      }
    }
    return projects;
  }

  /// プロジェクトをキャッシュに保存
  Future<void> saveProject(
    WorkspaceInfo workspace,
    String type,
    ManidocProject project,
  ) async {
    final dir = await _workspaceDir(workspace, type);
    final file = File('${dir.path}/${project.id}.json');

    // プロジェクトJSONにキャッシュメタデータを付与
    final json = project.toJson();
    json['_cache'] = {
      'driveFileId': project.driveFileId,
      'driveFolderId': project.driveFolderId,
      'isReadOnly': project.isReadOnly,
      'hasProjectFolder': project.hasProjectFolder,
      'isDirty': project.isDirty,
    };

    await file.writeAsString(jsonEncode(json), encoding: utf8);
  }

  /// 複数プロジェクトを一括キャッシュ保存
  Future<void> saveAllProjects(
    WorkspaceInfo workspace,
    String type,
    List<ManidocProject> projects,
  ) async {
    final dir = await _workspaceDir(workspace, type);

    // 既存キャッシュを取得
    final existingFiles = <String>{};
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        existingFiles.add(entity.path);
      }
    }

    // 新しいプロジェクト一覧のIDセット
    final newIds = projects.map((p) => p.id).toSet();

    // 削除されたプロジェクトのキャッシュを消す
    for (final path in existingFiles) {
      final fileName = path.split('/').last.replaceAll('.json', '');
      // Windowsのパス区切り対応
      final name = fileName.split('\\').last;
      if (!newIds.contains(name)) {
        await File(path).delete();
      }
    }

    // 保存
    for (final project in projects) {
      await saveProject(workspace, type, project);
    }
  }

  /// プロジェクトをキャッシュから削除
  Future<void> deleteProject(
    WorkspaceInfo workspace,
    String type,
    String projectId,
  ) async {
    final dir = await _workspaceDir(workspace, type);
    final file = File('${dir.path}/$projectId.json');
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 未同期（dirty）のプロジェクト一覧を取得
  Future<List<ManidocProject>> getDirtyProjects(
    WorkspaceInfo workspace,
    String type,
  ) async {
    final projects = await loadProjects(workspace, type);
    return projects.where((p) => p.isDirty).toList();
  }

  /// ワークスペースのキャッシュを全削除
  Future<void> clearWorkspaceCache(WorkspaceInfo workspace) async {
    final root = await _cacheRoot();
    final safeName = workspace.name.replaceAll(RegExp(r'[^\w\-.]'), '_');
    final dir = Directory('${root.path}/$safeName');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // ── 画像キャッシュ ──

  /// 画像キャッシュディレクトリ（プロジェクト単位）
  Future<Directory> _imageDir(
    WorkspaceInfo workspace,
    String type,
    String projectId,
  ) async {
    final wsDir = await _workspaceDir(workspace, type);
    final dir = Directory('${wsDir.path}/images_$projectId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 画像をキャッシュに保存
  Future<void> saveImage(
    WorkspaceInfo workspace,
    String type,
    String projectId,
    String fileName,
    Uint8List bytes,
  ) async {
    final dir = await _imageDir(workspace, type, projectId);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
  }

  /// キャッシュから画像を読み込み
  Future<Uint8List?> loadImage(
    WorkspaceInfo workspace,
    String type,
    String projectId,
    String fileName,
  ) async {
    final dir = await _imageDir(workspace, type, projectId);
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// キャッシュに画像があるか確認
  Future<bool> hasImage(
    WorkspaceInfo workspace,
    String type,
    String projectId,
    String fileName,
  ) async {
    final dir = await _imageDir(workspace, type, projectId);
    return File('${dir.path}/$fileName').exists();
  }

  /// 最終同期日時を保存
  Future<void> saveLastSyncTime(
    WorkspaceInfo workspace,
    String type,
  ) async {
    final dir = await _workspaceDir(workspace, type);
    final file = File('${dir.path}/_last_sync.txt');
    await file.writeAsString(DateTime.now().toIso8601String());
  }

  /// 最終同期日時を取得
  Future<DateTime?> getLastSyncTime(
    WorkspaceInfo workspace,
    String type,
  ) async {
    final dir = await _workspaceDir(workspace, type);
    final file = File('${dir.path}/_last_sync.txt');
    if (!await file.exists()) return null;
    try {
      final str = await file.readAsString();
      return DateTime.parse(str.trim());
    } catch (_) {
      return null;
    }
  }
}
