import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_bridge.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/security_key/security_key_prompts.dart';

import '../passkey_test_support.dart';

const _channel = MethodChannel('gleec.wallet/security_key');

void _answer(Future<Object?> Function(MethodCall call) handler) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);

Map<String, Object?> _assertion({Object? prf, Object? credentialId}) => {
  'credentialId': credentialId ?? bytesOf(1, 16),
  'userHandle': null,
  'userName': 'Wallet · 0123abcd',
  'userDisplayName': 'Wallet',
  'authenticatorData': bytesOf(2, 37),
  'signature': bytesOf(3, 70),
  'prf': prf,
};

/// An encoded reply, so the bridge decodes views into this very buffer.
ByteData _reply(List<Map<String, Object?>> assertions) =>
    const StandardMethodCodec().encodeSuccessEnvelope({
      'assertions': assertions,
    });

void _replyWith(ByteData reply) => TestDefaultBinaryMessengerBinding
    .instance
    .defaultBinaryMessenger
    .setMockMessageHandler(_channel.name, (_) async => reply);

Future<List<SecurityKeyCandidate>> _request(SecurityKeyBridge bridge) =>
    bridge.getAssertion(
      path: '/dev/hidraw3',
      rpId: passkeyRp,
      clientDataHash: bytesOf(5),
      salt: bytesOf(6),
      allowCredentials: const [],
      timeout: const Duration(minutes: 2),
    );

bool _holds(ByteData reply, Uint8List secret) {
  final bytes = reply.buffer.asUint8List(
    reply.offsetInBytes,
    reply.lengthInBytes,
  );
  for (var i = 0; i + secret.length <= bytes.length; i++) {
    var j = 0;
    while (j < secret.length && bytes[i + j] == secret[j]) {
      j++;
    }
    if (j == secret.length) return true;
  }
  return false;
}

