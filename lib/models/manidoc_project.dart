import 'dart:ui' show Color;
import 'package:uuid/uuid.dart';
import 'manidoc_node.dart';

class ManidocProject {
  /// このクラスが明示的に扱うJSONキー。これ以外は [extra] へ退避して往復させる。
  static const _knownKeys = {
    'id',
    'name',
    'createdAt',
    'lastModifiedAt',
    'description',
    'lastSelectedNodeId',
    'sortOrder',
    'themeCssFileName',
    'tag',
    'rootNodes',
  };

  String id;
  String name;
  DateTime createdAt;
  DateTime lastModifiedAt;
  String description;
  String lastSelectedNodeId;
  int sortOrder;
  String themeCssFileName;
  String tag;
  List<ManidocNode> rootNodes;

  /// デスクトップ版が付ける未知フィールド(タイル色 cardForeColor / cardBackColor など)。
  /// このアプリでは使わないが、保存時に落とさないようそのまま書き戻す。
  final Map<String, dynamic> extra;

  // Drive メタデータ（JSONに保存しない）
  String? driveFileId;
  String? driveFolderId;   // 新形式: UUIDプロジェクトフォルダID / 旧形式: ワークスペースフォルダID
  bool isReadOnly;
  bool hasProjectFolder;   // true=新形式(driveFolderIdがプロジェクトフォルダ) / false=旧形式

  // ローカルメタデータ（Windows用・JSONに保存しない）
  String? localFilePath;

  // オフラインキャッシュ用（JSONに保存しない）
  bool isDirty;

  /// 読み込んだ時点でのワークスペース側ファイルの更新時刻（JSONに保存しない）。
  /// 上書き保存の直前にこれと現物を比べ、他所で書き換わっていたら衝突とみなす。
  DateTime? remoteModifiedAt;

  ManidocProject({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    this.description = '',
    this.lastSelectedNodeId = '',
    this.sortOrder = 0,
    this.themeCssFileName = '',
    this.tag = '',
    List<ManidocNode>? rootNodes,
    Map<String, dynamic>? extra,
    this.driveFileId,
    this.driveFolderId,
    this.isReadOnly = false,
    this.hasProjectFolder = false,
    this.isDirty = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastModifiedAt = lastModifiedAt ?? DateTime.now(),
        rootNodes = rootNodes ?? [],
        extra = extra ?? {};

  factory ManidocProject.create(String name) => ManidocProject(
        id: const Uuid().v4(),
        name: name,
      );

  factory ManidocProject.fromJson(Map<String, dynamic> json) => ManidocProject(
        id: json['id'] as String? ?? const Uuid().v4(),
        name: json['name'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        lastModifiedAt: json['lastModifiedAt'] != null
            ? DateTime.tryParse(json['lastModifiedAt'] as String) ??
                DateTime.now()
            : DateTime.now(),
        description: json['description'] as String? ?? '',
        lastSelectedNodeId: json['lastSelectedNodeId'] as String? ?? '',
        sortOrder: json['sortOrder'] as int? ?? 0,
        themeCssFileName: json['themeCssFileName'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        rootNodes: (json['rootNodes'] as List<dynamic>?)
                ?.map((e) => ManidocNode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        extra: Map<String, dynamic>.from(json)
          ..removeWhere((key, _) => _knownKeys.contains(key)),
      );

  /// デスクトップ版が付けるタイルの背景色（cardBackColor）。無ければ null。
  Color? get cardBackColor => _parseColor(extra['cardBackColor']);

  /// デスクトップ版が付けるタイルの文字色（cardForeColor）。無ければ null。
  Color? get cardForeColor => _parseColor(extra['cardForeColor']);

  /// タイル色の '#rrggbb' 文字列。未設定なら空文字。編集ダイアログから読み書きする。
  /// デスクトップ版と同じく extra 経由で保存し、空文字ならキーごと落とす
  /// （本家 Manidoc が読むJSONを不要に汚さない）。
  String get cardBackColorHex => (extra['cardBackColor'] as String?) ?? '';
  set cardBackColorHex(String hex) => _setColorHex('cardBackColor', hex);

  String get cardForeColorHex => (extra['cardForeColor'] as String?) ?? '';
  set cardForeColorHex(String hex) => _setColorHex('cardForeColor', hex);

  void _setColorHex(String key, String hex) {
    final v = hex.trim();
    if (v.isEmpty) {
      extra.remove(key);
    } else {
      extra[key] = v;
    }
  }

  /// "#rrggbb" / "#aarrggbb"（先頭の # は任意）を [Color] に変換する。
  /// 形式が想定外なら null を返して既定色にフォールバックさせる。
  static Color? _parseColor(dynamic value) {
    if (value is! String) return null;
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'ff$hex'; // アルファ無しは不透明扱い
    if (hex.length != 8) return null;
    final argb = int.tryParse(hex, radix: 16);
    if (argb == null) return null;
    return Color(argb);
  }

  /// プロジェクトJSONかどうか(rootNodes を持つか)。
  /// ワークスペース直下には project.colors.json のような別用途のJSONも置かれるため、
  /// これで弾かないと名前なし・0ノードのプロジェクトとして一覧に出てしまう。
  static bool looksLikeProject(Map<String, dynamic> json) =>
      json.containsKey('rootNodes');

  // 未知フィールドを先に展開し、既知フィールドで上書きする
  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'lastModifiedAt': lastModifiedAt.toIso8601String(),
        'description': description,
        'lastSelectedNodeId': lastSelectedNodeId,
        'sortOrder': sortOrder,
        'themeCssFileName': themeCssFileName,
        'tag': tag,
        'rootNodes': rootNodes.map((e) => e.toJson()).toList(),
      };
}
