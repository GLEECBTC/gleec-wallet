part of 'backup_stores_test.dart';

const _clientId =
    '123456789012-abcdefghijklmnop0123456789abcdef.apps.googleusercontent.com';
const _scheme =
    'com.googleusercontent.apps.123456789012-abcdefghijklmnop0123456789abcdef';
const _driveScope = 'https://www.googleapis.com/auth/drive.appdata';
const _driveConfig = WalletTransferConfig(
  googleDriveEnabled: true,
  googleIosClientId: _clientId,
);

void _authorizerCases() {
  const channel = MethodChannel('test/google_drive_auth');
  late _Bridge bridge;
  late List<http.Request> posts;
  late http.Response Function(http.Request request) tokenReply;

  /// What Google sends back to the app's scheme for this sign-in.
  String Function(Uri request) callback = (_) => '';

  setUp(() {
    bridge = _Bridge(channel)
      ..reply = (call) => {
        'callbackUrl': callback(
          Uri.parse((call.arguments as Map)['url'] as String),
        ),
      };
    posts = [];
    callback = (request) =>
        '$_scheme:/oauth2redirect?state=${request.queryParameters['state']}'
        '&code=4%2Fcode&scope=${Uri.encodeQueryComponent(_driveScope)}';
    tokenReply = (_) => _json({
      'access_token': 'ya29.access-token',
      'expires_in': 3599,
      'refresh_token': '1//refresh-token',
      'scope': _driveScope,
      'token_type': 'Bearer',
    });
  });
  tearDown(() => bridge.detach());

  PlatformGoogleDriveAuthorizer authorizer({
    GoogleDriveAuthPlatform platform = GoogleDriveAuthPlatform.apple,
    WalletTransferConfig config = _driveConfig,
  }) => PlatformGoogleDriveAuthorizer(
    config: config,
    channel: channel,
    client: MockClient((request) async {
      posts.add(request);
      return tokenReply(request);
    }),
    random: Random(3),
    platform: platform,
  );

  test('runs the code flow with PKCE on Apple platforms', () async {
    expect(await authorizer().authorize(), 'ya29.access-token');

    final call = bridge.calls.single;
    expect(call.method, 'authorize');
    final arguments = call.arguments as Map;
    expect(arguments['callbackScheme'], _scheme);
    final url = Uri.parse(arguments['url'] as String);
    expect(
      '${url.origin}${url.path}',
      'https://accounts.google.com/o/oauth2/v2/auth',
    );
    final params = url.queryParameters;
    expect(params['client_id'], _clientId);
    expect(params['redirect_uri'], '$_scheme:/oauth2redirect');
    expect(params['response_type'], 'code');
    expect(params['scope'], _driveScope);
    expect(params['code_challenge_method'], 'S256');
    expect(params['state'], matches(RegExp(r'^[A-Za-z0-9_-]{32}$')));

    final exchange = posts.single;
    expect('${exchange.url}', 'https://oauth2.googleapis.com/token');
    final fields = exchange.bodyFields;
    expect(fields.keys.toSet(), {
      'client_id',
      'code',
      'code_verifier',
      'grant_type',
      'redirect_uri',
    });
    expect(fields['client_id'], _clientId);
    expect(fields['code'], '4/code');
    expect(fields['grant_type'], 'authorization_code');
    expect(fields['redirect_uri'], '$_scheme:/oauth2redirect');
    // RFC 7636: the challenge is the verifier's SHA-256, base64url, unpadded.
    final verifier = fields['code_verifier']!;
    expect(verifier, matches(RegExp(r'^[A-Za-z0-9._~-]{64}$')));
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    expect(params['code_challenge'], challenge);
  });

  test('uses a fresh verifier and state for every sign-in', () async {
    final google = authorizer();
    await google.authorize();
    await google.authorize();
    final [first, second] = [
      for (final call in bridge.calls)
        Uri.parse((call.arguments as Map)['url'] as String).queryParameters,
    ];
    expect(second['state'], isNot(first['state']));
    expect(second['code_challenge'], isNot(first['code_challenge']));
  });

  test('exchanges no code whose state does not match', () async {
    final forged = <String Function(Uri request)>[
      (_) => '$_scheme:/oauth2redirect?state=forged&code=4%2Fcode',
      (_) => '$_scheme:/oauth2redirect?code=4%2Fcode',
      (request) =>
          'evil.example:/oauth2redirect?state='
          '${request.queryParameters['state']}&code=4%2Fcode',
      (request) =>
          '$_scheme:/elsewhere?state=${request.queryParameters['state']}'
          '&code=4%2Fcode',
    ];
    for (final reply in forged) {
      callback = reply;
      await expectLater(
        authorizer().authorize(),
        _fails(PasskeyBackupFailure.storeUnavailable),
      );
    }
    expect(posts, isEmpty);
  });

  test('a declined consent or an unticked permission cancels', () async {
    callback = (request) =>
        '$_scheme:/oauth2redirect?state=${request.queryParameters['state']}'
        '&error=access_denied';
    await expectLater(
      authorizer().authorize(),
      _fails(PasskeyBackupFailure.canceled),
    );
    expect(posts, isEmpty);

    callback = (request) =>
        '$_scheme:/oauth2redirect?state=${request.queryParameters['state']}'
        '&code=4%2Fcode';
    tokenReply = (_) => _json({
      'access_token': 'ya29.access-token',
      'scope': 'openid email',
      'token_type': 'Bearer',
    });
    await expectLater(
      authorizer().authorize(),
      _fails(PasskeyBackupFailure.canceled),
    );

    bridge.reply = (_) => throw PlatformException(code: 'canceled');
    await expectLater(
      authorizer().authorize(),
      _fails(PasskeyBackupFailure.canceled),
    );
    bridge.calls.clear();
    bridge.reply = (_) => throw PlatformException(code: 'busy');
    await expectLater(
      authorizer().authorize(),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
    expect(bridge.calls, hasLength(1));
  });

  test('refuses a failed or malformed token exchange', () async {
    final replies = [
      http.Response('{"error":"invalid_grant"}', 400),
      http.Response('not json', 200),
      _json({'token_type': 'Bearer'}),
      _json({'access_token': 'two words', 'token_type': 'Bearer'}),
      _json({'access_token': 'ya29.x\r\nX-Evil: 1'}),
      _json({'access_token': 'ya29.x', 'token_type': 'mac'}),
    ];
    for (final reply in replies) {
      tokenReply = (_) => reply;
      await expectLater(
        authorizer().authorize(),
        _fails(PasskeyBackupFailure.storeUnavailable),
      );
    }
  });

  test('Android asks Play services for the token', () async {
    bridge.reply = (_) => {'accessToken': 'ya29.android-token'};
    final google = authorizer(platform: GoogleDriveAuthPlatform.android);
    expect(await google.isAvailable(), isTrue);
    expect(await google.authorize(), 'ya29.android-token');
    expect(bridge.calls.single.method, 'authorize');
    expect(bridge.calls.single.arguments, isNull);
    expect(posts, isEmpty);

    bridge.reply = (_) => {'accessToken': 42};
    await expectLater(
      google.authorize(),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
    bridge.reply = (_) => throw PlatformException(code: 'canceled');
    await expectLater(
      google.authorize(),
      _fails(PasskeyBackupFailure.canceled),
    );
    bridge.calls.clear();
    bridge.reply = (_) => throw PlatformException(code: 'busy');
    await expectLater(
      google.authorize(),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
    // Another sign-in is open: never asked again on its own.
    expect(bridge.calls, hasLength(1));
    bridge.detach();
    await expectLater(
      google.authorize(),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
  });

  test('is unavailable unless the build configures this platform', () async {
    final unavailable = [
      authorizer(config: const WalletTransferConfig(googleDriveEnabled: true)),
      authorizer(
        config: const WalletTransferConfig(
          googleDriveEnabled: true,
          googleIosClientId: 'not-a-client-id',
        ),
      ),
      authorizer(
        config: const WalletTransferConfig(googleIosClientId: _clientId),
      ),
      authorizer(
        platform: GoogleDriveAuthPlatform.android,
        config: const WalletTransferConfig(),
      ),
      authorizer(platform: GoogleDriveAuthPlatform.unsupported),
    ];
    for (final google in unavailable) {
      expect(await google.isAvailable(), isFalse);
      await expectLater(
        google.authorize(),
        _fails(PasskeyBackupFailure.storeUnavailable),
      );
    }
    expect(bridge.calls, isEmpty);
    expect(posts, isEmpty);
  });
}
