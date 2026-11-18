import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_assertion_check.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_authenticator.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/linux_security_key_authenticator.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_bridge.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_prompts.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

import '../passkey_test_support.dart';
import 'security_key_test_support.dart';

part 'linux_security_key_flow_cases.dart';

Matcher _fails(WalletAccessFailure failure) => throwsA(
  isA<WalletAccessException>().having((e) => e.failure, 'failure', failure),
);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

final _counting = Uint8List.fromList(List.generate(32, (i) => i));

class _Rig {
  _Rig() {
    script = PromptScript(prompts)..pins.add('1234');
  }

  final bridge = FakeSecurityKeyBridge();
  final prompts = SecurityKeyPrompts();
  late PromptScript script;
  late final authenticator = LinuxSecurityKeyAuthenticator(
    bridge: bridge,
    prompts: prompts,
    pollInterval: Duration.zero,
    timeout: const Duration(seconds: 5),
  );

  PasskeyAssertionRequest request({List<Uint8List> allow = const []}) =>
      PasskeyAssertionRequest(
        rpId: passkeyRp,
        challenge: bytesOf(3),
        salt: bytesOf(4),
        allowCredentials: allow,
      );

  Future<PasskeyAssertion> assertion({List<Uint8List> allow = const []}) =>
      authenticator.getAssertion(request(allow: allow));
}

void main() {
  group('WebAuthn PRF over hmac-secret', () {
    test('transforms the salt as browsers do', () {
      // Computed independently with Python's hashlib.
      expect(
        _hex(webAuthnPrfSalt(_counting)),
        'dc1f4f3b3d759586245d5de7e2e115d2a056a2df27109db7cef9b4b3a89bb106',
      );
    });

    test('composes the client data the Windows bridge composes', () {
      final clientData = securityKeyClientData(passkeyRp, _counting);
      expect(
        utf8.decode(clientData),
        '{"type":"webauthn.get",'
        '"challenge":"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",'
        '"origin":"https://dex.gleec.com","crossOrigin":false}',
      );
      expect(
        sha256.convert(clientData).toString(),
        '1683887f94a3f0ff81bec2900c4147f645116212414a709feca8f1830e0a859e',
      );
    });
  });

  group('Linux security-key authenticator', () {
    late _Rig rig;
    setUp(() => rig = _Rig());
    tearDown(() => rig.script.dispose());

    test(
      'a PIN and a touch give an assertion the shared checks accept',
      () async {
        final request = rig.request();
        final assertion = await rig.authenticator.getAssertion(request);

        checkPasskeyAssertion(assertion, request);
        final call = rig.bridge.calls.single;
        expect(call.salt, webAuthnPrfSalt(request.salt));
        expect(
          call.clientDataHash,
          sha256.convert(assertion.clientDataJson).bytes,
        );
        expect(call.pinText, '1234');
        expect(call.pin, everyElement(0), reason: 'wiped once sent');
        expect(assertion.prf, bytesOf(51));
        expect(rig.script.stages, [
          SecurityKeyStage.enterPin,
          SecurityKeyStage.touch,
        ]);
        expect(rig.prompts.current, isNull, reason: 'the sheet closes');
      },
    );

    test('asks again after a wrong PIN, with the tries left', () async {
      rig.script.pins.add('5678');
      rig.bridge.answers.add(
        const SecurityKeyException('pinInvalid', retries: 2),
      );
      await rig.assertion();

      expect([for (final c in rig.bridge.calls) c.pinText], ['1234', '5678']);
      final second = rig.script.shown.where(
        (p) => p.stage == SecurityKeyStage.enterPin,
      );
      expect(second.last.wrongPin, isTrue);
      expect(second.last.retriesLeft, 2);
    });

    test(
      'a key that refuses more PINs is reinserted, then asked again',
      () async {
        rig.script.pins.add('1234');
        rig.bridge.answers.add(const SecurityKeyException('pinAuthBlocked'));
        rig.bridge.deviceLists
          ..clear()
          ..addAll([
            [securityKey(0)],
            [securityKey(0)],
            [],
            [],
            [securityKey(1)],
          ]);
        await rig.assertion();

        expect(rig.script.stages, contains(SecurityKeyStage.reinsert));
        expect(rig.script.stages, contains(SecurityKeyStage.insert));
        expect(rig.bridge.calls.last.path, '/dev/hidraw1');
      },
    );

    test('a blocked PIN locks the request out', () async {
      rig.bridge.answers.add(const SecurityKeyException('pinBlocked'));
      await expectLater(rig.assertion(), _fails(WalletAccessFailure.lockedOut));
    });

    test('no tries left means no PIN is asked for', () async {
      rig.bridge.deviceLists.first = [securityKey(0, pinRetries: 0)];
      await expectLater(rig.assertion(), _fails(WalletAccessFailure.lockedOut));
      expect(rig.script.stages, isNot(contains(SecurityKeyStage.enterPin)));
      expect(rig.bridge.calls, isEmpty);
    });

    test('waits for a key to be inserted', () async {
      rig.bridge.deviceLists
        ..clear()
        ..addAll([
          [],
          [],
          [securityKey(0)],
        ]);
      await rig.assertion();
      expect(rig.script.stages.first, SecurityKeyStage.insert);
    });

    test('a cancel while waiting for a key stops the request', () async {
      rig.bridge.deviceLists.first = [];
      rig.script.onShown = (prompt) => rig.prompts.cancel();
      await expectLater(rig.assertion(), _fails(WalletAccessFailure.canceled));
      expect(rig.bridge.cancels, 1);
    });

    test('says when the session may not open the key', () async {
      rig.bridge.deviceLists.first = [
        securityKey(0, state: SecurityKeyDeviceState.noAccess),
      ];
      rig.script.onShown = (prompt) => rig.prompts.cancel();
      await expectLater(rig.assertion(), _fails(WalletAccessFailure.canceled));
      expect(rig.script.stages, [SecurityKeyStage.noAccess]);
    });

    test('with several keys, the one touched is the one used', () async {
      rig.bridge.deviceLists.first = [securityKey(0), securityKey(1)];
      rig.bridge.selection = '/dev/hidraw1';
      await rig.assertion();
      expect(rig.bridge.selections.single, ['/dev/hidraw0', '/dev/hidraw1']);
      expect(rig.script.stages.first, SecurityKeyStage.chooseKey);
      expect(rig.bridge.calls.single.path, '/dev/hidraw1');
    });

    test('a key that cannot evaluate hmac-secret is refused', () async {
      rig.bridge.deviceLists.first = [securityKey(0, hmacSecret: false)];
      await expectLater(
        rig.assertion(),
        _fails(WalletAccessFailure.prfUnavailable),
      );
      expect(rig.script.stages, isEmpty);
    });

    _flowCases(() => rig);
  });
}
