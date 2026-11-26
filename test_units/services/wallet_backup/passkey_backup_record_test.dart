import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show AESEngine, KeyParameter;
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration_types.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_record.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

import '../wallet_access/passkey/passkey_test_support.dart' show bytesOf;

part 'passkey_backup_record_vectors.dart';

const _rp = 'backup.example.net';
const _gpm = 'ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4';
const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon about';
final _prf = bytesOf(4);

Matcher _fails(PasskeyBackupFailure failure) => throwsA(
  isA<PasskeyBackupException>().having((e) => e.failure, 'failure', failure),
);

WalletTransferSecret _secret({
  String name = 'Savings',
  TransferWalletType type = TransferWalletType.hd,
  String seed = _phrase,
  bool phraseConfirmed = true,
}) => WalletTransferSecret(
  walletName: name,
  type: type,
  seed: seed,
  phraseConfirmed: phraseConfirmed,
);

RegisteredPasskey _passkey({
  Uint8List? credentialId,
  bool backupEligible = true,
  bool backupState = true,
  String? aaguid = _gpm,
  List<String> transports = const ['hybrid', 'internal'],
}) => RegisteredPasskey(
  credentialId: credentialId ?? bytesOf(1, 16),
  backupEligible: backupEligible,
  backupState: backupState,
  transports: transports,
  aaguid: aaguid,
);

PasskeyBackupRecord _seal({
  String rpId = _rp,
  RegisteredPasskey? passkey,
  Uint8List? userHandle,
  Uint8List? prf,
  WalletTransferSecret? secret,
  DateTime? created,
  Random? random,
}) => PasskeyBackupRecord.seal(
  rpId: rpId,
  passkey: passkey ?? _passkey(),
  userHandle: userHandle ?? bytesOf(2),
  prf: prf ?? _prf,
  secret: secret ?? _secret(),
  created: created ?? DateTime.utc(2026, 11, 18, 22, 53, 7),
  random: random,
);

Map<String, Object?> _json(PasskeyBackupRecord record) =>
    jsonDecode(record.encode()) as Map<String, Object?>;

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _unb64(Object? value) =>
    base64Url.decode(base64Url.normalize(value! as String));

String _flipByte(Object? field, int index, [int bit = 0]) =>
    _b64(_unb64(field)..[index] ^= 1 << bit);

String _flipChar(String text, int index, [int bit = 0]) =>
    String.fromCharCodes(text.codeUnits.toList()..[index] ^= 1 << bit);

/// What decoding and opening [raw] with the vector's PRF fails with, or
/// null when it opens. Any other error fails the test.
PasskeyBackupFailure? _failure(String raw, {String rpId = _rp}) {
  try {
    PasskeyBackupRecord.decode(raw, expectedRpId: rpId).open(_prf);
    return null;
  } on PasskeyBackupException catch (error) {
    return error.failure;
  }
}

