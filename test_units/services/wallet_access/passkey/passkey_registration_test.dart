import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration_types.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';
import 'package:web_dex/services/wallet_backup/passkey_provider_names.dart';

import 'passkey_registration_test_support.dart';
import 'passkey_test_support.dart' show bytesOf;

part 'passkey_registration_cbor_cases.dart';
part 'passkey_registration_channel_cases.dart';

Matcher _fails(WalletAccessFailure failure) => throwsA(
  isA<WalletAccessException>().having((e) => e.failure, 'failure', failure),
);

final _invalid = _fails(WalletAccessFailure.invalidResponse);

final _request = PasskeyRegistrationRequest(
  rpId: registrationRp,
  challenge: bytesOf(11),
  userId: bytesOf(12),
  userName: 'Gleec Wallet recovery',
  displayName: 'Gleec Wallet recovery – Savings',
  prfSalt: bytesOf(13),
);

final _id = bytesOf(1, 16);

PasskeyRegistration _registration({
  Uint8List? clientData,
  Uint8List? attestation,
  Uint8List? credentialId,
  Uint8List? prf,
  List<String> transports = const ['internal', 'hybrid'],
}) => PasskeyRegistration(
  credentialId: credentialId ?? _id,
  clientDataJson: clientData ?? registrationClientData(_request.challenge),
  attestationObject:
      attestation ??
      registrationAttestation(registrationAuthData(credentialId: _id)),
  prfOutput: prf,
  transports: transports,
);

Uint8List _attested({
  int flags = registrationFlags,
  String rpId = registrationRp,
  List<int>? aaguid,
  List<int>? credentialId,
  Object? key,
  Object? extensions,
  List<int> trailing = const [],
}) => registrationAttestation(
  registrationAuthData(
    credentialId: credentialId ?? _id,
    rpId: rpId,
    flags: flags,
    aaguid: aaguid,
    key: key,
    extensions: extensions,
    trailing: trailing,
  ),
);

RegisteredPasskey _check(PasskeyRegistration registration) =>
    checkPasskeyRegistration(registration, _request);

/// Accepted, or refused as an invalid response: never any other error.
bool _accepted(Uint8List attestation) {
  try {
    _check(_registration(attestation: attestation));
    return true;
  } on WalletAccessException catch (error) {
    expect(error.failure, WalletAccessFailure.invalidResponse);
    return false;
  }
}

