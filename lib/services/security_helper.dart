import 'dart:convert';
import 'package:encrypt/encrypt.dart';

/// Manidoc本体 (C# SecurityHelper) と互換のAES-256-CBC暗号化
class SecurityHelper {
  static final _key = Key.fromUtf8('Manidoc_Secret_Key_2026_VibeLogi'); // 32 chars = AES-256
  static final _iv = IV.fromUtf8('Manidoc_Init_Vec'); // 16 chars

  static String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    final encrypter = Encrypter(AES(_key, mode: AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: _iv);
    return encrypted.base64;
  }

  static String decrypt(String cipherText) {
    if (cipherText.isEmpty) return '';
    try {
      final encrypter = Encrypter(AES(_key, mode: AESMode.cbc));
      return encrypter.decrypt64(cipherText, iv: _iv);
    } catch (_) {
      return '';
    }
  }
}
