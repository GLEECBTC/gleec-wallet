import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../wallet_access_types.dart';
import 'passkey_assertion_check.dart';
import 'passkey_authenticator.dart';
import 'passkey_envelope.dart';
import 'passkey_registration_types.dart';

part 'passkey_registration_cbor.dart';

/// The native bridge on iOS, macOS and Android. It shares the assertion
/// channel, so one `cancel` ends whichever prompt is open.
final class MethodChannelPasskeyRegistrar implements PasskeyRegistrar {
  MethodChannelPasskeyRegistrar({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('gleec.wallet/passkey');

  final MethodChannel _channel;

  @override
  Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('support');
      return result?['available'] == true;
    } on Object {
      return false;
    }
  }

  @override
  Future<PasskeyRegistration> register(
    PasskeyRegistrationRequest request,
  ) async {
    if (!_acceptable(request)) _invalid();
    final Object? result;
    try {
      result = await _channel.invokeMethod<Object?>('register', {
        'rpId': request.rpId,
        'challenge': request.challenge,
        'userId': request.userId,
        'userName': request.userName,
        'displayName': request.displayName,
        'prfSalt': request.prfSalt,
        'timeoutMs': 120000,
      });
    } on MissingPluginException {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    } on PlatformException catch (error) {
      throw WalletAccessException(passkeyChannelFailure(error.code));
    }
    final reply = switch (result) {
      final Map<Object?, Object?> map => map,
      _ => _invalid(),
    };
    Uint8List bytes(String name) => switch (reply[name]) {
      final Uint8List value when value.isNotEmpty => value,
      _ => _invalid(),
    };
    final prf = reply['prfFirst'];
    final transports = reply['transports'] ?? const <Object?>[];
    if ((prf != null && prf is! Uint8List) ||
        transports is! List ||
        transports.any((value) => value is! String)) {
      _invalid();
    }
    return PasskeyRegistration(
      credentialId: bytes('credentialId'),
      clientDataJson: bytes('clientDataJSON'),
      attestationObject: bytes('attestationObject'),
      prfOutput: prf as Uint8List?,
      transports: List.unmodifiable(transports.cast<String>()),
    );
  }

