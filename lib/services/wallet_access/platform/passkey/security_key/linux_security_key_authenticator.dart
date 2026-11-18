import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../wallet_access_types.dart';
import '../passkey_authenticator.dart';
import 'security_key_bridge.dart';
import 'security_key_prompts.dart';

/// The salt browsers send as hmac-secret input for a WebAuthn PRF input
/// (WebAuthn Level 3, PRF extension). libfido2 passes its salt through raw.
Uint8List webAuthnPrfSalt(Uint8List input) => Uint8List.fromList(
  sha256.convert([...utf8.encode('WebAuthn PRF'), 0, ...input]).bytes,
);

/// Client data exactly as the Windows bridge composes it, so one set of
/// assertion checks covers both.
Uint8List securityKeyClientData(String rpId, Uint8List challenge) =>
    utf8.encode(
      '{"type":"webauthn.get","challenge":"'
      '${base64Url.encode(challenge).replaceAll('=', '')}'
      '","origin":"https://$rpId","crossOrigin":false}',
    );

/// "Use an existing passkey" on Linux: a FIDO2 security key through
/// libfido2. The PIN and the choice of key come from the app's own sheet
/// ([SecurityKeyPrompts]), never from the platform.
class LinuxSecurityKeyAuthenticator implements PasskeyAuthenticator {
  LinuxSecurityKeyAuthenticator({
    SecurityKeyBridge? bridge,
    SecurityKeyPrompts? prompts,
    this.pollInterval = const Duration(milliseconds: 750),
    this.timeout = const Duration(minutes: 2),
  }) : _bridge = bridge ?? MethodChannelSecurityKeyBridge(),
       _prompts = prompts ?? SecurityKeyPrompts.instance;

  final SecurityKeyBridge _bridge;
  final SecurityKeyPrompts _prompts;
  final Duration pollInterval;

  /// How long one wait (for a key, a touch or a reinsertion) may last.
  final Duration timeout;
  _Session? _session;

  @override
  Future<bool> isSupported() =>
      _bridge.isAvailable().catchError((Object _) => false);

  @override
  Future<PasskeyAssertion> getAssertion(PasskeyAssertionRequest request) async {
    if (_session != null) {
      throw const WalletAccessException(WalletAccessFailure.busy);
    }
    if (!_prompts.hasHost ||
        !RegExp(r'^[a-z0-9.-]{1,253}$').hasMatch(request.rpId)) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    final session = _session = _Session();
    final cancellations = _prompts.cancellations.listen(
      (_) => _interrupt(session),
    );
    try {
      final clientData = securityKeyClientData(request.rpId, request.challenge);
      final keyRequest = _Request(
        rpId: request.rpId,
        clientDataHash: Uint8List.fromList(sha256.convert(clientData).bytes),
        salt: webAuthnPrfSalt(request.salt),
        allowCredentials: request.allowCredentials,
      );
      SecurityKeyCandidate? chosen;
      try {
        while (chosen == null) {
          final device = await _chooseDevice(session);
          chosen = await _assertWith(session, device, keyRequest);
        }
      } on SecurityKeyException catch (error) {
        _fail(_failure(error.code));
      }
      final answer = chosen;
      return PasskeyAssertion(
        credentialId: answer.credentialId,
        userHandle: answer.userHandle,
        authenticatorData: answer.authenticatorData,
        clientDataJson: clientData,
        signature: answer.signature,
        prf: answer.prf!,
      );
    } finally {
      await cancellations.cancel();
      if (identical(_session, session)) _session = null;
      _prompts.close();
    }
  }

  /// Also answers a step waiting on the user, so a lock or sign-out never
  /// waits for the sheet.
  @override
  Future<void> cancel() async {
    final session = _session;
    if (session == null) return;
    _interrupt(session);
    _prompts.cancel();
  }

  void _interrupt(_Session session) {
    if (session.canceled) return;
    session.cancel();
    unawaited(_bridge.cancel().catchError((Object _) {}));
  }

  /// The one usable key, or the key the user touches when there are several.
  /// Waits for one to be inserted.
  Future<SecurityKeyDevice> _chooseDevice(_Session session) async {
    final waiting = Stopwatch()..start();
    while (true) {
      session.ensureActive();
      final devices = await _call(session, _bridge.devices);
      final usable = devices.where((device) => device.usable).toList();
      if (usable.length == 1) return usable.single;
      if (usable.length > 1) {
        _prompts.show(const SecurityKeyPrompt(SecurityKeyStage.chooseKey));
        try {
          final path = await _call(
            session,
            () => _bridge.select([
              for (final device in usable.take(8)) device.path,
            ], timeout: timeout),
          );
          for (final device in usable) {
            if (device.path == path) return device;
          }
        } on SecurityKeyException catch (error) {
          if (error.code == 'timeout') _fail(WalletAccessFailure.canceled);
          if (error.code != 'deviceGone') _fail(_failure(error.code));
        }
        continue;
      }
      // Only keys that cannot evaluate hmac-secret are inserted.
      if (devices.any((d) => d.state == SecurityKeyDeviceState.ready)) {
        _fail(WalletAccessFailure.prfUnavailable);
      }
      if (waiting.elapsed > timeout) _fail(WalletAccessFailure.canceled);
      _prompts.show(
        SecurityKeyPrompt(
          devices.any((d) => d.state == SecurityKeyDeviceState.noAccess)
              ? SecurityKeyStage.noAccess
              : devices.isEmpty
              ? SecurityKeyStage.insert
              : SecurityKeyStage.reinsert,
        ),
      );
      await session.wait(pollInterval);
    }
  }

