import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// Reads data written by earlier versions of the app: version 1 wallet files
/// and the seeds of wallets kept in legacy browser storage.
///
/// Nothing writes this format any more. It is PBKDF2-HMAC-SHA1 with 1,000
/// iterations and AES-128-CBC with no MAC, and before that an MD5 key. New
/// wallet files use `WalletFileCodec`.
class EncryptionTool {
  /// Decrypts the provided [encryptedData] using AES decryption with the given [password].
  /// The method attempts to decode the [encryptedData] as a JSON-encoded string
  /// containing encrypted data and initialization vectors (IVs).
  /// Parameters:
  /// - [password] (String): The password used for decryption key derivation.
  /// - [encryptedData] (String): The JSON-encoded string containing encrypted data and IVs.
  ///
  /// Return Value:
  /// - Future<String?>: The decrypted data, or `null` if decryption fails.
  ///
  /// Example Usage:
  /// ```dart
  /// String password = 'securepassword';
  /// String encryptedData = '{"0":"...", "1":"...", "2":"..."}';
  ///
  /// String? decryptedResult = await decryptData(password, encryptedData);
  /// print(decryptedResult); // Output: Decrypted data or null if decryption fails
  /// ```
  /// unit tests [testEncryptDataTool]
  Future<String?> decryptData(String password, String encryptedData) async {
    try {
      final Map<String, dynamic> json = jsonDecode(encryptedData);
      final Uint8List data = Uint8List.fromList(base64.decode(json['0']));
      final IV iv1 = IV.fromBase64(json['1']);
      final IV iv2 = IV.fromBase64(json['2']);

      final secretKey = await _pbkdf2Key(password, iv2.bytes);

      final encrypter = Encrypter(AES(secretKey, mode: AESMode.cbc));
      final String decrypted = encrypter.decrypt(Encrypted(data), iv: iv1);

      return decrypted;
    } catch (_) {
      return _decryptLegacy(password, encryptedData);
    }
  }

  String? _decryptLegacy(String password, String encryptedData) {
    try {
      final String length32Key = md5.convert(utf8.encode(password)).toString();
      final key = Key.fromUtf8(length32Key);
      final IV iv = IV.allZerosOfLength(16);

      final Encrypter encrypter = Encrypter(AES(key));
      final Encrypted encrypted = Encrypted.fromBase64(encryptedData);
      final decryptedData = encrypter.decrypt(encrypted, iv: iv);

      return decryptedData;
    } catch (_) {
      return null;
    }
  }

  Future<Key> _pbkdf2Key(String password, Uint8List salt) async {
    return Key.fromUtf8(password).stretch(16, iterationCount: 1000, salt: salt);
  }
}