void main() {
  group('passkey registration check', () {
    test('accepts a synced passkey made for the relying party', () {
      final prf = bytesOf(20);
      final passkey = _check(_registration(prf: prf));
      expect(passkey.credentialId, _id);
      expect(passkey.backupEligible, isTrue);
      expect(passkey.backupState, isTrue);
      expect(passkey.aaguid, isNull);
      expect(passkey.transports, ['internal', 'hybrid']);
      expect(passkey.reachesOtherDevices, isTrue);
      // The same buffer, so one wipe covers it.
      expect(identical(passkey.prfOutput, prf), isTrue);

      final android = _registration(
        clientData: registrationClientData(
          _request.challenge,
          origin:
              'android:apk-key-hash:${base64Url.encode(bytesOf(5)).replaceAll('=', '')}',
          crossOrigin: null,
        ),
      );
      expect(_check(android).prfOutput, isNull);
    });

    test('names the provider from a non-zero AAGUID only', () {
      final gpm = [
        0xea, 0x9b, 0x8d, 0x66, 0x4d, 0x01, 0x1d, 0x21, //
        0x3c, 0xe4, 0xb6, 0xb4, 0x8c, 0xb5, 0x75, 0xd4,
      ];
      final passkey = _check(
        _registration(attestation: _attested(aaguid: gpm)),
      );
      expect(passkey.aaguid, 'ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4');
      expect(passkeyProviderName(passkey.aaguid), 'Google Password Manager');
      final unknown = _check(
        _registration(attestation: _attested(aaguid: bytesOf(3, 16))),
      );
      expect(unknown.aaguid, '5d5e5f60-6162-6364-6566-6768696a6b6c');
      expect(passkeyProviderName(unknown.aaguid), isNull);
    });

    test('reads the backup flags and refuses state without eligibility', () {
      RegisteredPasskey withFlags(
        int flags, [
        List<String> transports = const ['internal'],
      ]) => _check(
        _registration(
          attestation: _attested(flags: flags),
          transports: transports,
        ),
      );
      final local = withFlags(0x45);
      expect([local.backupEligible, local.backupState], [false, false]);
      expect(local.reachesOtherDevices, isFalse);
      expect(withFlags(0x45, ['usb']).reachesOtherDevices, isTrue);
      final eligible = withFlags(0x4d);
      expect([eligible.backupEligible, eligible.backupState], [true, false]);
      expect(eligible.reachesOtherDevices, isTrue);
      expect(() => withFlags(0x55), _invalid);
    });

    test('requires presence, verification and attested credential data', () {
      for (final flags in [0x5c, 0x59, 0x1d, 0x00]) {
        expect(
          () => _check(_registration(attestation: _attested(flags: flags))),
          _invalid,
          reason: 'flags $flags',
        );
      }
    });

    test('refuses a passkey for another site, request or origin', () {
      final cases = <String, PasskeyRegistration>{
        'another relying party': _registration(
          attestation: _attested(rpId: 'evil.example'),
        ),
        'an assertion': _registration(
          clientData: registrationClientData(
            _request.challenge,
            type: 'webauthn.get',
          ),
        ),
        'another challenge': _registration(
          clientData: registrationClientData(bytesOf(99)),
        ),
        'another origin': _registration(
          clientData: registrationClientData(
            _request.challenge,
            origin: 'https://evil.example',
          ),
        ),
        'a cross-origin frame': _registration(
          clientData: registrationClientData(
            _request.challenge,
            crossOrigin: true,
          ),
        ),
        'a malformed cross-origin flag': _registration(
          clientData: registrationClientData(
            _request.challenge,
            crossOrigin: 'false',
          ),
        ),
        'client data that is not JSON': _registration(
          clientData: utf8.encode('{"type":'),
        ),
        'client data that is not UTF-8': _registration(
          clientData: Uint8List.fromList([0x7b, 0xff, 0x7d]),
        ),
        'client data that is a list': _registration(
          clientData: utf8.encode('[]'),
        ),
        'oversized client data': _registration(
          clientData: Uint8List.fromList([
            ...registrationClientData(_request.challenge),
            ...List.filled(16384, 0x20),
          ]),
        ),
        'a padded challenge': _registration(
          clientData: utf8.encode(
            jsonEncode({
              'type': 'webauthn.create',
              'challenge': base64Url.encode(_request.challenge),
              'origin': 'https://$registrationRp',
            }),
          ),
        ),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(() => _check(value), _invalid, reason: key);
      }
    });

    test('requires the credential the platform reported', () {
      expect(
        () => _check(
          _registration(attestation: _attested(credentialId: bytesOf(2, 16))),
        ),
        _invalid,
      );
      expect(
        () => _check(_registration(credentialId: bytesOf(1, 17))),
        _invalid,
      );
      expect(() => _check(_registration(credentialId: Uint8List(0))), _invalid);
      final longest = bytesOf(1, 1023);
      expect(
        _check(
          _registration(
            credentialId: longest,
            attestation: _attested(credentialId: longest),
          ),
        ).credentialId,
        longest,
      );
      final tooLong = bytesOf(1, 1024);
      expect(
        () => _check(
          _registration(
            credentialId: tooLong,
            attestation: _attested(credentialId: tooLong),
          ),
        ),
        _invalid,
      );
    });

    test('takes a PRF output only at full length', () {
      expect(_check(_registration()).prfOutput, isNull);
      for (final length in [0, 16, 31, 33, 64]) {
        expect(
          () => _check(_registration(prf: bytesOf(4, length))),
          _invalid,
          reason: '$length bytes',
        );
      }
    });

    test('keeps well-formed transport hints once each', () {
      final passkey = _check(
        _registration(
          transports: [
            'hybrid',
            'internal',
            'hybrid',
            'USB',
            '',
            'smart-card',
            'x' * 33,
            'a',
            'b',
            'c',
            'd',
            'e',
            'f',
          ],
        ),
      );
      expect(passkey.transports, [
        'hybrid',
        'internal',
        'smart-card',
        'a',
        'b',
        'c',
        'd',
        'e',
      ]);
      expect(() => passkey.transports.add('usb'), throwsUnsupportedError);
    });

    test('requires exactly a format, a statement and the data', () {
      final data = registrationAuthData(credentialId: _id);
      final statement = <Object?, Object?>{
        'alg': -7,
        'sig': bytesOf(6, 70),
        'x5c': [bytesOf(7, 300), bytesOf(8, 200)],
      };
      expect(
        _accepted(
          registrationAttestation(data, format: 'packed', statement: statement),
        ),
        isTrue,
      );
      final cases = <String, Object?>{
        'no format': {'attStmt': <Object?, Object?>{}, 'authData': data},
        'an extra key': {
          'fmt': 'none',
          'attStmt': <Object?, Object?>{},
          'authData': data,
          'epAtt': true,
        },
        'an empty format': {
          'fmt': '',
          'attStmt': <Object?, Object?>{},
          'authData': data,
        },
        'a numeric format': {
          'fmt': 1,
          'attStmt': <Object?, Object?>{},
          'authData': data,
        },
        'a list statement': {
          'fmt': 'none',
          'attStmt': <Object?>[],
          'authData': data,
        },
        'text data': {
          'fmt': 'none',
          'attStmt': <Object?, Object?>{},
          'authData': 'data',
        },
        'integer keys': {1: 'none', 2: <Object?, Object?>{}, 3: data},
        'a list': ['none', <Object?, Object?>{}, data],
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(_accepted(cbor(value)), isFalse, reason: key);
      }
      final valid = registrationAttestation(data);
      expect(_accepted(Uint8List.fromList([...valid, 0])), isFalse);
      // The same map with "fmt" written twice.
      expect(
        _accepted(
          Uint8List.fromList([
            0xa4,
            ...valid.sublist(1),
            ...cbor('fmt'),
            ...cbor('none'),
          ]),
        ),
        isFalse,
      );
      expect(
        _accepted(
          registrationAttestation(data, statement: {'x5c': bytesOf(1, 70000)}),
        ),
        isFalse,
      );
    });

    test('accepts extensions only when flagged, and nothing after', () {
      const extensions = {'credProtect': 2, 'hmac-secret': true};
      expect(_accepted(_attested(flags: 0xdd, extensions: extensions)), isTrue);
      expect(_accepted(_attested(extensions: extensions)), isFalse);
      expect(_accepted(_attested(trailing: [0x00])), isFalse);
      expect(_accepted(_attested(flags: 0xdd)), isFalse);
      expect(_accepted(_attested(flags: 0xdd, extensions: [1])), isFalse);
      expect(
        _accepted(
          _attested(flags: 0xdd, extensions: extensions, trailing: [0xa0]),
        ),
        isFalse,
      );
    });

    test('requires a COSE key with its type and algorithm', () {
      expect(_accepted(_attested(key: {1: 1, 3: -8, -1: 6})), isTrue);
      for (final key in <Object?>[
        [1, 2],
        bytesOf(1, 64),
        {3: -7},
        {1: 2},
        {1: 'EC2', 3: -7},
        <Object?, Object?>{},
      ]) {
        expect(_accepted(_attested(key: key)), isFalse, reason: '$key');
      }
    });

    test('refuses every truncation of the object and of its data', () {
      final object = _attested(flags: 0xdd, extensions: {'credProtect': 2});
      for (var length = 0; length < object.length; length++) {
        expect(
          _accepted(Uint8List.sublistView(object, 0, length)),
          isFalse,
          reason: 'object cut at $length',
        );
      }
      final data = registrationAuthData(credentialId: _id);
      for (var length = 0; length < data.length; length++) {
        expect(
          _accepted(
            registrationAttestation(Uint8List.sublistView(data, 0, length)),
          ),
          isFalse,
          reason: 'data cut at $length',
        );
      }
    });

    test('garbage and flipped bits never fail as anything else', () {
      final random = Random(7);
      for (var i = 0; i < 500; i++) {
        final garbage = Uint8List.fromList(
          List.generate(random.nextInt(200), (_) => random.nextInt(256)),
        );
        expect(_accepted(garbage), isFalse);
      }
      final data = registrationAuthData(
        credentialId: _id,
        flags: 0xdd,
        extensions: {'credProtect': 2},
      );
      final object = registrationAttestation(data);
      // The data is the map's last value, so it ends the object.
      final start = object.length - data.length;
      final flagBits = <int>{};
      var unread = 0;
      for (var index = 0; index < object.length; index++) {
        for (var bit = 0; bit < 8; bit++) {
          final flipped = Uint8List.fromList(object)..[index] ^= 1 << bit;
          if (!_accepted(flipped)) continue;
          final offset = index - start;
          expect(
            offset >= 0 && (offset < 32 || (offset >= 53 && offset < 71)),
            isFalse,
            reason: 'the RP hash or the credential at $offset',
          );
          if (offset == 32) flagBits.add(bit);
          if ((offset >= 33 && offset < 53) || offset >= 71) unread++;
        }
      }
      // Only the reserved bits and the backup state may change; signCount,
      // the AAGUID, the key's contents and extension values are not checked.
      expect(flagBits, {1, 4, 5});
      expect(unread, greaterThan(0));
    });
  });

  group('passkey CBOR reader', _cborReaderTests);
  group('passkey registration method channel', _channelTests);
  group('passkey provider names', _providerNameTests);
}