Matcher _code(String code, {int? retries}) => throwsA(
  isA<SecurityKeyException>()
      .having((e) => e.code, 'code', code)
      .having((e) => e.retries, 'retries', retries),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bridge = MethodChannelSecurityKeyBridge();
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_channel, null)
      ..setMockMessageHandler(_channel.name, null);
  });

  group('security-key channel', () {
    test('is unavailable without the Linux bridge', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
      expect(await bridge.isAvailable(), isFalse);
      await expectLater(bridge.devices(), _code('unavailable'));
    });

    test('reads the key list', () async {
      _answer((call) async {
        expect(call.method, 'devices');
        return {
          'devices': [
            {
              'path': '/dev/hidraw3',
              'product': 'Maker Key',
              'state': 'ready',
              'hmacSecret': true,
              'pin': true,
              'uv': false,
              'pinRetries': 5,
              'uvRetries': -1,
            },
            {'path': '/dev/hidraw4', 'state': 'noAccess'},
          ],
        };
      });
      final [ready, blocked] = await bridge.devices();
      expect(ready.usable, isTrue);
      expect(ready.pinRetries, 5);
      expect(ready.uvRetries, isNull, reason: 'the bridge sends -1 for none');
      expect(blocked.state, SecurityKeyDeviceState.noAccess);
      expect(blocked.usable, isFalse);
    });

    test('sends the request as bytes, with no PIN for built-in UV', () async {
      late Map<Object?, Object?> sent;
      _answer((call) async {
        sent = call.arguments as Map<Object?, Object?>;
        return {
          'assertions': [_assertion(prf: bytesOf(9))],
        };
      });
      final [candidate] = await bridge.getAssertion(
        path: '/dev/hidraw3',
        rpId: passkeyRp,
        clientDataHash: bytesOf(5),
        salt: bytesOf(6),
        allowCredentials: [bytesOf(1, 16)],
        timeout: const Duration(minutes: 2),
      );
      expect(sent['clientDataHash'], isA<Uint8List>());
      expect(sent['allowCredentials'], [bytesOf(1, 16)]);
      expect(sent['pin'], isNull);
      expect(sent['timeoutMs'], 120000);
      expect(candidate.userHandle, isNull);
      expect(candidate.prf, bytesOf(9));
    });

    test('reports tries left after a wrong PIN', () async {
      _answer(
        (_) async => throw PlatformException(
          code: 'pinInvalid',
          details: {'retries': 3},
        ),
      );
      await expectLater(
        bridge.getAssertion(
          path: '/dev/hidraw3',
          rpId: passkeyRp,
          clientDataHash: bytesOf(5),
          salt: bytesOf(6),
          allowCredentials: const [],
          timeout: const Duration(minutes: 2),
          pin: Uint8List.fromList([0x31, 0x32, 0x33, 0x34]),
        ),
        _code('pinInvalid', retries: 3),
      );
    });

    test('a malformed answer is refused', () async {
      _answer(
        (_) async => {
          'assertions': [
            _assertion(prf: bytesOf(9)),
            _assertion(prf: bytesOf(9), credentialId: Uint8List(0)),
          ],
        },
      );
      await expectLater(
        bridge.getAssertion(
          path: '/dev/hidraw3',
          rpId: passkeyRp,
          clientDataHash: bytesOf(5),
          salt: bytesOf(6),
          allowCredentials: const [],
          timeout: const Duration(minutes: 2),
        ),
        _code('invalidResponse'),
      );
    });

    test('owns wipeable PRF bytes from a read-only reply', () async {
      _replyWith(_reply([_assertion(prf: bytesOf(9))]).asUnmodifiableView());
      final [candidate] = await _request(bridge);
      expect(candidate.prf, bytesOf(9));
      candidate.wipe();
      expect(candidate.prf, everyElement(0));
    });

    test('erases the reply buffer and keeps an owned copy', () async {
      final reply = _reply([_assertion(prf: bytesOf(9))]);
      expect(_holds(reply, bytesOf(9)), isTrue);
      _replyWith(reply);
      final [candidate] = await _request(bridge);
      expect(_holds(reply, bytesOf(9)), isFalse);
      expect(candidate.prf, bytesOf(9));
    });

    test('a malformed read-only reply is refused', () async {
      _replyWith(
        _reply([
          _assertion(prf: bytesOf(9)),
          _assertion(prf: bytesOf(9), credentialId: Uint8List(0)),
        ]).asUnmodifiableView(),
      );
      await expectLater(_request(bridge), _code('invalidResponse'));
    });
  });

  group('security-key prompts', () {
    test('a PIN nobody waits for is wiped', () {
      final prompts = SecurityKeyPrompts();
      final pin = Uint8List.fromList([0x31, 0x32, 0x33, 0x34]);
      prompts.answerPin(pin);
      expect(pin, everyElement(0));
    });

    test('an answer for another step is ignored', () async {
      final prompts = SecurityKeyPrompts()..attachHost();
      final pin = prompts.askPin();
      prompts
        ..answerAccount(0)
        ..retry();
      final typed = Uint8List.fromList([0x31, 0x32, 0x33, 0x34]);
      prompts.answerPin(typed);
      expect(await pin, same(typed));
    });

    test('a cancel answers the waiting step and is announced', () async {
      final prompts = SecurityKeyPrompts()..attachHost();
      var announced = 0;
      prompts.cancellations.listen((_) => announced++);
      final choice = prompts.chooseAccount(const [
        SecurityKeyAccount(usable: true),
      ]);
      prompts.cancel();
      expect(await choice, isNull);
      expect(announced, 1);
    });

    test('closing clears the sheet and nothing else can answer', () async {
      final prompts = SecurityKeyPrompts()..attachHost();
      final shown = <SecurityKeyPrompt?>[];
      prompts.changes.listen(shown.add);
      final retry = prompts.askRetry();
      prompts.close();
      expect(await retry, isFalse);
      await pumpEventQueue();
      expect(shown.last, isNull);
      expect(prompts.current, isNull);
    });

    test('with no host, a step that needs the user ends at once', () async {
      final prompts = SecurityKeyPrompts();
      expect(await prompts.askPin(), isNull);
      expect(await prompts.askRetry(), isFalse);
    });

    test('the last host to leave ends a request between steps', () async {
      final prompts = SecurityKeyPrompts()..attachHost();
      var announced = 0;
      prompts.cancellations.listen((_) => announced++);
      prompts.detachHost();
      expect(announced, 1, reason: 'nothing was on screen');
    });

    test('the last host to leave cancels what it showed', () async {
      final prompts = SecurityKeyPrompts()..attachHost();
      expect(prompts.hasHost, isTrue);
      final pin = prompts.askPin();
      prompts.detachHost();
      expect(prompts.hasHost, isFalse);
      expect(await pin, isNull);
    });
  });
}
