part of 'passkey_registration_test.dart';

void _channelTests() {
  const channel = MethodChannel('gleec.wallet/passkey');
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<String, Object?> reply() => {
    'credentialId': bytesOf(1, 16),
    'clientDataJSON': bytesOf(2, 80),
    'attestationObject': bytesOf(3, 120),
    'prfFirst': bytesOf(4),
    'transports': ['internal', 'hybrid'],
  };

  void answer(Object? Function(MethodCall call) handler) => messenger
      .setMockMethodCallHandler(channel, (call) async => handler(call));

  test('sends the request and returns what the platform made', () async {
    MethodCall? seen;
    answer((call) {
      seen = call;
      return reply();
    });
    final registration = await MethodChannelPasskeyRegistrar().register(
      _request,
    );
    expect(seen!.method, 'register');
    expect(seen!.arguments, {
      'rpId': registrationRp,
      'challenge': bytesOf(11),
      'userId': bytesOf(12),
      'userName': 'Gleec Wallet recovery',
      'displayName': 'Gleec Wallet recovery – Savings',
      'prfSalt': bytesOf(13),
      'timeoutMs': 120000,
    });
    expect(registration.credentialId, bytesOf(1, 16));
    expect(registration.clientDataJson, bytesOf(2, 80));
    expect(registration.attestationObject, bytesOf(3, 120));
    expect(registration.prfOutput, bytesOf(4));
    expect(registration.transports, ['internal', 'hybrid']);
  });

  test('refuses what the bridge would refuse, before asking it', () async {
    var calls = 0;
    answer((_) {
      calls++;
      return reply();
    });
    PasskeyRegistrationRequest request({
      String rpId = registrationRp,
      int challenge = 16,
      int userId = 64,
      String userName = 'Gleec Wallet recovery',
      String displayName = 'Gleec Wallet recovery – Savings',
      int prfSalt = 32,
    }) => PasskeyRegistrationRequest(
      rpId: rpId,
      challenge: bytesOf(11, challenge),
      userId: bytesOf(12, userId),
      userName: userName,
      displayName: displayName,
      prfSalt: bytesOf(13, prfSalt),
    );
    final refused = <String, PasskeyRegistrationRequest>{
      'no relying party': request(rpId: ''),
      'a relying party over 253 characters': request(rpId: 'a' * 254),
      'a short challenge': request(challenge: 15),
      'no user id': request(userId: 0),
      'a user id over 64 bytes': request(userId: 65),
      'no user name': request(userName: ''),
      'a user name over 1,024 bytes': request(userName: 'é' * 513),
      'no display name': request(displayName: ''),
      'a display name over 1,024 bytes': request(displayName: 'x' * 1025),
      'a short PRF salt': request(prfSalt: 31),
      'a long PRF salt': request(prfSalt: 33),
    };
    for (final MapEntry(:key, :value) in refused.entries) {
      await expectLater(
        MethodChannelPasskeyRegistrar().register(value),
        _invalid,
        reason: key,
      );
    }
    expect(calls, 0);
    // Each limit itself is allowed.
    await MethodChannelPasskeyRegistrar().register(
      request(
        rpId: 'a' * 253,
        userId: 1,
        userName: 'é' * 512,
        displayName: 'x' * 1024,
      ),
    );
    expect(calls, 1);
  });

  test('takes a reply without PRF output or transports', () async {
    answer((_) => {...reply(), 'prfFirst': null}..remove('transports'));
    final registration = await MethodChannelPasskeyRegistrar().register(
      _request,
    );
    expect(registration.prfOutput, isNull);
    expect(registration.transports, isEmpty);
    answer((_) => {...reply()}..remove('prfFirst'));
    expect(
      (await MethodChannelPasskeyRegistrar().register(_request)).prfOutput,
      isNull,
    );
  });

  test('refuses a malformed reply', () async {
    final replies = <String, Object?>{
      'nothing': null,
      'a list': [1],
      'no credential': {...reply()}..remove('credentialId'),
      'empty attestation': {...reply(), 'attestationObject': Uint8List(0)},
      'text client data': {...reply(), 'clientDataJSON': '{}'},
      'PRF as a list': {
        ...reply(),
        'prfFirst': [1, 2],
      },
      'transports as text': {...reply(), 'transports': 'internal'},
      'a numeric transport': {
        ...reply(),
        'transports': [1],
      },
    };
    for (final MapEntry(:key, :value) in replies.entries) {
      answer((_) => value);
      await expectLater(
        MethodChannelPasskeyRegistrar().register(_request),
        _invalid,
        reason: key,
      );
    }
  });

  test('maps native failures without their details', () async {
    final expected = <String, WalletAccessFailure>{
      'canceled': WalletAccessFailure.canceled,
      'busy': WalletAccessFailure.busy,
      'prfUnavailable': WalletAccessFailure.prfUnavailable,
      'invalidResponse': WalletAccessFailure.invalidResponse,
      'unavailable': WalletAccessFailure.unavailable,
      'something new': WalletAccessFailure.unavailable,
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      answer((_) => throw PlatformException(code: key, message: 'secret'));
      await expectLater(
        MethodChannelPasskeyRegistrar().register(_request),
        _fails(value),
        reason: key,
      );
    }
    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      MethodChannelPasskeyRegistrar().register(_request),
      _fails(WalletAccessFailure.unavailable),
    );
  });

  test('reports a removed passkey and cancels at best effort', () async {
    final calls = <MethodCall>[];
    answer((call) {
      calls.add(call);
      throw PlatformException(code: 'unavailable');
    });
    final registrar = MethodChannelPasskeyRegistrar();
    await registrar.reportRemoved(
      rpId: registrationRp,
      credentialId: bytesOf(1, 16),
    );
    await registrar.cancel();
    expect(calls.map((call) => call.method), ['reportRemoved', 'cancel']);
    expect(calls.first.arguments, {
      'rpId': registrationRp,
      'credentialId': bytesOf(1, 16),
    });
    messenger.setMockMethodCallHandler(channel, null);
    await registrar.reportRemoved(
      rpId: registrationRp,
      credentialId: bytesOf(1, 16),
    );
    await registrar.cancel();
  });

  test('reports support only when the bridge says so', () async {
    final registrar = MethodChannelPasskeyRegistrar();
    expect(await registrar.isSupported(), isFalse);
    answer((_) => {'available': true});
    expect(await registrar.isSupported(), isTrue);
    answer((_) => {'available': false});
    expect(await registrar.isSupported(), isFalse);
    answer((_) => throw PlatformException(code: 'unavailable'));
    expect(await registrar.isSupported(), isFalse);
  });
}

void _providerNameTests() {
  test('names well-known passkey providers only', () {
    const known = {
      'ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4': 'Google Password Manager',
      'fbfc3007-154e-4ecc-8c0b-6e020557d7bd': 'Apple Passwords',
      'bada5566-a7aa-401f-bd96-45619a55120d': '1Password',
      '50726f74-6f6e-5061-7373-50726f746f6e': 'Proton Pass',
      'd548826e-79b4-db40-a3d8-11116f7e8349': 'Bitwarden',
      '531126d6-e717-415c-9320-3d9aa6981239': 'Dashlane',
      '53414d53-554e-4700-0000-000000000000': 'Samsung Pass',
      '0ea242b4-43c4-4a1b-8b17-dd6d0b6baec6': 'Keeper',
    };
    for (final MapEntry(:key, :value) in known.entries) {
      expect(passkeyProviderName(key), value);
      expect(passkeyProviderName(key.toUpperCase()), value);
    }
    expect(passkeyProviderName(null), isNull);
    expect(passkeyProviderName('00000000-0000-0000-0000-000000000001'), isNull);
  });
}
