import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../models/workspace_info.dart';
import 'drive_service.dart';
import 'local_cache_service.dart';

enum SyncStatus { idle, syncing, offline, error }

/// 保存の結果。conflict は「読み込んだ後に他所（デスクトップ版など）で
/// 同じファイルが書き換わっていた」ことを示す。上書きはしていない。
enum SaveResult { savedRemote, savedLocalOnly, conflict }

/// Drive ↔ ローカルキャッシュの同期を管理するサービス
class SyncService {
  /// キャッシュの名前空間。以前は 'windows'（読み取り専用）と 'android'
  /// （読み書き）に分けていたが、SAF ではワークスペース全体を読み書きできる
  /// ため一本化した。旧キャッシュは別名なので参照されず、そのまま無視される。
  static const workspaceType = 'workspace';

  final _driveService = DriveService();
  final _cacheService = LocalCacheService();

  /// オンラインかどうかを確認（実際のインターネット到達性をチェック）
  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    if (result.contains(ConnectivityResult.none)) return false;

    // ネットワークインターフェースはあるが実際に通信できるか確認
    try {
      final response = await HttpClient()
          .getUrl(Uri.parse('https://www.googleapis.com/generate_204'))
          .then((req) => req.close())
          .timeout(const Duration(seconds: 5));
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Pull: Driveからプロジェクト一覧を取得してキャッシュに保存
  /// 返り値はDriveから取得した最新プロジェクト一覧
  Future<List<ManidocProject>?> pullProjects(
    WorkspaceInfo workspace,
    String folderId,
    String type,
  ) async {
    if (!await isOnline()) return null;

    try {
      const readOnly = false;
      final files = await _driveService.listProjectFiles(folderId);
      final projects = <ManidocProject>[];

      for (final info in files) {
        final project = await _driveService.readProject(
          info.file,
          readOnly: readOnly,
          folderId: info.parentFolderId,
          hasProjectFolder: info.hasProjectFolder,
        );
        if (project != null) projects.add(project);
      }

      // dirtyなローカル変更を保持する
      final dirtyProjects =
          await _cacheService.getDirtyProjects(workspace, type);
      final dirtyMap = {for (final p in dirtyProjects) p.id: p};

      for (var i = 0; i < projects.length; i++) {
        final local = dirtyMap[projects[i].id];
        if (local != null) {
          // ローカルの変更が新しい場合はローカルを優先
          if (local.lastModifiedAt.isAfter(projects[i].lastModifiedAt)) {
            // Driveメタデータは最新を使い、中身はローカルを使う
            local.driveFileId = projects[i].driveFileId;
            local.driveFolderId = projects[i].driveFolderId;
            local.hasProjectFolder = projects[i].hasProjectFolder;
            projects[i] = local;
          }
        }
      }

      // Driveから0件取得の場合、キャッシュを保護（通信不安定の可能性）
      if (projects.isEmpty) {
        final cached = await _cacheService.loadProjects(workspace, type);
        return cached.isNotEmpty ? cached : projects;
      }

      // キャッシュに保存
      await _cacheService.saveAllProjects(workspace, type, projects);

      // 画像をキャッシュ
      for (final project in projects) {
        await _cacheProjectImages(workspace, type, project);
      }

      await _cacheService.saveLastSyncTime(workspace, type);

      return projects;
    } catch (_) {
      return null;
    }
  }

  /// Push: dirtyなプロジェクトをDriveにアップロード
  Future<int> pushDirtyProjects(
    WorkspaceInfo workspace,
    String type,
  ) async {
    if (!await isOnline()) return 0;

    final dirtyProjects =
        await _cacheService.getDirtyProjects(workspace, type);
    var pushed = 0;

    for (final project in dirtyProjects) {
      // 相手側が新しければ触らない。dirty のまま残るので編集内容は消えない。
      if (await _isConflicting(project)) continue;
      final ok = await _driveService.updateProject(project);
      if (ok) {
        project.isDirty = false;
        await _cacheService.saveProject(workspace, type, project);
        pushed++;
      }
    }

    if (pushed > 0) {
      await _cacheService.saveLastSyncTime(workspace, type);
    }
    return pushed;
  }

  /// プロジェクトをローカルに保存（＋オンラインならワークスペースにも書き戻す）
  ///
  /// 書き戻す前に、読み込んだ時点から相手側が変わっていないかを確認する。
  /// 変わっていたら上書きせず conflict を返す。ローカルには保存済みなので
  /// 編集内容が失われることはない。
  Future<SaveResult> saveProject(
    WorkspaceInfo workspace,
    String type,
    ManidocProject project,
  ) async {
    // まずローカルキャッシュに保存（即座）
    project.isDirty = true;
    project.lastModifiedAt = DateTime.now();
    await _cacheService.saveProject(workspace, type, project);

    if (!await isOnline()) return SaveResult.savedLocalOnly;

    if (await _isConflicting(project)) return SaveResult.conflict;

    final ok = await _driveService.updateProject(project);
    if (!ok) return SaveResult.savedLocalOnly;

    project.isDirty = false;
    await _cacheService.saveProject(workspace, type, project);
    return SaveResult.savedRemote;
  }

  /// 読み込んだ時点の更新時刻と現物を突き合わせる。
  /// 基準が無い（新規作成直後など）場合は衝突とみなさない。
  Future<bool> _isConflicting(ManidocProject project) async {
    final base = project.remoteModifiedAt;
    final fileId = project.driveFileId;
    if (base == null || fileId == null) return false;
    final current = await _driveService.remoteModifiedAt(fileId);
    if (current == null) return false;
    return current.isAfter(base);
  }

  /// プロジェクト内の全画像をキャッシュ
  Future<void> _cacheProjectImages(
    WorkspaceInfo workspace,
    String type,
    ManidocProject project,
  ) async {
    final imagePaths = <String>[];
    _collectImagePaths(project.rootNodes, imagePaths);
    if (imagePaths.isEmpty) return;

    for (final path in imagePaths) {
      final fileName = path.substring('images/'.length);
      // 既にキャッシュ済みならスキップ
      if (await _cacheService.hasImage(
          workspace, type, project.id, fileName)) {
        continue;
      }
      // Driveからダウンロードしてキャッシュ
      final bytes = await _downloadImage(project, path);
      if (bytes != null) {
        await _cacheService.saveImage(
            workspace, type, project.id, fileName, bytes);
      }
    }
  }

  /// ノードツリーからimages/で始まるimagePathを収集
  void _collectImagePaths(List<ManidocNode> nodes, List<String> paths) {
    for (final node in nodes) {
      if (node.imagePath.startsWith('images/')) {
        paths.add(node.imagePath);
      }
      _collectImagePaths(node.children, paths);
    }
  }

  /// Driveから画像をダウンロード
  Future<Uint8List?> _downloadImage(
    ManidocProject project,
    String imagePath,
  ) async {
    try {
      final folderId = project.driveFolderId;
      if (folderId == null) return null;

      String projectFolderId = folderId;
      if (!project.hasProjectFolder) {
        final sub = await _driveService.getOrCreateSubFolder(
            project.id, parentId: folderId);
        if (sub != null) projectFolderId = sub;
      }

      final imagesFolderId = await _driveService.getOrCreateSubFolder(
          'images', parentId: projectFolderId);
      if (imagesFolderId == null) return null;

      final fileName = imagePath.substring('images/'.length);
      final fileId =
          await _driveService.findFileIdByName(imagesFolderId, fileName);
      if (fileId == null) return null;

      final bytes = await _driveService.downloadFileBytes(fileId);
      if (bytes == null) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// キャッシュから画像を読み込み
  Future<Uint8List?> loadCachedImage(
    WorkspaceInfo workspace,
    String type,
    String projectId,
    String fileName,
  ) async {
    return _cacheService.loadImage(workspace, type, projectId, fileName);
  }

  /// 画像をキャッシュに保存（エディタから新規アップロード時にも使用）
  Future<void> cacheImage(
    WorkspaceInfo workspace,
    String type,
    String projectId,
    String fileName,
    Uint8List bytes,
  ) async {
    await _cacheService.saveImage(workspace, type, projectId, fileName, bytes);
  }

  /// キャッシュからプロジェクト一覧を読み込み（オフライン用）
  Future<List<ManidocProject>> loadFromCache(
    WorkspaceInfo workspace,
    String type,
  ) async {
    return _cacheService.loadProjects(workspace, type);
  }

  /// 最終同期日時を取得
  Future<DateTime?> getLastSyncTime(
    WorkspaceInfo workspace,
    String type,
  ) async {
    return _cacheService.getLastSyncTime(workspace, type);
  }
}
