import 'dart:typed_data';
import '../models/manidoc_node.dart';
import '../models/manidoc_project.dart';
import '../models/workspace_info.dart';
import 'drive_service.dart';
import 'local_cache_service.dart';

enum SyncStatus { idle, syncing, error }

/// 読み込みのどの段階にいるか。無反応に見えないよう UI にそのまま出す。
enum SyncPhase { scanning, reading, images }

/// 進み具合。total が 0 のときは件数不明（走査中）。
class SyncProgress {
  final SyncPhase phase;
  final int done;
  final int total;

  const SyncProgress(this.phase, {this.done = 0, this.total = 0});
}

/// 保存の結果。conflict は「読み込んだ後に他所（デスクトップ版など）で
/// 同じファイルが書き換わっていた」ことを示す。上書きはしていない。
enum SaveResult { savedRemote, savedLocalOnly, conflict }

/// ワークスペース ↔ ローカルキャッシュの同期を管理するサービス
///
/// ワークスペースへのアクセスは SAF 経由なので、インターネット接続の有無は
/// 判断材料にしない（端末内フォルダなら通信は不要、Google ドライブなら
/// プロバイダ側が面倒を見る）。以前はここで疎通確認をしてから動いていたが、
/// 通信できないだけで読み込みが始まらず、原因も出ないままになっていた。
class SyncService {
  /// キャッシュの名前空間。以前は 'windows'（読み取り専用）と 'android'
  /// （読み書き）に分けていたが、SAF ではワークスペース全体を読み書きできる
  /// ため一本化した。旧キャッシュは別名なので参照されず、そのまま無視される。
  static const workspaceType = 'workspace';

  final _driveService = DriveService();
  final _cacheService = LocalCacheService();

  /// Pull: ワークスペースからプロジェクト一覧を取得してキャッシュに保存
  ///
  /// 画像は含めない（数が多いと数分かかるため、一覧を出した後に
  /// [cacheProjectImages] で別途取り込む）。
  /// 読めなかった場合は例外を投げる。呼び出し側で理由を出すこと。
  Future<List<ManidocProject>> pullProjects(
    WorkspaceInfo workspace,
    String folderId,
    String type, {
    void Function(SyncProgress)? onProgress,
  }) async {
    onProgress?.call(const SyncProgress(SyncPhase.scanning));
    final files = await _driveService.listProjectFiles(folderId);

    // 0件のときはキャッシュを保護（フォルダの選び間違いで消さない）
    if (files.isEmpty) {
      final cached = await _cacheService.loadProjects(workspace, type);
      return cached;
    }

    final projects = <ManidocProject>[];
    for (var i = 0; i < files.length; i++) {
      onProgress?.call(
        SyncProgress(SyncPhase.reading, done: i, total: files.length),
      );
      final info = files[i];
      final project = await _driveService.readProject(
        info.file,
        readOnly: false,
        folderId: info.parentFolderId,
        hasProjectFolder: info.hasProjectFolder,
      );
      if (project != null) projects.add(project);
    }
    onProgress?.call(
      SyncProgress(SyncPhase.reading, done: files.length, total: files.length),
    );

    // dirtyなローカル変更を保持する
    final dirtyProjects = await _cacheService.getDirtyProjects(workspace, type);
    final dirtyMap = {for (final p in dirtyProjects) p.id: p};

    for (var i = 0; i < projects.length; i++) {
      final local = dirtyMap[projects[i].id];
      if (local != null) {
        // ローカルの変更が新しい場合はローカルを優先
        if (local.lastModifiedAt.isAfter(projects[i].lastModifiedAt)) {
          // ワークスペース側のメタデータは最新を使い、中身はローカルを使う
          local.driveFileId = projects[i].driveFileId;
          local.driveFolderId = projects[i].driveFolderId;
          local.hasProjectFolder = projects[i].hasProjectFolder;
          projects[i] = local;
        }
      }
    }

    await _cacheService.saveAllProjects(workspace, type, projects);
    await _cacheService.saveLastSyncTime(workspace, type);

    return projects;
  }

  /// Push: dirtyなプロジェクトをワークスペースに書き戻す
  Future<int> pushDirtyProjects(
    WorkspaceInfo workspace,
    String type,
  ) async {
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

  /// プロジェクトをローカルに保存（＋ワークスペースにも書き戻す）
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

  /// プロジェクトの画像をまとめてキャッシュする。
  ///
  /// 一覧の表示より後に回す想定。Google ドライブを選んでいると1ファイルごとに
  /// 通信が走るので、フォルダの引き当ては1プロジェクトにつき1回だけにしてある。
  Future<void> cacheProjectImages(
    WorkspaceInfo workspace,
    String type,
    List<ManidocProject> projects, {
    void Function(SyncProgress)? onProgress,
  }) async {
    final targets = <ManidocProject>[];
    for (final project in projects) {
      final paths = <String>[];
      _collectImagePaths(project.rootNodes, paths);
      if (paths.isNotEmpty) targets.add(project);
    }
    if (targets.isEmpty) return;

    for (var i = 0; i < targets.length; i++) {
      onProgress?.call(
        SyncProgress(SyncPhase.images, done: i, total: targets.length),
      );
      await _cacheOneProjectImages(workspace, type, targets[i]);
    }
    onProgress?.call(
      SyncProgress(SyncPhase.images,
          done: targets.length, total: targets.length),
    );
  }

  Future<void> _cacheOneProjectImages(
    WorkspaceInfo workspace,
    String type,
    ManidocProject project,
  ) async {
    final imagePaths = <String>[];
    _collectImagePaths(project.rootNodes, imagePaths);

    // キャッシュ済みを除いてから、初めてワークスペースを触る
    final wanted = <String>[];
    for (final path in imagePaths) {
      final fileName = path.substring('images/'.length);
      if (await _cacheService.hasImage(workspace, type, project.id, fileName)) {
        continue;
      }
      if (!wanted.contains(fileName)) wanted.add(fileName);
    }
    if (wanted.isEmpty) return;

    final imagesFolderId = await _imagesFolderId(project);
    if (imagesFolderId == null) return;

    // images/ の一覧は1回だけ引いて名前→IDの表にする
    final entries = await _driveService.listFolder(imagesFolderId);
    final idByName = {for (final e in entries) e.name: e.id};

    for (final fileName in wanted) {
      final fileId = idByName[fileName];
      if (fileId == null) continue;
      final bytes = await _driveService.downloadFileBytes(fileId);
      if (bytes == null) continue;
      await _cacheService.saveImage(
          workspace, type, project.id, fileName, Uint8List.fromList(bytes));
    }
  }

  /// プロジェクトの images/ フォルダのID。無ければ作る。
  Future<String?> _imagesFolderId(ManidocProject project) async {
    try {
      final folderId = project.driveFolderId;
      if (folderId == null) return null;

      var projectFolderId = folderId;
      if (!project.hasProjectFolder) {
        final sub = await _driveService.getOrCreateSubFolder(project.id,
            parentId: folderId);
        if (sub != null) projectFolderId = sub;
      }
      return _driveService.getOrCreateSubFolder('images',
          parentId: projectFolderId);
    } catch (_) {
      return null;
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
