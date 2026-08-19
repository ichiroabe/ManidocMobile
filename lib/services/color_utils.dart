import 'package:flutter/material.dart';

/// 色と '#RRGGBB' 文字列の相互変換ユーティリティ。
/// デスクトップ版(openManidoc)の color_utils.dart と互換。
/// プロジェクトタイル色(cardForeColor / cardBackColor)から使う。

/// Color → '#rrggbb'(小文字、アルファは捨てる)
String hexFromColor(Color c) =>
    '#${((c.r * 255).round() << 16 | (c.g * 255).round() << 8 | (c.b * 255).round()).toRadixString(16).padLeft(6, '0')}';

/// '#rrggbb' / 'rrggbb' / '#aarrggbb' → Color。解釈できなければ null。
Color? colorFromHex(String value) {
  var s = value.replaceAll('#', '').trim();
  if (s.length == 8) {
    final n = int.tryParse(s, radix: 16);
    return n == null ? null : Color(n);
  }
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  return Color(0xFF000000 | n);
}

/// 2色のコントラスト比(WCAG)。1(同色)〜21(黒と白)。
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 本文として読める最低ライン(WCAG AA)
const double kReadableContrast = 4.5;

/// 背景色の上で読みやすい文字色(黒 or 白)を、コントラスト比の高い方で返す。
Color contrastForegroundFor(Color background) =>
    contrastRatio(Colors.white, background) >=
            contrastRatio(Colors.black, background)
        ? Colors.white
        : Colors.black;
