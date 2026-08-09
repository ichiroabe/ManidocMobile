import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Storage Access Framework の薄いラッパ。
/// ツリーURI(利用者が選んだフォルダ)とドキュメントIDの文字列だけを扱う。
class SafService {
  static const _channel = MethodChannel('manidoc/saf');

  /// フォルダ選択画面を開く。キャンセルなら null。
  Future<SafPick?> pickTree() async {
    final r = await _channel.invokeMapMethod<String, dynamic>('pickTree');
    if (r == null) return null;
    return SafPick(
      tree: r['tree'] as String,
      doc: r['doc'] as String,
      name: r['name'] as String? ?? '',
    );
  }

  /// 権限が生きているか（利用者が設定から取り消した場合に false になる）
  Future<bool> hasPermission(String tree) async =>
      await _channel.invokeMethod<bool>('hasPermission', {'tree': tree}) ?? false;

  Future<List<SafEntry>> listChildren(String tree, {String? doc}) async {
    final r = await _channel.invokeListMethod<dynamic>(
      'listChildren',
      {'tree': tree, 'doc': doc},
    );
    if (r == null) return [];
    return r
        .cast<Map<Object?, Object?>>()
        .map((m) => SafEntry.fromMap(m))
        .toList();
  }

  Future<Uint8List?> readBytes(String tree, String doc) =>
      _channel.invokeMethod<Uint8List>('readBytes', {'tree': tree, 'doc': doc});

  Future<bool> writeBytes(String tree, String doc, Uint8List bytes) async =>
      await _channel.invokeMethod<bool>(
        'writeBytes',
        {'tree': tree, 'doc': doc, 'bytes': bytes},
      ) ??
      false;

  Future<String?> createFile(
    String tree, {
    String? parent,
    required String name,
    required String mime,
    Uint8List? bytes,
  }) =>
      _channel.invokeMethod<String>('createFile', {
        'tree': tree,
        'parent': parent,
        'name': name,
        'mime': mime,
        'bytes': bytes,
      });

  Future<String?> createDir(String tree, {String? parent, required String name}) =>
      _channel.invokeMethod<String>(
        'createDir',
        {'tree': tree, 'parent': parent, 'name': name},
      );

  Future<bool> delete(String tree, String doc) async =>
      await _channel.invokeMethod<bool>('delete', {'tree': tree, 'doc': doc}) ??
      false;
}

class SafPick {
  final String tree;
  final String doc;
  final String name;
  const SafPick({required this.tree, required this.doc, required this.name});
}

class SafEntry {
  static const dirMime = 'vnd.android.document/directory';

  final String id;
  final String name;
  final String? mime;
  final int? size;
  final DateTime? modified;

  const SafEntry({
    required this.id,
    required this.name,
    this.mime,
    this.size,
    this.modified,
  });

  bool get isDir => mime == dirMime;

  factory SafEntry.fromMap(Map<Object?, Object?> m) {
    final ms = m['modified'] as int?;
    return SafEntry(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? '',
      mime: m['mime'] as String?,
      size: (m['size'] as num?)?.toInt(),
      modified: ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }
}