  /// Null when the key went away and another must be chosen.
  Future<SecurityKeyCandidate?> _assertWith(
    _Session session,
    SecurityKeyDevice device,
    _Request request,
  ) async {
    var builtIn = device.uv && device.uvRetries != 0;
    var retriesLeft = device.pinRetries;
    var wrongPin = false;
    while (true) {
      session.ensureActive();
      Uint8List? pin;
      // Covers a PIN that arrives after a cancel overtook it, too.
      try {
        if (!builtIn) {
          // The web wallet's passkeys need verification, which a key without
          // a PIN or fingerprint cannot give, so it holds none of them.
          if (!device.pin) {
            _fail(
              device.uv
                  ? WalletAccessFailure.lockedOut
                  : WalletAccessFailure.passkeyNotFound,
            );
          }
          if (retriesLeft == 0) _fail(WalletAccessFailure.lockedOut);
          pin = await _prompts.askPin(
            product: device.product,
            retriesLeft: retriesLeft,
            wrongPin: wrongPin,
          );
          if (pin == null) _interrupt(session);
          session.ensureActive();
        }
        _prompts.show(
          SecurityKeyPrompt(SecurityKeyStage.touch, product: device.product),
        );
        final candidates = await _call(
          session,
          () => _bridge.getAssertion(
            path: device.path,
            rpId: request.rpId,
            clientDataHash: request.clientDataHash,
            salt: request.salt,
            allowCredentials: request.allowCredentials,
            timeout: timeout,
            pin: pin,
          ),
        );
        return await _pick(session, candidates);
      } on SecurityKeyException catch (error) {
        switch (error.code) {
          case 'pinInvalid':
            wrongPin = true;
            retriesLeft = error.retries;
          case 'pinRequired' || 'uvInvalid' || 'uvBlocked' when builtIn:
            // CTAP 2.1: built-in verification falls back to the PIN.
            builtIn = false;
            wrongPin = false;
          case 'uvInvalid' || 'uvBlocked':
            _fail(WalletAccessFailure.lockedOut);
          case 'pinAuthBlocked':
            await _awaitRemoval(session, device.path);
            return null;
          case 'pinBlocked':
            _fail(WalletAccessFailure.lockedOut);
          case 'pinNotSet':
            _fail(WalletAccessFailure.passkeyNotFound);
          case 'timeout':
            if (!await _prompts.askRetry(product: device.product)) {
              _interrupt(session);
            }
            session.ensureActive();
            wrongPin = false;
          case 'deviceGone' || 'noAccess':
            return null;
          default:
            _fail(_failure(error.code));
        }
      } finally {
        pin?.fillRange(0, pin.length, 0);
      }
    }
  }

  /// A key that refused three wrong PINs takes no more until it has been
  /// removed; afterwards the device choice waits for it again.
  Future<void> _awaitRemoval(_Session session, String path) async {
    final waiting = Stopwatch()..start();
    _prompts.show(const SecurityKeyPrompt(SecurityKeyStage.reinsert));
    while (true) {
      session.ensureActive();
      final devices = await _call(session, _bridge.devices);
      if (!devices.any((device) => device.path == path)) return;
      if (waiting.elapsed > timeout) _fail(WalletAccessFailure.canceled);
      await session.wait(pollInterval);
    }
  }

  /// Each web wallet the user protected left its own passkey on the key, so
  /// a discoverable request can return several. The others' PRF outputs are
  /// for a salt no envelope uses, and are wiped at once.
  Future<SecurityKeyCandidate> _pick(
    _Session session,
    List<SecurityKeyCandidate> candidates,
  ) async {
    var index = 0;
    try {
      session.ensureActive();
      if (candidates.length > 1) {
        final chosen = await _prompts.chooseAccount([
          for (final candidate in candidates)
            SecurityKeyAccount(
              displayName: candidate.userDisplayName,
              name: candidate.userName,
              usable: candidate.prf != null,
            ),
        ]);
        if (chosen == null) _interrupt(session);
        session.ensureActive();
        index = chosen!;
      }
      if (candidates[index].prf?.length != 32) {
        _fail(WalletAccessFailure.prfUnavailable);
      }
      return candidates[index];
    } catch (_) {
      index = -1;
      rethrow;
    } finally {
      for (var i = 0; i < candidates.length; i++) {
        if (i != index) candidates[i].wipe();
      }
    }
  }

  /// A bridge call that a cancel overtakes reports the cancel, whatever the
  /// key answered meanwhile.
  Future<T> _call<T>(_Session session, Future<T> Function() call) async {
    final T result;
    try {
      result = await call();
    } on SecurityKeyException {
      session.ensureActive();
      rethrow;
    }
    if (session.canceled && result is List<SecurityKeyCandidate>) {
      for (final candidate in result) {
        candidate.wipe();
      }
    }
    session.ensureActive();
    return result;
  }
}

Never _fail(WalletAccessFailure failure) =>
    throw WalletAccessException(failure);

WalletAccessFailure _failure(String code) => switch (code) {
  'pinBlocked' => WalletAccessFailure.lockedOut,
  'timeout' => WalletAccessFailure.canceled,
  _ => passkeyChannelFailure(code),
};

class _Request {
  const _Request({
    required this.rpId,
    required this.clientDataHash,
    required this.salt,
    required this.allowCredentials,
  });

  final String rpId;
  final Uint8List clientDataHash;
  final Uint8List salt;
  final List<Uint8List> allowCredentials;
}

class _Session {
  final _signal = Completer<void>();
  bool canceled = false;

  void cancel() {
    canceled = true;
    if (!_signal.isCompleted) _signal.complete();
  }

  void ensureActive() {
    if (canceled) _fail(WalletAccessFailure.canceled);
  }

  Future<void> wait(Duration duration) =>
      Future.any([Future<void>.delayed(duration), _signal.future]);
}
