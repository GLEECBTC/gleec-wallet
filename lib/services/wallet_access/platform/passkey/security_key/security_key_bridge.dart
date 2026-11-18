import 'package:flutter/services.dart';

enum SecurityKeyDeviceState {
  ready,

  /// Listed by udev, but this session may not open it.
  noAccess,

  /// Present but not answering, e.g. held by another app.
  unreadable,
}

/// A security key as the Linux bridge lists it. It carries no secret.
class SecurityKeyDevice {
  const SecurityKeyDevice({
    required this.path,
    required this.state,
    this.product,
    this.hmacSecret = false,
    this.pin = false,
    this.uv = false,
    this.pinRetries,
    this.uvRetries,
  });

  final String path;
  final SecurityKeyDeviceState state;
  final String? product;
  final bool hmacSecret;

  /// A PIN is set.
  final bool pin;

  /// Built-in verification, such as a fingerprint, is set up.
  final bool uv;
  final int? pinRetries;
  final int? uvRetries;

  bool get usable => state == SecurityKeyDeviceState.ready && hmacSecret;
}

/// One credential in a key's answer. [prf] is secret key material, null
/// when the key evaluated no hmac-secret for this credential.
class SecurityKeyCandidate {
  const SecurityKeyCandidate({
    required this.credentialId,
    required this.authenticatorData,
    required this.signature,
    this.userHandle,
    this.userName,
    this.userDisplayName,
    this.prf,
  });

  final Uint8List credentialId;
  final Uint8List? userHandle;
  final String? userName;
  final String? userDisplayName;
  final Uint8List authenticatorData;
  final Uint8List signature;
  final Uint8List? prf;

  void wipe() => prf?.fillRange(0, prf!.length, 0);
}

/// A bridge error code, never with key or credential details.
class SecurityKeyException implements Exception {
  const SecurityKeyException(this.code, {this.retries});

  final String code;

  /// PIN or built-in verification tries left, after a wrong attempt.
  final int? retries;

  @override
  String toString() => 'SecurityKeyException($code)';
}

/// The `gleec.wallet/security_key` channel: libfido2 on Linux, one request
/// at a time.
abstract interface class SecurityKeyBridge {
  Future<bool> isAvailable();
  Future<List<SecurityKeyDevice>> devices();

  /// Blinks every key in [paths] and returns the one the user touches.
  Future<String> select(List<String> paths, {required Duration timeout});

  /// [salt] is the hmac-secret input, already transformed from the PRF input.
  /// A null [pin] asks the key for built-in verification.
  Future<List<SecurityKeyCandidate>> getAssertion({
    required String path,
    required String rpId,
    required Uint8List clientDataHash,
    required Uint8List salt,
    required List<Uint8List> allowCredentials,
    required Duration timeout,
    Uint8List? pin,
  });
  Future<void> cancel();
}

class MethodChannelSecurityKeyBridge implements SecurityKeyBridge {
  MethodChannelSecurityKeyBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('gleec.wallet/security_key');

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('support');
      return result?['available'] == true;
    } on Object {
      return false;
    }
  }

  @override
  Future<List<SecurityKeyDevice>> devices() async {
    final result = await _invoke('devices');
    final list = result['devices'];
    if (list is! List) throw const SecurityKeyException('invalidResponse');
    return [for (final entry in list) _device(entry)];
  }

  @override
  Future<String> select(List<String> paths, {required Duration timeout}) async {
    final result = await _invoke('select', {
      'paths': paths,
      'timeoutMs': timeout.inMilliseconds,
    });
    final path = result['path'];
    if (path is! String) throw const SecurityKeyException('invalidResponse');
    return path;
  }

  @override
  Future<List<SecurityKeyCandidate>> getAssertion({
    required String path,
    required String rpId,
    required Uint8List clientDataHash,
    required Uint8List salt,
    required List<Uint8List> allowCredentials,
    required Duration timeout,
    Uint8List? pin,
  }) async {
    final result = await _invoke('getAssertion', {
      'path': path,
      'rpId': rpId,
      'clientDataHash': clientDataHash,
      'salt': salt,
      'allowCredentials': allowCredentials,
      'pin': pin,
      'timeoutMs': timeout.inMilliseconds,
    });
    final list = result['assertions'];
    if (list is! List || list.isEmpty) {
      throw const SecurityKeyException('invalidResponse');
    }
    try {
      return [for (final entry in list) _candidate(entry)];
    } on Object {
      // Candidates share these buffers, so this wipes every one decoded.
      for (final entry in list) {
        final prf = entry is Map ? entry['prf'] : null;
        if (prf is Uint8List) prf.fillRange(0, prf.length, 0);
      }
      rethrow;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on Object {
      // Nothing is pending, or this build has no bridge.
    }
  }

  Future<Map<Object?, Object?>> _invoke(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        method,
        arguments,
      );
      if (result == null) throw const SecurityKeyException('invalidResponse');
      return result;
    } on MissingPluginException {
      throw const SecurityKeyException('unavailable');
    } on PlatformException catch (error) {
      final details = error.details;
      final retries = details is Map ? details['retries'] : null;
      throw SecurityKeyException(
        error.code,
        retries: retries is int && retries >= 0 ? retries : null,
      );
    }
  }
}

SecurityKeyDevice _device(Object? entry) {
  if (entry is! Map || entry['path'] is! String) {
    throw const SecurityKeyException('invalidResponse');
  }
  int? count(Object? value) => value is int && value >= 0 ? value : null;
  return SecurityKeyDevice(
    path: entry['path'] as String,
    product: entry['product'] is String ? entry['product'] as String : null,
    state: switch (entry['state']) {
      'ready' => SecurityKeyDeviceState.ready,
      'noAccess' => SecurityKeyDeviceState.noAccess,
      _ => SecurityKeyDeviceState.unreadable,
    },
    hmacSecret: entry['hmacSecret'] == true,
    pin: entry['pin'] == true,
    uv: entry['uv'] == true,
    pinRetries: count(entry['pinRetries']),
    uvRetries: count(entry['uvRetries']),
  );
}

SecurityKeyCandidate _candidate(Object? entry) {
  if (entry is! Map) throw const SecurityKeyException('invalidResponse');
  final map = entry;
  Uint8List bytes(String name) {
    final value = map[name];
    if (value is Uint8List && value.isNotEmpty) return value;
    throw const SecurityKeyException('invalidResponse');
  }

  final userHandle = map['userHandle'];
  final prf = map['prf'];
  return SecurityKeyCandidate(
    credentialId: bytes('credentialId'),
    authenticatorData: bytes('authenticatorData'),
    signature: bytes('signature'),
    userHandle: userHandle is Uint8List && userHandle.isNotEmpty
        ? userHandle
        : null,
    userName: map['userName'] is String ? map['userName'] as String : null,
    userDisplayName: map['userDisplayName'] is String
        ? map['userDisplayName'] as String
        : null,
    prf: prf is Uint8List ? prf : null,
  );
}
