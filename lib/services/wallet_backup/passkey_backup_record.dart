import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_envelope.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration_types.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_config.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

part 'passkey_backup_record_crypto.dart';

/// A wallet sealed to one backup passkey. Only that passkey's PRF output
/// for [prfSalt] opens it. The rest is a public header that names no
/// wallet, and all of it is authenticated: no field can move between
/// records without failing to open.
///
/// The PRF output derives a key-encryption key that wraps a random data key,
/// and the data key seals the secret. GCM does not bind a ciphertext to one
/// key, so a commitment to the data key is checked before it is used.
final class PasskeyBackupRecord {
  const PasskeyBackupRecord._({
    required this.id,
    required this.rpId,
    required this.created,
    required this._credentialId,
    required this._userHandle,
    required this.backupEligible,
    required this.backupState,
    required this.aaguid,
    required this.transports,
    required this._wrap,
    required this._commit,
    required this._seed,
  });

  static const kind = 'gleec.wallet.passkey-backup';
  static const version = 1;
  static const maxLength = 16384;
  static const userHandleLength = 32;

  /// Fixed, so a restore needs nothing from the record before its one
  /// discoverable prompt. A copy: nobody can change it for the next caller.
  static Uint8List get prfSalt => Uint8List.fromList(_prfSalt);

  /// Base64url of 16 random bytes; also the per-record HKDF salt.
  final String id;
  final String rpId;

  /// UTC, to the second.
  final DateTime created;
  final Uint8List _credentialId;
  final Uint8List _userHandle;
  final bool backupEligible;
  final bool backupState;

  /// A naming hint, never a reason to trust anything.
  final String? aaguid;
  final List<String> transports;

  // The data key sealed under the PRF's key and the secret under the data
  // key, each as nonce, ciphertext and tag; then the data key's commitment.
  final Uint8List _wrap;
  final Uint8List _seed;
  final Uint8List _commit;

  Uint8List get credentialId => Uint8List.fromList(_credentialId);
  Uint8List get userHandle => Uint8List.fromList(_userHandle);
  String get storageName => 'gleec-passkey-backup-$id.json';

  /// Seals [secret] under [prf], the PRF output of [passkey] for [prfSalt].
  /// The caller keeps ownership of [prf] and wipes it.
  static PasskeyBackupRecord seal({
    required String rpId,
    required RegisteredPasskey passkey,
    required Uint8List userHandle,
    required Uint8List prf,
    required WalletTransferSecret secret,
    required DateTime created,
    Random? random,
  }) {
    _checkPrf(prf);
    final utc = created.toUtc();
    final header = PasskeyBackupRecord._(
      id: _encode(PasskeyEnvelope.randomBytes(_idLength, random)),
      rpId: rpId,
      created: DateTime.utc(
        utc.year,
        utc.month,
        utc.day,
        utc.hour,
        utc.minute,
        utc.second,
      ),
      credentialId: Uint8List.fromList(passkey.credentialId),
      userHandle: Uint8List.fromList(userHandle),
      backupEligible: passkey.backupEligible,
      backupState: passkey.backupState,
      aaguid: passkey.aaguid,
      transports: List.unmodifiable(passkey.transports),
      wrap: Uint8List(0),
      commit: Uint8List(0),
      seed: Uint8List(0),
    );
    // Only a caller that skipped checkPasskeyRegistration gets here.
    if (!header._validHeader) throw ArgumentError('Invalid backup header');
    final aad = header._aad;
    final dek = PasskeyEnvelope.randomBytes(_keyLength, random);
    final kek = _deriveKek(prf, header.id);
    final plaintext = secret.encode();
    try {
      final record = header._withCiphertext(
        wrap: _seal(kek, aad, dek, random),
        commit: _commitment(dek, header.id),
        seed: _seal(dek, aad, plaintext, random),
      );
      if (record.encode().length > maxLength) {
        throw ArgumentError('Backup record too large');
      }
      return record;
    } finally {
      _wipe(dek);
      _wipe(kek);
      _wipe(plaintext);
    }
  }

  /// Throws [PasskeyBackupFailure.wrongPasskey] when anything fails to
  /// authenticate, whichever passkey or field is to blame, and
  /// [PasskeyBackupFailure.damaged] when what decrypts is not a wallet.
  /// The caller keeps ownership of [prf]; nothing secret stays here.
  WalletTransferSecret open(Uint8List prf) {
    _checkPrf(prf);
    final aad = _aad;
    final kek = _deriveKek(prf, id);
    Uint8List? dek;
    Uint8List? plaintext;
    try {
      dek = _open(kek, _wrap, aad);
      if (dek == null || !passkeyBytesEqual(_commitment(dek, id), _commit)) {
        throw const PasskeyBackupException(PasskeyBackupFailure.wrongPasskey);
      }
      plaintext = _open(dek, _seed, aad);
      if (plaintext == null) {
        throw const PasskeyBackupException(PasskeyBackupFailure.wrongPasskey);
      }
      try {
        return WalletTransferSecret.decode(plaintext);
      } on Object {
        throw const PasskeyBackupException(PasskeyBackupFailure.damaged);
      }
    } finally {
      _wipe(kek);
      if (dek != null) _wipe(dek);
      if (plaintext != null) _wipe(plaintext);
    }
  }

  String encode() => jsonEncode({
    'kind': kind,
    'v': version,
    'id': id,
    'rpId': rpId,
    'created': _iso(created),
    'credentialId': _encode(_credentialId),
    'userHandle': _encode(_userHandle),
    'backupEligible': backupEligible,
    'backupState': backupState,
    'aaguid': aaguid,
    'transports': transports,
    'wrap': _encode(_wrap),
    'commit': _encode(_commit),
    'seed': _encode(_seed),
  });

  /// Accepts only the exact form [encode] writes, give or take surrounding
  /// whitespace. A record from a newer app is [PasskeyBackupFailure.newerVersion]
  /// and one for another host [PasskeyBackupFailure.otherRelyingParty];
  /// anything else malformed is [PasskeyBackupFailure.damaged].
  static PasskeyBackupRecord decode(
    String raw, {
    required String expectedRpId,
  }) {
    const damaged = PasskeyBackupException(PasskeyBackupFailure.damaged);
    if (raw.length > maxLength) throw damaged;
    final text = raw.trim();
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw damaged;
    }
    if (json is! Map<String, Object?> || json['kind'] != kind) throw damaged;
    final v = json['v'];
    // Checked before the key set, which a newer version may change.
    if (v is int && v > version) {
      throw const PasskeyBackupException(PasskeyBackupFailure.newerVersion);
    }
    if (v is! int ||
        v != version ||
        json.length != _keys.length ||
        !_keys.every(json.containsKey)) {
      throw damaged;
    }
    final rp = json['rpId'];
    if (rp is! String) throw damaged;
    if (rp != expectedRpId) {
      throw const PasskeyBackupException(
        PasskeyBackupFailure.otherRelyingParty,
      );
    }
    final record = _fromJson(json, rp);
    // Re-encoding also refuses repeated keys, escapes and other spellings.
    if (record == null || !record._validHeader || record.encode() != text) {
      throw damaged;
    }
    return record;
  }

  @override
  String toString() => 'PasskeyBackupRecord(<redacted>)';
}
