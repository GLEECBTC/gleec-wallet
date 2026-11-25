import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_assertion_check.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_authenticator.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_envelope.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

import 'passkey_test_support.dart';

Matcher _fails(WalletAccessFailure failure) => throwsA(
  isA<WalletAccessException>().having((e) => e.failure, 'failure', failure),
);

PasskeyEnvelope _sealed({String value = passkeyPassword, int revision = 1}) =>
    PasskeyEnvelope.seal(
      key: passkeyWalletKey,
      revision: revision,
      rpId: passkeyRp,
      credentialId: bytesOf(1, 16),
      userHandle: bytesOf(2),
      enrollmentId: 'enrollment-0123456789AB',
      salt: bytesOf(3),
      aesKey: PasskeyEnvelope.deriveKey(bytesOf(4)),
      value: value,
    );

void main() {
  group('passkey envelope', () {
    final key = PasskeyEnvelope.deriveKey(bytesOf(4));

    test('derives HKDF-SHA256 with an empty salt and the envelope info', () {
      // An independent RFC 5869 implementation over package:crypto.
      final prk = Hmac(sha256, List.filled(32, 0)).convert(bytesOf(4)).bytes;
      final okm = Hmac(
        sha256,
        prk,
      ).convert([...utf8.encode('gleec.wallet.passkey-envelope.v1'), 1]).bytes;
      expect(PasskeyEnvelope.deriveKey(bytesOf(4)), okm);
      expect(
        () => PasskeyEnvelope.deriveKey(bytesOf(4, 16)),
        _fails(WalletAccessFailure.prfUnavailable),
      );
    });

    test('opens only with the key it was sealed under', () {
      final envelope = _sealed();
      expect(envelope.open(key), passkeyPassword);
      expect(
        () => envelope.open(PasskeyEnvelope.deriveKey(bytesOf(5))),
        _fails(WalletAccessFailure.envelopeCorrupt),
      );
    });

    test('round-trips through its stored form', () {
      final stored = _sealed().encode();
      final decoded = PasskeyEnvelope.decode(
        stored,
        expectedKey: passkeyWalletKey,
        expectedRpId: passkeyRp,
      );
      expect(decoded.open(key), passkeyPassword);
      expect(decoded.encode(), stored);
    });

    test('authenticates every stored field', () {
      final stored = jsonDecode(_sealed().encode()) as Map<String, dynamic>;
      final altered = <String, Object?>{
        'revision': 2,
        'credentialId': base64Url.encode(bytesOf(9, 16)).replaceAll('=', ''),
        'userHandle': base64Url.encode(bytesOf(9)).replaceAll('=', ''),
        'enrollmentId': 'enrollment-ZZZZZZZZZZZZ',
        'salt': base64Url.encode(bytesOf(9)).replaceAll('=', ''),
        'nonce': base64Url.encode(bytesOf(9, 12)).replaceAll('=', ''),
      };
      for (final MapEntry(key: field, :value) in altered.entries) {
        final tampered = PasskeyEnvelope.decode(
          jsonEncode({...stored, field: value}),
          expectedKey: passkeyWalletKey,
          expectedRpId: passkeyRp,
        );
        expect(
          () => tampered.open(key),
          _fails(WalletAccessFailure.envelopeCorrupt),
          reason: field,
        );
      }
    });

    test('rejects a record for another wallet, site, kind or version', () {
      final stored = jsonDecode(_sealed().encode()) as Map<String, dynamic>;
      for (final change in <Map<String, Object?>>[
        {'key': 'gleec.wallet.other'},
        {'rpId': 'preview.gleec.com'},
        {'kind': 'something-else'},
        {'v': 2},
        {'revision': 0},
        {'salt': base64Url.encode(bytesOf(3, 16)).replaceAll('=', '')},
        {'ciphertext': 'AA'},
        {'credentialId': 'not base64!'},
      ]) {
        expect(
          () => PasskeyEnvelope.decode(
            jsonEncode({...stored, ...change}),
            expectedKey: passkeyWalletKey,
            expectedRpId: passkeyRp,
          ),
          _fails(WalletAccessFailure.envelopeCorrupt),
          reason: '$change',
        );
      }
      expect(
        () => PasskeyEnvelope.decode(
          'not json',
          expectedKey: passkeyWalletKey,
          expectedRpId: passkeyRp,
        ),
        _fails(WalletAccessFailure.envelopeCorrupt),
      );
    });

    test('reseals under the next revision with the same binding', () {
      final first = _sealed();
      final next = first.reseal('A-new-password-the-owner-chose', key);
      expect(next.revision, 2);
      expect(next.salt, first.salt);
      expect(next.credentialId, first.credentialId);
      expect(next.nonce, isNot(first.nonce));
      expect(next.open(key), 'A-new-password-the-owner-chose');
    });
  });

  group('passkey assertion checks', () {
    late FakePasskeyAuthenticator authenticator;
    late PasskeyAssertionRequest request;

    setUp(() {
      authenticator = FakePasskeyAuthenticator();
      request = PasskeyAssertionRequest(
        rpId: passkeyRp,
        challenge: bytesOf(11),
        salt: bytesOf(12),
      );
    });

    Future<void> check({Uint8List? expectedUserHandle}) async {
      final assertion = await authenticator.getAssertion(request);
      checkPasskeyAssertion(
        assertion,
        request,
        expectedUserHandle: expectedUserHandle,
      );
    }

    test('accepts a verified assertion for the wallet site', () async {
      await check();
      authenticator.origin =
          'android:apk-key-hash:${base64Url.encode(bytesOf(5)).replaceAll('=', '')}';
      await check();
    });

    test('rejects what the passkey did not verify or sign for us', () async {
      final cases = <String, void Function()>{
        'no user verification': () => authenticator.flags = 0x01,
        'no user presence': () => authenticator.flags = 0x04,
        'another site': () => authenticator.rpIdForHash = 'evil.example',
        'another origin': () => authenticator.origin = 'https://evil.example',
        'a registration': () => authenticator.type = 'webauthn.create',
        'another challenge': () => authenticator.wrongChallenge = true,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        authenticator = FakePasskeyAuthenticator();
        value();
        await expectLater(
          check(),
          _fails(WalletAccessFailure.invalidResponse),
          reason: key,
        );
      }
    });

    test('requires the bound passkey and its user', () async {
      request = PasskeyAssertionRequest(
        rpId: passkeyRp,
        challenge: bytesOf(11),
        salt: bytesOf(12),
        allowCredentials: [authenticator.passkeys.first.id],
      );
      await check(expectedUserHandle: authenticator.passkeys.first.userHandle);
      await expectLater(
        check(expectedUserHandle: bytesOf(77)),
        _fails(WalletAccessFailure.invalidResponse),
      );
      final assertion = await authenticator.getAssertion(request);
      final other = PasskeyAssertionRequest(
        rpId: passkeyRp,
        challenge: bytesOf(11),
        salt: bytesOf(12),
        allowCredentials: [bytesOf(50, 16)],
      );
      expect(
        () => checkPasskeyAssertion(assertion, other),
        _fails(WalletAccessFailure.invalidResponse),
      );
    });

    test('requires a full-length PRF output', () async {
      authenticator.prfLength = 16;
      await expectLater(check(), _fails(WalletAccessFailure.prfUnavailable));
    });
  });

  group('passkey method channel', () {
    const channel = MethodChannel('gleec.wallet/passkey');
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      messenger.setMockMessageHandler(channel.name, null);
    });

    PasskeyAssertionRequest request() => PasskeyAssertionRequest(
      rpId: passkeyRp,
      challenge: bytesOf(1),
      salt: bytesOf(2),
    );

    test('passes binary arguments and returns the assertion', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return {
          'credentialId': bytesOf(1, 16),
          'userHandle': null,
          'authenticatorData': bytesOf(2, 37),
          'clientDataJSON': bytesOf(3, 40),
          'signature': bytesOf(4, 70),
          'prf': bytesOf(5),
        };
      });
      final assertion = await MethodChannelPasskeyAuthenticator().getAssertion(
        request(),
      );
      final arguments = seen!.arguments as Map;
      expect(seen!.method, 'getAssertion');
      expect(arguments['salt'], bytesOf(2));
      expect(arguments['allowCredentials'], isEmpty);
      expect(assertion.userHandle, isNull);
      expect(assertion.prf, bytesOf(5));
    });

    test('owns wipeable PRF bytes from a read-only platform reply', () async {
      const codec = StandardMethodCodec();
      final reply = codec.encodeSuccessEnvelope({
        'credentialId': bytesOf(1, 16),
        'authenticatorData': bytesOf(2, 37),
        'clientDataJSON': bytesOf(3, 40),
        'signature': bytesOf(4, 70),
        'prf': bytesOf(5),
      }).asUnmodifiableView();
      messenger.setMockMessageHandler(channel.name, (_) async => reply);

      final assertion = await MethodChannelPasskeyAuthenticator().getAssertion(
        request(),
      );
      expect(assertion.prf, bytesOf(5));
      assertion.wipe();
      expect(assertion.prf, everyElement(0));
    });

    testWidgets('cancels a silent provider and permits a fresh retry', (
      tester,
    ) async {
      const codec = StandardMethodCodec();
      final originalReply = Completer<ByteData>();
      final completeReply = codec.encodeSuccessEnvelope({
        'credentialId': bytesOf(1, 16),
        'authenticatorData': bytesOf(2, 37),
        'clientDataJSON': bytesOf(3, 40),
        'signature': bytesOf(4, 70),
        'prf': bytesOf(5),
      });
      var requests = 0;
      var cancellations = 0;
      messenger.setMockMessageHandler(channel.name, (message) async {
        final call = codec.decodeMethodCall(message!);
        if (call.method == 'cancel') {
          cancellations++;
          return codec.encodeSuccessEnvelope(null);
        }
        requests++;
        return requests == 1 ? originalReply.future : completeReply;
      });
      final authenticator = MethodChannelPasskeyAuthenticator();
      final timedOut = expectLater(
        authenticator.getAssertion(request()),
        _fails(WalletAccessFailure.canceled),
      );
      await tester.pump(const Duration(minutes: 2));
      await timedOut;
      expect(cancellations, 1);

      originalReply.complete(completeReply.asUnmodifiableView());
      await tester.pump();
      final retry = await authenticator.getAssertion(request());
      expect(retry.prf, bytesOf(5));
      expect(requests, 2);
    });

    test('maps native failures without their details', () async {
      final expected = <String, WalletAccessFailure>{
        'canceled': WalletAccessFailure.canceled,
        'interrupted': WalletAccessFailure.canceled,
        'noCredential': WalletAccessFailure.passkeyNotFound,
        'prfUnavailable': WalletAccessFailure.prfUnavailable,
        'busy': WalletAccessFailure.busy,
        'something new': WalletAccessFailure.unavailable,
      };
      for (final MapEntry(:key, :value) in expected.entries) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: key, message: 'secret'),
        );
        await expectLater(
          MethodChannelPasskeyAuthenticator().getAssertion(request()),
          _fails(value),
          reason: key,
        );
      }
    });

    test('treats a reply without PRF output as unsupported', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'credentialId': bytesOf(1, 16),
          'authenticatorData': bytesOf(2, 37),
          'clientDataJSON': bytesOf(3, 40),
          'signature': bytesOf(4, 70),
        },
      );
      await expectLater(
        MethodChannelPasskeyAuthenticator().getAssertion(request()),
        _fails(WalletAccessFailure.prfUnavailable),
      );
    });

    test('reports no support without a bridge', () async {
      expect(await MethodChannelPasskeyAuthenticator().isSupported(), isFalse);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'available': true},
      );
      expect(await MethodChannelPasskeyAuthenticator().isSupported(), isTrue);
    });
  });

  test('constant-time comparison compares contents and length', () {
    expect(passkeyBytesEqual([1, 2], [1, 2]), isTrue);
    expect(passkeyBytesEqual([1, 2], [1, 3]), isFalse);
    expect(passkeyBytesEqual([1, 2], [1, 2, 3]), isFalse);
  });
}
