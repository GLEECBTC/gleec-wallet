import 'package:flutter/services.dart';

import '../../wallet_access_types.dart';

/// One user-verified WebAuthn assertion that also evaluates the PRF
/// extension. An empty [allowCredentials] lets the user choose any passkey
/// they hold for [rpId].
class PasskeyAssertionRequest {
  const PasskeyAssertionRequest({
    required this.rpId,
    required this.challenge,
    required this.salt,
    this.allowCredentials = const [],
  });

  final String rpId;
  final Uint8List challenge;
  final Uint8List salt;
  final List<Uint8List> allowCredentials;
}

/// The operating system's assertion. [prf] is secret key material: whoever
/// receives this wipes it as soon as the key has been derived.
class PasskeyAssertion {
  const PasskeyAssertion({
    required this.credentialId,
    required this.userHandle,
    required this.authenticatorData,
    required this.clientDataJson,
    required this.signature,
    required this.prf,
  });

  final Uint8List credentialId;
  final Uint8List? userHandle;
  final Uint8List authenticatorData;
  final Uint8List clientDataJson;
  final Uint8List signature;
  final Uint8List prf;

  void wipe() => prf.fillRange(0, prf.length, 0);
}

abstract interface class PasskeyAuthenticator {
  /// Whether this build and OS can run a PRF assertion at all. A true answer
  /// is a candidate only: the provider must still return PRF output.
  Future<bool> isSupported();
  Future<PasskeyAssertion> getAssertion(PasskeyAssertionRequest request);
  Future<void> cancel();
}

/// The native bridge on iOS, macOS, Android and Windows.
class MethodChannelPasskeyAuthenticator implements PasskeyAuthenticator {
  MethodChannelPasskeyAuthenticator({MethodChannel? channel})
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
  Future<PasskeyAssertion> getAssertion(PasskeyAssertionRequest request) async {
    final Map<Object?, Object?>? result;
    try {
      result = await _channel.invokeMapMethod<Object?, Object?>(
        'getAssertion',
        {
          'rpId': request.rpId,
          'challenge': request.challenge,
          'salt': request.salt,
          'allowCredentials': request.allowCredentials,
          'timeoutMs': 120000,
        },
      );
    } on MissingPluginException {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    } on PlatformException catch (error) {
      throw WalletAccessException(passkeyChannelFailure(error.code));
    }
    Uint8List bytes(String name, {bool optional = false}) {
      final value = result?[name];
      if (value is Uint8List && (value.isNotEmpty || optional)) return value;
      if (optional && value == null) return Uint8List(0);
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }

    final prf = result?['prf'];
    if (prf is! Uint8List) {
      throw const WalletAccessException(WalletAccessFailure.prfUnavailable);
    }
    final userHandle = bytes('userHandle', optional: true);
    return PasskeyAssertion(
      credentialId: bytes('credentialId'),
      userHandle: userHandle.isEmpty ? null : userHandle,
      authenticatorData: bytes('authenticatorData'),
      clientDataJson: bytes('clientDataJSON'),
      signature: bytes('signature'),
      prf: prf,
    );
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on Object {
      // Nothing is pending, or the platform has no bridge.
    }
  }
}

/// Native error codes, which never carry provider or credential details. An
/// interrupted prompt changed nothing, and nothing continues on a cancel, so
/// it reads as one.
WalletAccessFailure passkeyChannelFailure(String code) => switch (code) {
  'canceled' || 'interrupted' => WalletAccessFailure.canceled,
  'noCredential' => WalletAccessFailure.passkeyNotFound,
  'prfUnavailable' => WalletAccessFailure.prfUnavailable,
  'busy' => WalletAccessFailure.busy,
  'lockedOut' => WalletAccessFailure.lockedOut,
  'invalidResponse' => WalletAccessFailure.invalidResponse,
  _ => WalletAccessFailure.unavailable,
};
