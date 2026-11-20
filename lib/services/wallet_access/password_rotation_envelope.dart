import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

/// Crash recovery for changing an unattended generated password to a password
/// chosen by its owner. The former credential is never journaled in plaintext.
class PasswordRotationEnvelope {
  static Future<String> seal(
    String newPassword,
    String oldPassword,
    String entryId,
  ) => compute(_seal, [newPassword, oldPassword, entryId]);

  static Future<String?> open(
    String newPassword,
    String envelope,
    String entryId,
  ) => compute(_open, [newPassword, envelope, entryId]);

  static Uint8List _random(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _key(String password, Uint8List salt) {
    final derivation = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, 600000, 32));
    return derivation.process(Uint8List.fromList(utf8.encode(password)));
  }

  static String _seal(List<String> args) {
    final salt = _random(16);
    final nonce = _random(12);
    final key = _key(args[0], salt);
    final plaintext = Uint8List.fromList(utf8.encode(args[1]));
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(
            KeyParameter(key),
            128,
            nonce,
            Uint8List.fromList(
              utf8.encode('gleec.password-rotation.v1:${args[2]}'),
            ),
          ),
        );
      return jsonEncode({
        'v': 1,
        'salt': base64Encode(salt),
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(cipher.process(plaintext)),
      });
    } finally {
      key.fillRange(0, key.length, 0);
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  static String? _open(List<String> args) {
    Uint8List? key;
    Uint8List? plaintext;
    try {
      final json = jsonDecode(args[1]) as Map<String, dynamic>;
      if (json['v'] != 1) return null;
      final salt = base64Decode(json['salt'] as String);
      final nonce = base64Decode(json['nonce'] as String);
      if (salt.length != 16 || nonce.length != 12) return null;
      key = _key(args[0], salt);
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            128,
            nonce,
            Uint8List.fromList(
              utf8.encode('gleec.password-rotation.v1:${args[2]}'),
            ),
          ),
        );
      plaintext = cipher.process(base64Decode(json['ciphertext'] as String));
      return utf8.decode(plaintext);
    } catch (_) {
      return null;
    } finally {
      key?.fillRange(0, key.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }
}
