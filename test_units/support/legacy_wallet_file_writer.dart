import 'dart:convert';

import 'package:encrypt/encrypt.dart';
import 'package:web_dex/model/wallet.dart';

/// What the app wrote before wallet file version 2, kept here only to make
/// fixtures for the reader that still opens such files.
Future<String> legacyEncrypt(String password, String data) async {
  final iv = IV.fromLength(16);
  final salt = IV.fromLength(16);
  final key = Key.fromUtf8(password)
      .stretch(16, iterationCount: 1000, salt: salt.bytes);
  final encrypted = Encrypter(AES(key, mode: AESMode.cbc))
      .encrypt(data, iv: iv);
  return jsonEncode({
    '0': base64.encode(encrypted.bytes),
    '1': base64.encode(iv.bytes),
    '2': base64.encode(salt.bytes),
  });
}

/// A version 1 wallet file: [config] encrypted, its [seed] encrypted inside.
Future<String> legacyWalletFile(
  String password,
  WalletConfig config,
  String seed,
) async => legacyEncrypt(
  password,
  jsonEncode(
    config.copyWith(seedPhrase: await legacyEncrypt(password, seed)).toJson(),
  ),
);