  @override
  Future<void> reportRemoved({
    required String rpId,
    required Uint8List credentialId,
  }) async {
    try {
      await _channel.invokeMethod<void>('reportRemoved', {
        'rpId': rpId,
        'credentialId': credentialId,
      });
    } on Object {
      // Best effort: older systems have no such signal.
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on Object {
      // Nothing is pending, or the platform has no bridge.
    }
  }

  /// The limits the native bridges enforce, so a request they would refuse
  /// never reaches the OS.
  static bool _acceptable(PasskeyRegistrationRequest request) {
    bool name(String value) {
      final length = utf8.encode(value).length;
      return length > 0 && length <= 1024;
    }

    return request.rpId.isNotEmpty &&
        request.rpId.length <= 253 &&
        request.challenge.length >= 16 &&
        request.userId.isNotEmpty &&
        request.userId.length <= 64 &&
        name(request.userName) &&
        name(request.displayName) &&
        request.prfSalt.length == PasskeyEnvelope.saltLength;
  }
}

/// Checks a new passkey without verifying its attestation: "none" is asked
/// for, and no key from it is trusted. What must hold is that the platform
/// made this credential for [request]'s relying party, after verifying the
/// user, in answer to this challenge. The flags that say whether it syncs
/// come from the authenticator data; the AAGUID only names the provider.
RegisteredPasskey checkPasskeyRegistration(
  PasskeyRegistration registration,
  PasskeyRegistrationRequest request,
) {
  final id = registration.credentialId;
  final prf = registration.prfOutput;
  if (id.isEmpty ||
      id.length > _maxCredentialIdLength ||
      (prf != null && prf.length != PasskeyEnvelope.prfLength)) {
    _invalid();
  }
  _checkClientData(registration.clientDataJson, request);
  final _AuthData data;
  try {
    data = _AuthData.parse(
      _authData(registration.attestationObject),
      request.rpId,
      id,
    );
  } on Object {
    _invalid();
  }
  return RegisteredPasskey(
    credentialId: Uint8List.fromList(id),
    backupEligible: data.backupEligible,
    backupState: data.backupState,
    transports: passkeyTransports(registration.transports),
    aaguid: data.aaguid,
    // The same buffer, so wiping the result wipes the platform's copy.
    prfOutput: prf,
  );
}

/// Transport hints as kept with a passkey: WebAuthn token shapes, each once,
/// a few at most. Unknown tokens stay; they are hints, not checks.
List<String> passkeyTransports(Iterable<Object?> raw) {
  final kept = <String>[];
  for (final value in raw) {
    if (kept.length == _maxTransports) break;
    if (value is String &&
        _transport.hasMatch(value) &&
        !kept.contains(value)) {
      kept.add(value);
    }
  }
  return List.unmodifiable(kept);
}

const _maxCredentialIdLength = 1023;
const _maxClientDataLength = 16384;

/// Room for a provider that attests anyway, with a certificate chain.
const _maxAttestationLength = 65536;
const _maxTransports = 8;
final _transport = RegExp(r'^[a-z][a-z0-9-]{0,31}$');

Never _invalid() =>
    throw const WalletAccessException(WalletAccessFailure.invalidResponse);

void _checkClientData(Uint8List raw, PasskeyRegistrationRequest request) {
  if (raw.length > _maxClientDataLength) _invalid();
  Object? client;
  try {
    client = jsonDecode(utf8.decode(raw));
  } on Object {
    _invalid();
  }
  if (client is! Map ||
      client['type'] != 'webauthn.create' ||
      (client['crossOrigin'] ?? false) != false ||
      !passkeyOriginAllowed(client['origin'], request.rpId) ||
      !_sameChallenge(client['challenge'], request.challenge)) {
    _invalid();
  }
}

bool _sameChallenge(Object? encoded, Uint8List expected) {
  if (encoded is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
    return false;
  }
  try {
    return passkeyBytesEqual(
      base64Url.decode(base64Url.normalize(encoded)),
      expected,
    );
  } on FormatException {
    return false;
  }
}

/// The attestation object holds exactly a format, a statement nobody checks
/// here, and the authenticator data.
Uint8List _authData(Uint8List attestationObject) {
  if (attestationObject.length > _maxAttestationLength) _invalid();
  final object = _CborReader.decode(attestationObject);
  if (object is Map && object.length == 3) {
    if (object
        case {
          'fmt': final String format,
          'attStmt': Map _,
          'authData': final Uint8List data,
        }
        when format.isNotEmpty) {
      return data;
    }
  }
  _invalid();
}

/// Authenticator data with attested credential data (WebAuthn §6.1):
/// rpIdHash(32) flags(1) signCount(4) aaguid(16) idLength(2) id key [ext].
final class _AuthData {
  const _AuthData({
    required this.backupEligible,
    required this.backupState,
    required this.aaguid,
  });

  static const _userPresent = 0x01;
  static const _userVerified = 0x04;
  static const _backupEligible = 0x08;
  static const _backupState = 0x10;
  static const _attested = 0x40;
  static const _extensions = 0x80;
  static const _required = _userPresent | _userVerified | _attested;

  final bool backupEligible;
  final bool backupState;
  final String? aaguid;

  static _AuthData parse(Uint8List data, String rpId, Uint8List credentialId) {
    if (data.length < 55) _invalid();
    final flags = data[32];
    final rpIdHash = sha256.convert(utf8.encode(rpId)).bytes;
    // A PRF evaluated without user verification uses another secret, and
    // a backup state without eligibility is a contradiction.
    if (!passkeyBytesEqual(Uint8List.sublistView(data, 0, 32), rpIdHash) ||
        flags & _required != _required ||
        (flags & _backupState != 0 && flags & _backupEligible == 0)) {
      _invalid();
    }
    final idLength = data[53] << 8 | data[54];
    final keyStart = 55 + idLength;
    if (idLength != credentialId.length ||
        keyStart > data.length ||
        !passkeyBytesEqual(
          Uint8List.sublistView(data, 55, keyStart),
          credentialId,
        )) {
      _invalid();
    }
    final reader = _CborReader(data, keyStart);
    final key = reader.read();
    // Never used, as an assertion's signature is not verified, but it
    // must be a COSE key with its type and algorithm.
    if (key is! Map || key[1] is! int || key[3] is! int) _invalid();
    if (flags & _extensions != 0 && reader.read() is! Map) _invalid();
    if (reader.remaining != 0) _invalid();
    return _AuthData(
      backupEligible: flags & _backupEligible != 0,
      backupState: flags & _backupState != 0,
      aaguid: _uuid(Uint8List.sublistView(data, 37, 53)),
    );
  }

  /// Canonical lowercase form, or null for the zeros providers send when
  /// they don't identify themselves.
  static String? _uuid(Uint8List bytes) {
    if (bytes.every((byte) => byte == 0)) return null;
    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
