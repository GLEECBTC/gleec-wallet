import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../wallet_access_types.dart';
import 'credential_backend.dart';

@JS('gleecWalletCredentials')
external JSObject? get _walletCredentials;

/// Browser-local storage and WebAuthn PRF access. The bridge owns WebCrypto,
/// transactional IndexedDB persistence and cross-tab ceremony coordination.
class WebCredentialBackend extends CredentialBackend {
  late final JSFunction _changeListener = ((web.Event event) {
    final detail = (event as web.CustomEvent).detail.dartify();
    if (detail is Map && detail['external'] == true) {
      _changes.add(null);
    }
  }).toJS;

  late final StreamController<void> _changes = StreamController<void>.broadcast(
    onListen: () => web.window.addEventListener(
      'gleecWalletProtectionChanged',
      _changeListener,
    ),
    onCancel: () => web.window.removeEventListener(
      'gleecWalletProtectionChanged',
      _changeListener,
    ),
  );

  @override
  Stream<void> get protectionChanged => _changes.stream;

  Future<Object?> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final bridge = _walletCredentials;
    if (bridge == null) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    try {
      final promise = arguments == null
          ? bridge.callMethod<JSPromise<JSAny?>>(method.toJS)
          : bridge.callMethod<JSPromise<JSAny?>>(
              method.toJS,
              arguments.jsify(),
            );
      return (await promise.toDart).dartify();
    } catch (error) {
      throw _safeFailure(error);
    }
  }

  WalletAccessException _safeFailure(Object error) {
    if (error is WalletAccessException) return error;
    Object? code;
    try {
      code = (error as JSObject).getProperty<JSAny?>('code'.toJS).dartify();
    } catch (_) {
      // Raw browser exceptions can contain credential/provider details.
    }
    final failure = switch (code) {
      'canceled' || 'notCompleted' || 'aborted' => WalletAccessFailure.canceled,
      'unsupported' || 'unavailable' => WalletAccessFailure.unavailable,
      'invalidated' => WalletAccessFailure.invalidated,
      'lockedOut' => WalletAccessFailure.lockedOut,
      'storageFailed' => WalletAccessFailure.storageFailed,
      'busy' => WalletAccessFailure.busy,
      'staleOperation' => WalletAccessFailure.staleOperation,
      'walletUnavailable' => WalletAccessFailure.walletUnavailable,
      'prfUnavailable' => WalletAccessFailure.prfUnavailable,
      'envelopeCorrupt' => WalletAccessFailure.envelopeCorrupt,
      _ => WalletAccessFailure.invalidResponse,
    };
    return WalletAccessException(failure);
  }

  Map<Object?, Object?> _map(Object? value) {
    if (value is Map) return value.cast<Object?, Object?>();
    throw const WalletAccessException(WalletAccessFailure.invalidResponse);
  }

  CredentialProtection _protection(Object? value) => value == 'passkeyPrf'
      ? CredentialProtection.passkey
      : CredentialProtection.parse(value);

  @override
  Future<CredentialCapabilities> capabilities() async {
    final result = _map(await _call('capabilities'));
    return CredentialCapabilities(
      available: result['available'] == true,
      protection: _protection(result['protection']),
      deviceAuthentication: false,
      passkeyCandidate: result['passkeys'] == true,
    );
  }

  @override
  Future<CredentialRecordInfo?> metadata(String key) async {
    final result = await _call('metadata', {'key': key});
    if (result == null) return null;
    final record = _map(result);
    final revision = record['revision'];
    if (revision is! num || revision < 1 || revision.toInt() != revision) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    return CredentialRecordInfo(
      protection: _protection(record['protection']),
      enrolled: record['enrolled'] == true,
      revision: revision.toInt(),
    );
  }

  @override
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) async {
    await _call('write', {
      'key': key,
      'value': value,
      'requireAuthentication': requireAuthentication,
    });
  }

  @override
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  }) async {
    final result = await _call('read', {
      'key': key,
      'reason': reason,
      'requireAuthentication': requireAuthentication,
      'trigger': automatic ? 'automatic' : 'explicit',
      'purpose': purpose,
    });
    if (result == null || result is String) return result as String?;
    throw const WalletAccessException(WalletAccessFailure.invalidResponse);
  }

  @override
  Future<String?> prepareDelete(String key, {required String reason}) async {
    final result = await _call('prepareDelete', {'key': key, 'reason': reason});
    if (result == null || result is String) return result as String?;
    throw const WalletAccessException(WalletAccessFailure.invalidResponse);
  }

  @override
  Future<void> delete(String key, {String? authorization}) async {
    await _call('delete', {'key': key, 'authorization': authorization});
  }

  @override
  Future<void> cancel() async {
    // Cancellation is synchronous so a wallet switch immediately invalidates
    // outstanding WebAuthn promises before the next microtask can resolve.
    try {
      _walletCredentials?.callMethod<JSAny?>('cancel'.toJS);
    } catch (error) {
      throw _safeFailure(error);
    }
  }

  @override
  Future<void> enrollPasskey(
    String key,
    String value, {
    required String label,
  }) async {
    await _call('enrollPasskey', {'key': key, 'value': value, 'label': label});
  }

  @override
  Future<void> replacePasskeyAfterPasswordVerification(
    String key,
    String value, {
    required int expectedRevision,
    required String label,
  }) async {
    await _call('replacePasskeyAfterPasswordVerification', {
      'key': key,
      'value': value,
      'expectedRevision': expectedRevision,
      'label': label,
    });
  }

  @override
  Future<String?> prepareDeleteAfterPasswordVerification(
    String key, {
    required int expectedRevision,
  }) async {
    final result = await _call('prepareDeleteAfterPasswordVerification', {
      'key': key,
      'expectedRevision': expectedRevision,
    });
    if (result == null || result is String) return result as String?;
    throw const WalletAccessException(WalletAccessFailure.invalidResponse);
  }

  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) async {
    final result = await _call('savePassword', {
      'username': username,
      'password': password,
      'title': title,
    });
    return switch (result) {
      'accepted' => PasswordManagerOutcome.accepted,
      'unknown' => PasswordManagerOutcome.unknown,
      'declined' => PasswordManagerOutcome.declined,
      'failed' => PasswordManagerOutcome.failed,
      'unavailable' => PasswordManagerOutcome.unavailable,
      _ => throw const WalletAccessException(
        WalletAccessFailure.invalidResponse,
      ),
    };
  }
}

CredentialBackend createCredentialBackend() => WebCredentialBackend();
