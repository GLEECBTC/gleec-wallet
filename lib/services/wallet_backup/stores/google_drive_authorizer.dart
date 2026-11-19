import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../wallet_access/platform/passkey/passkey_envelope.dart';
import '../../wallet_transfer/wallet_transfer_config.dart';
import '../passkey_backup_types.dart';

/// Grants access to the app's own hidden folder in the user's Google Drive.
abstract interface class GoogleDriveAuthorizer {
  /// Whether this build can ask at all. Never prompts.
  Future<bool> isAvailable();

  /// A bearer token for the app data folder, held in memory by the caller
  /// and never stored. Throws [PasskeyBackupException].
  Future<String> authorize();
}

enum GoogleDriveAuthPlatform {
  android,
  apple,
  unsupported;

  static GoogleDriveAuthPlatform get current {
    if (kIsWeb) return unsupported;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => android,
      TargetPlatform.iOS || TargetPlatform.macOS => apple,
      _ => unsupported,
    };
  }
}

/// Android asks Google Play services, which knows the app by its package
/// and signing certificate. Apple platforms run the OAuth code flow with
/// PKCE in the system sign-in sheet, as an installed app without a secret.
final class PlatformGoogleDriveAuthorizer implements GoogleDriveAuthorizer {
  PlatformGoogleDriveAuthorizer({
    required this._config,
    MethodChannel? channel,
    http.Client? client,
    Random? random,
    GoogleDriveAuthPlatform? platform,
    this._timeout = const Duration(seconds: 30),
  }) : _channel =
           channel ?? const MethodChannel('gleec.wallet/google_drive_auth'),
       _client = client ?? http.Client(),
       _random = random ?? Random.secure(),
       _platform = platform ?? GoogleDriveAuthPlatform.current;

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static final _clientId = RegExp(
    r'^([0-9]+-[a-z0-9]+)\.apps\.googleusercontent\.com$',
  );
  static final _accessToken = RegExp(r'^[A-Za-z0-9._~+/-]{1,4096}=*$');
  static final _tokenEndpoint = Uri.parse(
    'https://oauth2.googleapis.com/token',
  );

  final WalletTransferConfig _config;
  final MethodChannel _channel;
  final http.Client _client;
  final Random _random;
  final GoogleDriveAuthPlatform _platform;
  final Duration _timeout;

  /// An iOS client's redirect scheme is its id reversed.
  String? get _redirectScheme {
    final match = _clientId.firstMatch(_config.googleIosClientId);
    return match == null ? null : 'com.googleusercontent.apps.${match[1]}';
  }

  @override
  Future<bool> isAvailable() async =>
      _config.googleDriveEnabled &&
      switch (_platform) {
        GoogleDriveAuthPlatform.android => true,
        GoogleDriveAuthPlatform.apple => _redirectScheme != null,
        GoogleDriveAuthPlatform.unsupported => false,
      };

  @override
  Future<String> authorize() async {
    if (!await isAvailable()) throw _unavailable;
    if (_platform == GoogleDriveAuthPlatform.android) {
      final result = await _invoke('authorize');
      return _checkedToken(result?['accessToken']);
    }
    return _authorizeWithCode();
  }

  Future<String> _authorizeWithCode() async {
    final clientId = _config.googleIosClientId;
    final scheme = _redirectScheme!;
    final redirectUri = '$scheme:/oauth2redirect';
    // 48 bytes encode to exactly 64 unreserved characters (RFC 7636).
    final verifier = _urlSafe(48);
    final state = _urlSafe(24);
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': scope,
      'code_challenge': _challenge(verifier),
      'code_challenge_method': 'S256',
      'state': state,
    });
    final result = await _invoke('authorize', {
      'url': url.toString(),
      'callbackScheme': scheme,
    });
    final code = _code(result?['callbackUrl'], scheme, state);
    return _exchange(clientId, code, verifier, redirectUri);
  }

  /// The callback carries the code only after its state proves it answers
  /// this request; another app or page cannot inject one.
  String _code(Object? callback, String scheme, String state) {
    if (callback is! String || callback.length > 8192) throw _unavailable;
    final Uri uri;
    try {
      uri = Uri.parse(callback);
    } on FormatException {
      throw _unavailable;
    }
    if (uri.scheme != scheme || uri.path != '/oauth2redirect') {
      throw _unavailable;
    }
    final params = uri.queryParameters;
    final returned = params['state'];
    if (returned == null ||
        !passkeyBytesEqual(utf8.encode(returned), utf8.encode(state))) {
      throw _unavailable;
    }
    if (params['error'] == 'access_denied') throw _canceled;
    final code = params['code'];
    if (params.containsKey('error') ||
        code == null ||
        code.isEmpty ||
        code.length > 2048) {
      throw _unavailable;
    }
    return code;
  }

  Future<String> _exchange(
    String clientId,
    String code,
    String verifier,
    String redirectUri,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            _tokenEndpoint,
            body: {
              'client_id': clientId,
              'code': code,
              'code_verifier': verifier,
              'grant_type': 'authorization_code',
              'redirect_uri': redirectUri,
            },
          )
          .timeout(_timeout);
    } on Object {
      throw _unavailable;
    }
    if (response.statusCode != 200 || response.bodyBytes.length > 65536) {
      throw _unavailable;
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object {
      throw _unavailable;
    }
    if (json is! Map) throw _unavailable;
    final type = json['token_type'];
    if (type is String && type.toLowerCase() != 'bearer') throw _unavailable;
    // Google lets the user untick the Drive permission and still sign in.
    final granted = json['scope'];
    if (granted is String && !granted.split(' ').contains(scope)) {
      throw _canceled;
    }
    // A refresh token would reach the folder later without asking; it is
    // dropped unread.
    return _checkedToken(json['access_token']);
  }

  Future<Map<Object?, Object?>?> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>(
        method,
        arguments,
      );
    } on MissingPluginException {
      throw _unavailable;
    } on PlatformException catch (error) {
      throw error.code == 'canceled' ? _canceled : _unavailable;
    }
  }

  static String _checkedToken(Object? token) {
    if (token is! String || !_accessToken.hasMatch(token)) throw _unavailable;
    return token;
  }

  String _urlSafe(int length) {
    final bytes = Uint8List.fromList(
      List.generate(length, (_) => _random.nextInt(256)),
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _challenge(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  static const _unavailable = PasskeyBackupException(
    PasskeyBackupFailure.storeUnavailable,
  );
  static const _canceled = PasskeyBackupException(
    PasskeyBackupFailure.canceled,
  );
}
