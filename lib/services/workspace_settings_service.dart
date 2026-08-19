import 'dart:convert';

import '../models/tag_definition.dart';
import '../models/workspace_info.dart';
import 'drive_service.dart';
import 'local_storage_service.dart';

/// ワークスペース直下の workspace.settings.json を読み書きするサービス。
/// デスクトップ版(openManidoc)と同じファイル・同じ tags[] 構造を使う。
/// tags[] の各要素に color('#rrggbb') を足してタグ色を保存する。
class WorkspaceSettingsService {
  final _drive = DriveService();
  final _local = LocalStorageService();

  static const _fileName = 'workspace.settings.json';
  static const _encoder = JsonEncoder.withIndent('  ');

  Future<String?> _read(WorkspaceInfo ws, bool isWindows) {
    if (isWindows) {
      final path = ws.localPath;
      if (path == null) return Future.value(null);
      return _local.readWorkspaceText(path, _fileName);
    }
    return _drive.readWorkspaceText(ws.windowsFolderId, _fileName);
  }

  Future<bool> _write(WorkspaceInfo ws, bool isWindows, String content) {
    if (isWindows) {
      final path = ws.localPath;
      if (path == null) return Future.value(false);
      return _local.writeWorkspaceText(path, _fileName, content);
    }
    return _drive.writeWorkspaceText(ws.windowsFolderId, _fileName, content);
  }

  /// tags[] を読む（ファイルが無い・壊れている場合は空リスト）。
  Future<List<TagDefinition>> loadTags(
      WorkspaceInfo ws, bool isWindows) async {
    final text = await _read(ws, isWindows);
    if (text == null) return [];
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return [];
      final tags = json['tags'] as List<dynamic>? ?? [];
      return tags
          .whereType<Map<String, dynamic>>()
          .map(TagDefinition.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// tags[] を保存する（settings.json の他のキーは保持する）。
  Future<void> saveTags(
      WorkspaceInfo ws, bool isWindows, List<TagDefinition> tags) async {
    Map<String, dynamic> json = {};
    final text = await _read(ws, isWindows);
    if (text != null) {
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) json = parsed;
      } catch (_) {}
    }
    json['tags'] = tags.map((t) => t.toJson()).toList();
    await _write(ws, isWindows, _encoder.convert(json));
  }
}