void main() {
  group('passkey backup record', () {
    test('evaluates the PRF at one fixed salt, handed out as a copy', () {
      final salt = PasskeyBackupRecord.prfSalt;
      expect(
        salt,
        sha256.convert(utf8.encode('gleec.wallet.passkey-backup.v1/prf')).bytes,
      );
      expect(
        _hex(salt),
        '1b86e2c85d04320e38c1c085dfba4a750d906a654c0fd0d4bd971054245530ba',
      );
      salt.fillRange(0, salt.length, 0);
      expect(PasskeyBackupRecord.prfSalt, isNot(salt));
    });

    test('round-trips and opens only with its passkey PRF', () {
      final record = _seal(
        created: DateTime.utc(2026, 11, 18, 22, 53, 7, 999, 999).toLocal(),
      );
      final raw = record.encode();
      final decoded = PasskeyBackupRecord.decode(raw, expectedRpId: _rp);
      expect(decoded.encode(), raw);
      expect(decoded.id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      expect(decoded.storageName, 'gleec-passkey-backup-${decoded.id}.json');
      expect(decoded.rpId, _rp);
      expect(decoded.created, DateTime.utc(2026, 11, 18, 22, 53, 7));
      expect(decoded.created.isUtc, isTrue);
      expect(decoded.credentialId, bytesOf(1, 16));
      expect(decoded.userHandle, bytesOf(2));
      expect([decoded.backupEligible, decoded.backupState], [true, true]);
      expect(decoded.aaguid, _gpm);
      expect(decoded.transports, ['hybrid', 'internal']);

      final opened = decoded.open(_prf);
      expect(opened.walletName, 'Savings');
      expect(opened.type, TransferWalletType.hd);
      expect(opened.seed, _phrase);
      expect(opened.phraseConfirmed, isTrue);
      // Nothing is used up, and the caller's PRF is left as it was.
      expect(decoded.open(_prf).seed, _phrase);
      expect(_prf, bytesOf(4));

      expect(
        () => decoded.open(bytesOf(5)),
        _fails(PasskeyBackupFailure.wrongPasskey),
      );
      expect(
        () => decoded.open(bytesOf(4, 16)),
        _fails(PasskeyBackupFailure.prfUnavailable),
      );
    });

    test('keeps a legacy seed byte for byte, and its flags', () {
      // Doubled spaces, a tab and a decomposed accent: never normalised.
      final seed =
          '  Legacy Seed, with  spaces e${String.fromCharCode(0x301)} and\ttabs ';
      final record = _seal(
        passkey: _passkey(backupState: false, aaguid: null, transports: []),
        secret: _secret(
          name: 'Ölwallet ✓',
          type: TransferWalletType.legacy,
          seed: seed,
          phraseConfirmed: false,
        ),
      );
      final decoded = PasskeyBackupRecord.decode(
        record.encode(),
        expectedRpId: _rp,
      );
      expect([decoded.backupEligible, decoded.backupState], [true, false]);
      expect(decoded.aaguid, isNull);
      expect(decoded.transports, isEmpty);
      final opened = decoded.open(_prf);
      expect(opened.seed, seed);
      expect(opened.walletName, 'Ölwallet ✓');
      expect(opened.type, TransferWalletType.legacy);
      expect(opened.phraseConfirmed, isFalse);
    });

    test('shows no secret and hands out copies of its bytes', () {
      final record = _seal();
      final raw = record.encode();
      for (final secret in ['Savings', 'abandon', 'about']) {
        expect(raw, isNot(contains(secret)));
      }
      expect(record.toString(), 'PasskeyBackupRecord(<redacted>)');
      expect(
        const PasskeyBackupException(PasskeyBackupFailure.wrongPasskey)
            .toString(),
        'PasskeyBackupException(wrongPasskey)',
      );
      record.credentialId.fillRange(0, 16, 0);
      record.userHandle.fillRange(0, 32, 0);
      expect(() => record.transports.add('usb'), throwsUnsupportedError);
      expect(record.open(_prf).seed, _phrase);
      // Fresh randomness every time: id, data key and nonces.
      final again = _json(_seal());
      for (final field in ['id', 'wrap', 'commit', 'seed']) {
        expect(again[field], isNot(_json(record)[field]), reason: field);
      }
    });

    test('a flipped bit in each field fails the way that field should', () {
      final json = _json(_seal());
      const damaged = PasskeyBackupFailure.damaged;
      const wrong = PasskeyBackupFailure.wrongPasskey;
      final seed = _unb64(json['seed']);
      final cases = <(String, Object?, PasskeyBackupFailure)>[
        ('kind', _flipChar(PasskeyBackupRecord.kind, 0), damaged),
        ('v', 1 ^ 1, damaged),
        ('v', 1 ^ 2, PasskeyBackupFailure.newerVersion),
        ('id', _flipByte(json['id'], 0), wrong),
        ('id', _flipByte(json['id'], 15, 7), wrong),
        ('rpId', _flipChar(_rp, 0), PasskeyBackupFailure.otherRelyingParty),
        ('created', _flipChar('2026-11-18T22:53:07Z', 18), wrong),
        ('created', _flipChar('2026-11-18T22:53:07Z', 10), damaged),
        ('credentialId', _flipByte(json['credentialId'], 3), wrong),
        ('userHandle', _flipByte(json['userHandle'], 31, 7), wrong),
        // Backed up without being eligible is a contradiction.
        ('backupEligible', false, damaged),
        ('backupState', false, wrong),
        ('aaguid', _flipChar(_gpm, 2), wrong),
        ('aaguid', _flipChar(_gpm, 0, 5), damaged),
        ('aaguid', null, wrong),
        ('transports', ['hybrid', _flipChar('internal', 0)], wrong),
        ('transports', ['internal', 'hybrid'], wrong),
        ('wrap', _flipByte(json['wrap'], 0), wrong),
        ('wrap', _flipByte(json['wrap'], 30), wrong),
        ('wrap', _flipByte(json['wrap'], 59, 7), wrong),
        ('commit', _flipByte(json['commit'], 0), wrong),
        ('commit', _flipByte(json['commit'], 31, 7), wrong),
        ('seed', _flipByte(json['seed'], 0), wrong),
        ('seed', _flipByte(json['seed'], 12), wrong),
        ('seed', _flipByte(json['seed'], seed.length - 1, 7), wrong),
      ];
      for (final (field, value, failure) in cases) {
        expect(
          _failure(jsonEncode({...json, field: value})),
          failure,
          reason: '$field = $value',
        );
      }
    });

    test('no single flipped bit anywhere in the text opens', () {
      final raw = _seal().encode();
      for (var index = 0; index < raw.length; index++) {
        for (final bit in [0, 1, 5]) {
          expect(
            _failure(_flipChar(raw, index, bit)),
            isNotNull,
            reason: 'character $index, bit $bit',
          );
        }
      }
    });

    test('binds every header field: swapped between records, none opens', () {
      final a = _json(_seal());
      final b = _json(
        _seal(
          rpId: 'other-backup.example.net',
          passkey: _passkey(credentialId: bytesOf(9, 16)),
          userHandle: bytesOf(8),
          created: DateTime.utc(2027, 2, 3, 4, 5, 6),
        ),
      );
      for (final field in [
        'id',
        'created',
        'credentialId',
        'userHandle',
        'wrap',
        'commit',
        'seed',
      ]) {
        expect(
          _failure(jsonEncode({...a, field: b[field]})),
          PasskeyBackupFailure.wrongPasskey,
          reason: field,
        );
      }
      final moved = jsonEncode({...a, 'rpId': b['rpId']});
      expect(_failure(moved), PasskeyBackupFailure.otherRelyingParty);
      expect(
        _failure(moved, rpId: 'other-backup.example.net'),
        PasskeyBackupFailure.wrongPasskey,
      );
    });

    test('accepts only the exact stored form', () {
      final record = _seal();
      final raw = record.encode();
      final json = _json(record);
      String withField(String key, Object? value) =>
          jsonEncode({...json, key: value});
      expect(
        PasskeyBackupRecord.decode('\n  $raw\r\n', expectedRpId: _rp).encode(),
        raw,
      );
      final cases = <String, String>{
        'not JSON': 'not json',
        'a list': '[]',
        'an extra key': withField('extra', 1),
        'a missing key': jsonEncode({...json}..remove('commit')),
        'a repeated key': raw.replaceFirst('"kind"', '"seed":"AAAA","kind"'),
        'inner whitespace': raw.replaceFirst(',"v"', ', "v"'),
        'reordered keys': jsonEncode({'v': 1, ...json}),
        // The kind with its hyphen written as a JSON escape.
        'an escaped character': raw.replaceFirst(
          'passkey-backup',
          'passkey${String.fromCharCode(92)}u002dbackup',
        ),
        'v as text': withField('v', '1'),
        'v as a fraction': raw.replaceFirst('"v":1', '"v":1.0'),
        'too long':
            '$raw${' ' * (PasskeyBackupRecord.maxLength - raw.length + 1)}',
        'a padded id': withField('id', '${json['id']}=='),
        'a short id': withField('id', _b64(bytesOf(5, 15))),
        'a non-canonical id': withField(
          'id',
          '${(json['id']! as String).substring(0, 21)}B',
        ),
        'standard base64': withField('credentialId', '+/8'),
        'an empty credential id': withField('credentialId', ''),
        'a long credential id': withField(
          'credentialId',
          _b64(bytesOf(1, 1024)),
        ),
        'a short user handle': withField('userHandle', _b64(bytesOf(2, 31))),
        'a short wrap': withField('wrap', _b64(bytesOf(1, 59))),
        'a long wrap': withField('wrap', _b64(bytesOf(1, 61))),
        'a short commit': withField('commit', _b64(bytesOf(1, 31))),
        'a short seed': withField('seed', _b64(bytesOf(1, 28))),
        'binary as a number': withField('seed', 7),
        'created with milliseconds': withField(
          'created',
          '2026-11-18T22:53:07.000Z',
        ),
        'created with an offset': withField(
          'created',
          '2026-11-18T22:53:07+00:00',
        ),
        'created out of range': withField('created', '2026-13-18T22:53:07Z'),
        'created as a number': withField('created', 1763506387),
        'an uppercase AAGUID': withField('aaguid', _gpm.toUpperCase()),
        'a zero AAGUID': withField(
          'aaguid',
          '00000000-0000-0000-0000-000000000000',
        ),
        'a numeric AAGUID': withField('aaguid', 5),
        'a repeated transport': withField('transports', ['hybrid', 'hybrid']),
        'a malformed transport': withField('transports', ['Hybrid']),
        'too many transports': withField('transports', [
          for (var i = 0; i < 9; i++) 't$i',
        ]),
        'a numeric transport': withField('transports', [1]),
        'transports as text': withField('transports', 'hybrid'),
        'a numeric flag': withField('backupEligible', 1),
        'a web wallet host': jsonEncode({...json, 'rpId': 'dex.gleec.com'}),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final rpId = key == 'a web wallet host' ? 'dex.gleec.com' : _rp;
        expect(
          () => PasskeyBackupRecord.decode(value, expectedRpId: rpId),
          _fails(PasskeyBackupFailure.damaged),
          reason: key,
        );
      }
    });

    test('names a newer version and another relying party', () {
      final json = _json(_seal());
      void expectFailure(
        String raw,
        PasskeyBackupFailure failure, {
        String rpId = _rp,
      }) => expect(
        () => PasskeyBackupRecord.decode(raw, expectedRpId: rpId),
        _fails(failure),
        reason: raw,
      );
      expectFailure(
        jsonEncode({...json, 'v': 2, 'added': true}),
        PasskeyBackupFailure.newerVersion,
      );
      expectFailure(
        jsonEncode({'kind': PasskeyBackupRecord.kind, 'v': 9}),
        PasskeyBackupFailure.newerVersion,
      );
      expectFailure(
        jsonEncode({...json, 'v': 0}),
        PasskeyBackupFailure.damaged,
      );
      expectFailure(
        jsonEncode({...json, 'kind': 'gleec.wallet.other', 'v': 2}),
        PasskeyBackupFailure.damaged,
      );
      expectFailure(
        jsonEncode(json),
        PasskeyBackupFailure.otherRelyingParty,
        rpId: 'other-backup.example.net',
      );
      expectFailure(
        jsonEncode({...json, 'rpId': 7}),
        PasskeyBackupFailure.damaged,
      );
    });

    test('refuses to seal what a registration check would not pass', () {
      final cases = <String, PasskeyBackupRecord Function()>{
        'state without eligibility': () =>
            _seal(passkey: _passkey(backupEligible: false)),
        'the web wallet host': () => _seal(rpId: 'dex.gleec.com'),
        'the web wallet domain': () => _seal(rpId: 'gleec.com'),
        'not a host': () => _seal(rpId: 'localhost'),
        'a short user handle': () => _seal(userHandle: bytesOf(2, 16)),
        'no credential id': () =>
            _seal(passkey: _passkey(credentialId: Uint8List(0))),
        'an uppercase AAGUID': () =>
            _seal(passkey: _passkey(aaguid: _gpm.toUpperCase())),
        'a repeated transport': () =>
            _seal(passkey: _passkey(transports: ['usb', 'usb'])),
        'a year past 9999': () => _seal(created: DateTime.utc(10000)),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(value, throwsArgumentError, reason: key);
      }
      expect(
        () => _seal(prf: bytesOf(4, 16)),
        _fails(PasskeyBackupFailure.prfUnavailable),
      );
    });

    test('a record at every limit fits the size bound and opens', () {
      final rpId = '${'a' * 63}.${'b' * 63}.${'c' * 63}.${'d' * 61}';
      // A name of escaped characters, and a seed filling what is left.
      WalletTransferSecret secretWith(String seed) => _secret(
        name: '\u0001' * WalletTransferSecret.maxNameLength,
        type: TransferWalletType.legacy,
        seed: seed,
        phraseConfirmed: false,
      );
      final overhead = secretWith('x').encode().length - 1;
      final secret = secretWith(
        'x' * (WalletTransferSecret.maxEncodedBytes - overhead),
      );
      expect(secret.encode().length, WalletTransferSecret.maxEncodedBytes);
      final record = _seal(
        rpId: rpId,
        secret: secret,
        passkey: _passkey(
          credentialId: bytesOf(1, 1023),
          transports: [for (var i = 0; i < 8; i++) 't$i'.padRight(32, 'x')],
        ),
      );
      final raw = record.encode();
      expect(raw.length, lessThanOrEqualTo(PasskeyBackupRecord.maxLength));
      final opened = PasskeyBackupRecord.decode(
        raw,
        expectedRpId: rpId,
      ).open(_prf);
      expect(opened.seed, secret.seed);
    });

    _vectorTests();
  });
}
