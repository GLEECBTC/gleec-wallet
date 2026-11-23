import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../wallet_access_types.dart';

/// A wallet credential encrypted under a key that only one passkey's PRF
/// output for [salt] can reproduce. Every field below is authenticated: none
/// can be swapped between records, wallets or revisions without failing
/// decryption.
class PasskeyEnvelope {
  const PasskeyEnvelope._({
    required this.key,
    required this.revision,
    required this.rpId,
    required this.credentialId,
    required this.userHandle,
    required this.enrollmentId,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
  });

  static const kind = 'gleec.wallet.passkey-envelope';
  static const version = 1;
  static const saltLength = 32;
  static const prfLength = 32;
  static const _nonceLength = 12;
  static const _tagLength = 16;
  static const _maxCredentialIdLength = 1023;
  static const _maxUserHandleLength = 64;
  static const _maxValueBytes = 16384;
  static final _info = utf8.encode('$kind.v$version');

  final String key;
  final int revision;
  final String rpId;
  final Uint8List credentialId;
  final Uint8List? userHandle;
  final String enrollmentId;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;

  static Uint8List randomBytes(int length, [Random? random]) {
    final source = random ?? Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => source.nextInt(256)),
    );
  }

  /// Encrypts [value] under [aesKey] from [deriveKey]. The caller keeps
  /// ownership of the key and wipes it.
  static PasskeyEnvelope seal({
    required String key,
    required int revision,
    required String rpId,
    required Uint8List credentialId,
    required Uint8List? userHandle,
    required String enrollmentId,
    required Uint8List salt,
    required Uint8List aesKey,
    required String value,
    Random? random,
  }) {
    final header = PasskeyEnvelope._(
      key: key,
      revision: revision,
      rpId: rpId,
      credentialId: Uint8List.fromList(credentialId),
      userHandle: userHandle == null ? null : Uint8List.fromList(userHandle),
      enrollmentId: enrollmentId,
      salt: Uint8List.fromList(salt),
      nonce: randomBytes(_nonceLength, random),
      ciphertext: Uint8List(0),
    );
    header._checkHeader();
    return header._encrypt(value, aesKey);
  }

  /// The same binding and key under the next revision, for a password change.
  PasskeyEnvelope reseal(String value, Uint8List aesKey, {Random? random}) =>
      PasskeyEnvelope._(
        key: key,
        revision: revision + 1,
        rpId: rpId,
        credentialId: credentialId,
        userHandle: userHandle,
        enrollmentId: enrollmentId,
        salt: salt,
        nonce: randomBytes(_nonceLength, random),
        ciphertext: Uint8List(0),
      )._encrypt(value, aesKey);

  PasskeyEnvelope _encrypt(String value, Uint8List aesKey) {
    final plaintext = Uint8List.fromList(utf8.encode(value));
    try {
      if (plaintext.isEmpty || plaintext.length > _maxValueBytes) {
        throw const WalletAccessException(WalletAccessFailure.invalidResponse);
      }
      return _withCiphertext(
        _cipher(true, aesKey, nonce, _aad).process(plaintext),
      );
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  /// Authenticates and decrypts with a key from [deriveKey]. Any mismatch,
  /// including a different passkey or salt, is [WalletAccessFailure.envelopeCorrupt].
  String open(Uint8List aesKey) {
    Uint8List? plaintext;
    try {
      plaintext = _cipher(false, aesKey, nonce, _aad).process(ciphertext);
      return utf8.decode(plaintext);
    } on Object {
      throw const WalletAccessException(WalletAccessFailure.envelopeCorrupt);
    } finally {
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  /// HKDF-SHA256 with an empty salt, as RFC 5869 allows. The PRF output is
  /// already uniformly random; the expansion separates this use of it from
  /// any other the same passkey and salt could be put to.
  static Uint8List deriveKey(Uint8List prf) {
    if (prf.length != prfLength) {
      throw const WalletAccessException(WalletAccessFailure.prfUnavailable);
    }
    final extract = HMac(SHA256Digest(), 64)..init(KeyParameter(Uint8List(32)));
    final prk = extract.process(prf);
    try {
      final expand = HMac(SHA256Digest(), 64)..init(KeyParameter(prk));
      return expand.process(Uint8List.fromList([..._info, 1]));
    } finally {
      prk.fillRange(0, prk.length, 0);
    }
  }

  static GCMBlockCipher _cipher(
    bool encrypt,
    Uint8List aesKey,
    Uint8List nonce,
    Uint8List aad,
  ) {
    if (aesKey.length != 32) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    return GCMBlockCipher(AESEngine())..init(
      encrypt,
      AEADParameters(KeyParameter(aesKey), _tagLength * 8, nonce, aad),
    );
  }

  PasskeyEnvelope _withCiphertext(Uint8List ciphertext) => PasskeyEnvelope._(
    key: key,
    revision: revision,
    rpId: rpId,
    credentialId: credentialId,
    userHandle: userHandle,
    enrollmentId: enrollmentId,
    salt: salt,
    nonce: nonce,
    ciphertext: ciphertext,
  );

  Uint8List get _aad => Uint8List.fromList(
    utf8.encode(
      jsonEncode([
        kind,
        version,
        key,
        revision,
        rpId,
        _encode(credentialId),
        userHandle == null ? '' : _encode(userHandle!),
        enrollmentId,
        _encode(salt),
      ]),
    ),
  );

  void _checkHeader() {
    if (key.isEmpty ||
        key.length > 512 ||
        revision < 1 ||
        rpId.isEmpty ||
        credentialId.isEmpty ||
        credentialId.length > _maxCredentialIdLength ||
        (userHandle != null &&
            (userHandle!.isEmpty ||
                userHandle!.length > _maxUserHandleLength)) ||
        !RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(enrollmentId) ||
        salt.length != saltLength ||
        nonce.length != _nonceLength) {
      throw const WalletAccessException(WalletAccessFailure.envelopeCorrupt);
    }
  }

  String encode() => jsonEncode({
    'kind': kind,
    'v': version,
    'key': key,
    'revision': revision,
    'rpId': rpId,
    'credentialId': _encode(credentialId),
    'userHandle': userHandle == null ? null : _encode(userHandle!),
    'enrollmentId': enrollmentId,
    'salt': _encode(salt),
    'nonce': _encode(nonce),
    'ciphertext': _encode(ciphertext),
  });

  /// Rejects anything but a well-formed envelope for exactly [expectedKey]
  /// and [expectedRpId]. Never returns a partially trusted record.
  static PasskeyEnvelope decode(
    String raw, {
    required String expectedKey,
    required String expectedRpId,
  }) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> ||
          json['kind'] != kind ||
          json['v'] != version ||
          json['key'] != expectedKey ||
          json['rpId'] != expectedRpId ||
          json['revision'] is! int ||
          json['enrollmentId'] is! String) {
        throw const FormatException();
      }
      final userHandle = json['userHandle'];
      final envelope = PasskeyEnvelope._(
        key: expectedKey,
        revision: json['revision'] as int,
        rpId: expectedRpId,
        credentialId: _decode(json['credentialId']),
        userHandle: userHandle == null ? null : _decode(userHandle),
        enrollmentId: json['enrollmentId'] as String,
        salt: _decode(json['salt']),
        nonce: _decode(json['nonce']),
        ciphertext: _decode(json['ciphertext']),
      ).._checkHeader();
      if (envelope.ciphertext.length <= _tagLength ||
          envelope.ciphertext.length > _maxValueBytes + _tagLength) {
        throw const FormatException();
      }
      return envelope;
    } on Object {
      throw const WalletAccessException(WalletAccessFailure.envelopeCorrupt);
    }
  }

  static String _encode(Uint8List bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List _decode(Object? value) {
    if (value is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
      throw const FormatException();
    }
    return base64Url.decode(base64Url.normalize(value));
  }
}

/// Byte comparison that does not stop at the first difference.
bool passkeyBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}
