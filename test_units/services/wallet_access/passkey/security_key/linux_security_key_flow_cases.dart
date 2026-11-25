part of 'linux_security_key_authenticator_test.dart';

void _flowCases(_Rig Function() rigOf) {
  test('built-in verification needs no PIN', () async {
    final rig = rigOf();
    rig.bridge.deviceLists.first = [
      securityKey(0, pin: false, uv: true, uvRetries: 3),
    ];
    await rig.assertion();
    expect(rig.bridge.calls.single.pin, isNull);
    expect(rig.script.stages, [SecurityKeyStage.touch]);
  });

  test('blocked built-in verification falls back to the PIN', () async {
    final rig = rigOf();
    rig.bridge.deviceLists.first = [securityKey(0, uv: true, uvRetries: 3)];
    rig.bridge.answers.add(const SecurityKeyException('uvBlocked'));
    await rig.assertion();
    expect([for (final c in rig.bridge.calls) c.pinText], [null, '1234']);
  });

  test(
    'a key with neither PIN nor fingerprint holds no such passkey',
    () async {
      final rig = rigOf();
      rig.bridge.deviceLists.first = [securityKey(0, pin: false)];
      await expectLater(
        rig.assertion(),
        _fails(WalletAccessFailure.passkeyNotFound),
      );
    },
  );

  test('the user picks among several passkeys; the rest are wiped', () async {
    final rig = rigOf();
    final first = keyCandidate(1);
    final second = keyCandidate(2);
    rig.bridge.answers.add([first, second]);
    rig.script.account = 1;
    final assertion = await rig.assertion();

    expect(assertion.credentialId, second.credentialId);
    expect(first.prf, everyElement(0));
    final choice = rig.script.shown.singleWhere(
      (p) => p.stage == SecurityKeyStage.chooseAccount,
    );
    expect(choice.accounts.map((a) => a.displayName), ['Wallet 1', 'Wallet 2']);
  });

  test('declining the choice wipes every answer', () async {
    final rig = rigOf();
    final answers = [keyCandidate(1), keyCandidate(2)];
    rig.bridge.answers.add(answers);
    await expectLater(rig.assertion(), _fails(WalletAccessFailure.canceled));
    for (final candidate in answers) {
      expect(candidate.prf, everyElement(0));
    }
  });

  test('a passkey without PRF output cannot unlock', () async {
    final rig = rigOf();
    rig.bridge.answers.add([keyCandidate(1, prf: false)]);
    await expectLater(
      rig.assertion(),
      _fails(WalletAccessFailure.prfUnavailable),
    );
  });

  test('no touch: trying again asks for the PIN again', () async {
    final rig = rigOf();
    rig.script
      ..retry = true
      ..pins.add('1234');
    rig.bridge.answers.add(const SecurityKeyException('timeout'));
    await rig.assertion();
    expect(rig.script.stages, contains(SecurityKeyStage.timedOut));
    expect(rig.bridge.calls, hasLength(2));
  });

  test('no touch and no retry is a cancel', () async {
    final rig = rigOf();
    rig.bridge.answers.add(const SecurityKeyException('timeout'));
    await expectLater(rig.assertion(), _fails(WalletAccessFailure.canceled));
  });

  test('a cancel during the touch wins over a late answer', () async {
    final rig = rigOf();
    final late = keyCandidate(1);
    rig.bridge
      ..hold = Completer<void>()
      ..answers.add([late]);
    rig.script.onShown = (prompt) {
      if (prompt.stage == SecurityKeyStage.enterPin) {
        rig.prompts.answerPin(Uint8List.fromList(utf8.encode('1234')));
      } else if (prompt.stage == SecurityKeyStage.touch) {
        unawaited(rig.authenticator.cancel());
      }
    };
    final pending = rig.assertion();
    await pumpEventQueue();
    rig.bridge.hold!.complete();
    await expectLater(pending, _fails(WalletAccessFailure.canceled));
    expect(rig.bridge.cancels, 1);
    expect(late.prf, everyElement(0));
  });

  test('a cancel from outside ends a step waiting on the user', () async {
    final rig = rigOf();
    rig.script.onShown = (_) {};
    final pending = rig.assertion();
    await pumpEventQueue();
    expect(rig.prompts.current?.stage, SecurityKeyStage.enterPin);
    await rig.authenticator.cancel();
    await expectLater(pending, _fails(WalletAccessFailure.canceled));
    expect(rig.bridge.calls, isEmpty);
  });

  test('a PIN that a cancel overtakes is wiped unsent', () async {
    final rig = rigOf();
    final typed = Uint8List.fromList(utf8.encode('1234'));
    rig.script.onShown = (prompt) {
      if (prompt.stage != SecurityKeyStage.enterPin) return;
      rig.prompts.answerPin(typed);
      unawaited(rig.authenticator.cancel());
    };
    await expectLater(rig.assertion(), _fails(WalletAccessFailure.canceled));
    expect(typed, everyElement(0));
    expect(rig.bridge.calls, isEmpty);
  });

  test('a sheet that goes away between steps ends the request', () async {
    final rig = rigOf();
    final pending = rig.assertion();
    await rig.script.dispose();
    await expectLater(pending, _fails(WalletAccessFailure.canceled));
    rig.script = PromptScript(rig.prompts);
  });

  test('the shared failure codes come through', () async {
    final rig = rigOf();
    rig.bridge.answers.add(const SecurityKeyException('noCredential'));
    await expectLater(
      rig.assertion(allow: [bytesOf(1, 16)]),
      _fails(WalletAccessFailure.passkeyNotFound),
    );
    rig.script.pins.add('1234');
    rig.bridge.answers.add(const SecurityKeyException('busy'));
    await expectLater(rig.assertion(), _fails(WalletAccessFailure.busy));
    rig.bridge.devicesError = const SecurityKeyException('unavailable');
    await expectLater(rig.assertion(), _fails(WalletAccessFailure.unavailable));
  });

  test('one request at a time', () async {
    final rig = rigOf();
    rig.bridge.hold = Completer<void>();
    final first = rig.assertion();
    await pumpEventQueue();
    await expectLater(rig.assertion(), _fails(WalletAccessFailure.busy));
    rig.bridge.hold!.complete();
    await first;
  });

  test('without the sheet mounted there is no way to ask', () async {
    final rig = rigOf();
    await rig.script.dispose();
    await expectLater(rig.assertion(), _fails(WalletAccessFailure.unavailable));
    rig.script = PromptScript(rig.prompts);
    expect(rig.bridge.calls, isEmpty);
  });

  test('refuses a relying party that is not a host name', () async {
    final rig = rigOf();
    await expectLater(
      rig.authenticator.getAssertion(
        PasskeyAssertionRequest(
          rpId: 'dex.gleec.com","origin":"x',
          challenge: bytesOf(3),
          salt: bytesOf(4),
        ),
      ),
      _fails(WalletAccessFailure.unavailable),
    );
  });

  test('is supported only where the bridge loaded libfido2', () async {
    final rig = rigOf();
    expect(await rig.authenticator.isSupported(), isTrue);
    rig.bridge.available = false;
    expect(await rig.authenticator.isSupported(), isFalse);
  });
}
