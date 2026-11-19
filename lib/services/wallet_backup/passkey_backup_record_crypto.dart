part of 'passkey_backup_record.dart';

const _label = 'gleec.wallet.passkey-backup.v1';
final _prfSalt = SHA256Digest().process(utf8.encode('$_label/prf'));
final _kekInfo = utf8.encode('$_label/kek');
final _commitLabel = utf8.encode('$_label/commit');

const _keys = {
  'kind',
  'v',
  'id',
  'rpId',
  'created',
  'credentialId',
  'userHandle',
  'backupEligible',
  'backupState',
  'aaguid',
  'transports',
  'wrap',
  'commit',
  'seed',
};
const _idLength = 16;
const _prfLength = 32;
const _keyLength = 32;
const _nonceLength = 12;
const _tagLength = 16;
const _maxCredentialIdLength = 1023;
const _wrapLength = _nonceLength + _keyLength + _tagLength;
const _minSeedLength = _nonceLength + 1 + _tagLength;
final _base64Url = RegExp(r'^[A-Za-z0-9_-]+$');
final _isoSecond = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
const _zeroUuid = '00000000-0000-0000-0000-000000000000';

extension on PasskeyBackupRecord {
  /// Everything but the three ciphertexts, as both GCM operations' AAD.
  Uint8List get _aad => utf8.encode(
    jsonEncode([
      PasskeyBackupRecord.kind,
      PasskeyBackupRecord.version,
      id,
      rpId,
      _iso(created),
      _encode(_credentialId),
      _encode(_userHandle),
      backupEligible,
      backupState,
      aaguid ?? '',
      transports,
    ]),
  );

  bool get _validHeader {
    final uuid = aaguid;
    return _isId(id) &&
        WalletTransferConfig.isAllowedBackupRpId(rpId) &&
        created.isUtc &&
        created.millisecond == 0 &&
        created.microsecond == 0 &&
        created.year >= 0 &&
        created.year <= 9999 &&
        _credentialId.isNotEmpty &&
        _credentialId.length <= _maxCredentialIdLength &&
        _userHandle.length == PasskeyBackupRecord.userHandleLength &&
        // A passkey cannot be backed up without being eligible to be.
        (backupEligible || !backupState) &&
        (uuid == null || (_uuid.hasMatch(uuid) && uuid != _zeroUuid)) &&
        // Filtering only drops, so an equal length means nothing was.
        passkeyTransports(transports).length == transports.length;
  }

  PasskeyBackupRecord _withCiphertext({
    required Uint8List wrap,
    required Uint8List commit,
    required Uint8List seed,
  }) => PasskeyBackupRecord._(
    id: id,
    rpId: rpId,
    created: created,
    credentialId: _credentialId,
    userHandle: _userHandle,
    backupEligible: backupEligible,
    backupState: backupState,
    aaguid: aaguid,
    transports: transports,
    wrap: wrap,
    commit: commit,
    seed: seed,
  );
}

/// Null when any field has the wrong type, encoding or length.
PasskeyBackupRecord? _fromJson(Map<String, Object?> json, String rpId) {
  if (json case {
    'id': final String id,
    'created': final String created,
    'credentialId': final String credentialId,
    'userHandle': final String userHandle,
    'backupEligible': final bool backupEligible,
    'backupState': final bool backupState,
    'aaguid': final String? aaguid,
    'transports': final List<Object?> transports,
    'wrap': final String wrap,
    'commit': final String commit,
    'seed': final String seed,
  }) {
    final kept = passkeyTransports(transports);
    if (!_isId(id) || kept.length != transports.length) return null;
    try {
      return PasskeyBackupRecord._(
        id: id,
        rpId: rpId,
        created: _created(created),
        credentialId: _binary(credentialId, 1, _maxCredentialIdLength),
        userHandle: _binary(
          userHandle,
          PasskeyBackupRecord.userHandleLength,
          PasskeyBackupRecord.userHandleLength,
        ),
        backupEligible: backupEligible,
        backupState: backupState,
        aaguid: aaguid,
        transports: kept,
        wrap: _binary(wrap, _wrapLength, _wrapLength),
        commit: _binary(commit, _keyLength, _keyLength),
        seed: _binary(seed, _minSeedLength, PasskeyBackupRecord.maxLength),
      );
    } on FormatException {
      return null;
    }
  }
  return null;
}

void _checkPrf(Uint8List prf) {
  if (prf.length != _prfLength) {
    throw const PasskeyBackupException(PasskeyBackupFailure.prfUnavailable);
  }
}

/// HKDF-SHA256 (RFC 5869), one block. The record id as salt gives every
/// record its own key from the same PRF output.
Uint8List _deriveKek(Uint8List prf, String id) {
  final prk = _hmac(utf8.encode(id), prf);
  try {
    return _hmac(prk, Uint8List.fromList([..._kekInfo, 1]));
  } finally {
    _wipe(prk);
  }
}

Uint8List _commitment(Uint8List dek, String id) =>
    _hmac(dek, Uint8List.fromList([..._commitLabel, ...utf8.encode(id)]));

Uint8List _hmac(Uint8List key, Uint8List data) =>
    (HMac(SHA256Digest(), 64)..init(KeyParameter(key))).process(data);

Uint8List _seal(
  Uint8List key,
  Uint8List aad,
  Uint8List plaintext,
  Random? random,
) {
  final nonce = PasskeyEnvelope.randomBytes(_nonceLength, random);
  final body = _cipher(true, key, nonce, aad).process(plaintext);
  return Uint8List.fromList([...nonce, ...body]);
}

/// Null when the tag does not verify. GCM writes the plaintext before it
/// checks the tag, so a failed attempt's output is wiped here.
Uint8List? _open(Uint8List key, Uint8List sealed, Uint8List aad) {
  final nonce = Uint8List.sublistView(sealed, 0, _nonceLength);
  final body = Uint8List.sublistView(sealed, _nonceLength);
  final cipher = _cipher(false, key, nonce, aad);
  final out = Uint8List(cipher.getOutputSize(body.length));
  try {
    final length = cipher.processBytes(body, 0, body.length, out, 0);
    return Uint8List.sublistView(out, 0, length + cipher.doFinal(out, length));
  } on InvalidCipherTextException {
    _wipe(out);
    return null;
  }
}

GCMBlockCipher _cipher(
  bool encrypt,
  Uint8List key,
  Uint8List nonce,
  Uint8List aad,
) => GCMBlockCipher(
  AESEngine(),
)..init(encrypt, AEADParameters(KeyParameter(key), _tagLength * 8, nonce, aad));

void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

String _encode(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

bool _isId(String value) {
  try {
    _binary(value, _idLength, _idLength);
    return true;
  } on FormatException {
    return false;
  }
}

/// Canonical unpadded base64url only: one spelling per value.
Uint8List _binary(String value, int minLength, int maxLength) {
  if (!_base64Url.hasMatch(value)) throw const FormatException();
  final bytes = base64Url.decode(base64Url.normalize(value));
  if (bytes.length < minLength ||
      bytes.length > maxLength ||
      _encode(bytes) != value) {
    throw const FormatException();
  }
  return bytes;
}

String _iso(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-'
      '${two(time.day)}T${two(time.hour)}:${two(time.minute)}:'
      '${two(time.second)}Z';
}

/// [DateTime.parse] rolls over out-of-range fields, so the value must
/// format back to the same text.
DateTime _created(String value) {
  final parsed = _isoSecond.hasMatch(value) ? DateTime.parse(value) : null;
  if (parsed == null || _iso(parsed) != value) throw const FormatException();
  return parsed;
}
