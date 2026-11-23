import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../wallet_access_types.dart';
import '../credential_backend.dart';
import 'passkey_assertion_check.dart';
import 'passkey_authenticator.dart';
import 'passkey_envelope.dart';

part 'passkey_credential_changes.dart';
part 'passkey_credential_records.dart';

/// Adds passkey protection to a device vault that knows nothing about it.
///
/// The envelope is stored beside the wallet's record, in the vault's
/// unattended tier: it is ciphertext that only the bound passkey can open.
/// Precedence makes every switch a single step. While the device vault holds
/// a record for a key, that record is the wallet's protection and an envelope
/// beside it is inert. The envelope takes effect only once that record is
/// gone, and a device record written over it takes effect at once.
class PasskeyCredentialBackend extends CredentialBackend {
  PasskeyCredentialBackend({
    required CredentialBackend base,
    required PasskeyAuthenticator authenticator,
    this.rpId = relyingParty,
    Duration Function()? monotonicNow,
    Random? random,
  }) : _base = base,
       _authenticator = authenticator,
       _random = random ?? Random.secure(),
       _now = monotonicNow ?? _stopwatch() {
    _lockSubscription = base.deviceLocked.listen((_) => _revoke());
  }

  /// Passkeys made on the production web wallet are scoped to this host.
  static const relyingParty = 'dex.gleec.com';
  static const _permitPrefix = 'passkey:';
  static const _permitLifetime = Duration(seconds: 60);
  static const _readbackLifetime = Duration(seconds: 30);

  final String rpId;
  final CredentialBackend _base;
  final PasskeyAuthenticator _authenticator;
  final Random _random;
  final Duration Function() _now;
  late final StreamSubscription<void> _lockSubscription;
  int _generation = 0;
  bool _busy = false;
  _Permit? _readPermit;
  final _permits = <String, _Permit>{};
  _Readback? _readback;

  /// Another relying party's envelopes live under their own name, so a
  /// staging build sharing this keychain never mistakes them for damage.
  static String slotFor(String key, [String rpId = relyingParty]) =>
      rpId == relyingParty ? '$key.passkey' : '$key.passkey.$rpId';

  static Duration Function() _stopwatch() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }

  @override
  Stream<void> get deviceLocked => _base.deviceLocked;
  @override
  Stream<String?> get protectionChanged => _base.protectionChanged;

  @override
  Future<CredentialCapabilities> capabilities() async {
    final actual = await _base.capabilities();
    return CredentialCapabilities(
      available: actual.available,
      protection: actual.protection,
      deviceAuthentication: actual.deviceAuthentication,
      passkeyCandidate: actual.passkeyCandidate,
      // Asked each time: a screen lock added while the app runs counts.
      existingPasskeyCandidate:
          actual.available &&
          await _authenticator.isSupported().catchError((Object _) => false),
      unattendedReturn:
          actual.available &&
          actual.unattendedReturn &&
          !actual.deviceAuthentication,
    );
  }

  @override
  Future<CredentialRecordInfo?> metadata(String key) async {
    final device = await _base.metadata(key);
    if (device != null) return device;
    final slot = await _slot(key);
    if (slot == null) return null;
    final envelope = slot.envelope;
    // As the device vaults report a record they cannot use.
    if (envelope == null) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    return CredentialRecordInfo(
      protection: CredentialProtection.passkey,
      enrolled: true,
      revision: envelope.revision,
    );
  }

  @override
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  }) async {
    if (await _deviceHolds(key)) {
      return _base.read(
        key,
        reason: reason,
        requireAuthentication: requireAuthentication,
        automatic: automatic,
        purpose: purpose,
      );
    }
    if (await _slot(key) == null) return null;
    return _exclusive((token) async {
      final slot = await _slot(key);
      final envelope = _usable(slot);
      if (purpose == 'verifyWrite') {
        final grant = _readback;
        _readback = null;
        if (grant != null &&
            grant.permit.valid(key, slot!, _generation, _now())) {
          try {
            return envelope.open(grant.aesKey);
          } finally {
            grant.wipe();
          }
        }
        grant?.wipe();
      }
      final aesKey = await _unlock(envelope, token);
      final String value;
      try {
        value = envelope.open(aesKey);
      } finally {
        aesKey.fillRange(0, aesKey.length, 0);
      }
      await _ensureUnchanged(key, slot!, token);
      if (purpose == 'delete' && !automatic) {
        _readPermit = _permit(key, slot, token);
      }
      return value;
    });
  }

  @override
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) async {
    if (await _deviceHolds(key) || await _slot(key) == null) {
      return _base.write(
        key,
        value,
        requireAuthentication: requireAuthentication,
      );
    }
    // A passkey record never becomes unattended through a Boolean, and a
    // record this build cannot open is replaced only through repair.
    if (!requireAuthentication) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    await _exclusive((token) async {
      final slot = await _slot(key);
      final current = slot?.envelope;
      if (current == null) {
        throw const WalletAccessException(WalletAccessFailure.invalidated);
      }
      final aesKey = await _unlock(current, token);
      try {
        current.open(aesKey);
        final next = current.reseal(value, aesKey, random: _random);
        final stored = await _commit(
          next,
          value,
          aesKey,
          token,
          expected: slot,
        );
        // A cancel during the commit leaves the reseal in place but grants
        // nothing: its readback then asks again.
        if (token == _generation) _grantReadback(key, stored, aesKey, token);
      } finally {
        aesKey.fillRange(0, aesKey.length, 0);
      }
    });
  }

  @override
  Future<void> repairInvalidated(String key, String value) async {
    if (await _deviceHolds(key)) return _base.repairInvalidated(key, value);
    final slot = await _slot(key);
    if (slot == null || slot.envelope != null) {
      throw const WalletAccessException(WalletAccessFailure.unavailable);
    }
    // Only an envelope nobody can open is repaired, and only after the
    // engine verified [value]: device protection replaces it.
    await _exclusive((token) async {
      await _ensureUnchanged(key, slot, token);
      await _base.write(key, value, requireAuthentication: true);
      await _removeSlot(key);
    });
  }

  @override
  Future<void> bindExistingPasskey(String key, String value) =>
      _bindExisting(key, value);

  @override
  Future<void> replacePasskeyAfterPasswordVerification(
    String key,
    String value, {
    required int expectedRevision,
    required String label,
  }) => _rebind(key, value, expectedRevision);

  @override
  Future<void> replacePasskeyWithDevice(
    String key,
    String value, {
    required int expectedRevision,
  }) => _replaceWithDevice(key, value, expectedRevision);

  @override
  Future<void> replacePasskeyWithUnattended(
    String key,
    String value, {
    required int expectedRevision,
  }) => _replaceWithDevice(
    key,
    value,
    expectedRevision,
    requireAuthentication: false,
  );

  @override
  Future<String?> prepareDelete(String key, {required String reason}) =>
      _prepareDelete(key, reason);

  @override
  Future<String?> prepareDeleteAfterPasswordVerification(
    String key, {
    required int expectedRevision,
  }) => _prepareDeleteAfterPassword(key, expectedRevision);

  @override
  Future<void> delete(String key, {String? authorization}) =>
      _delete(key, authorization);

  @override
  Future<void> enrollPasskey(
    String key,
    String value, {
    required String label,
  }) => _base.enrollPasskey(key, value, label: label);

  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) =>
      _base.savePassword(username: username, password: password, title: title);

  @override
  Future<void> cancel() async {
    _revoke();
    await _authenticator.cancel();
    await _base.cancel();
  }

  Future<void> dispose() {
    _revoke();
    return _lockSubscription.cancel();
  }

  void _revoke() {
    _generation++;
    _readPermit = null;
    _permits.clear();
    _clearReadback();
  }

  /// Whether the device vault's record governs [key]. One it cannot describe
  /// is still its own, so the operation goes to it exactly as before.
  Future<bool> _deviceHolds(String key) async {
    try {
      return await _base.metadata(key) != null;
    } on WalletAccessException catch (error) {
      // Anything else, such as a busy vault, says nothing about which record
      // governs, and must never route a write in front of an envelope.
      if (error.failure == WalletAccessFailure.invalidated) return true;
      rethrow;
    }
  }

  Future<_Slot?> _slot(String key) async {
    final raw = await _base.read(
      slotFor(key, rpId),
      reason: 'Unlock your Gleec wallet',
    );
    if (raw == null) return null;
    try {
      return _Slot(
        raw,
        PasskeyEnvelope.decode(raw, expectedKey: key, expectedRpId: rpId),
      );
    } on WalletAccessException {
      return _Slot(raw, null);
    }
  }

  PasskeyEnvelope _usable(_Slot? slot) {
    final envelope = slot?.envelope;
    if (slot == null) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    if (envelope == null) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    return envelope;
  }

  Future<T> _exclusive<T>(Future<T> Function(int token) body) async {
    if (_busy) throw const WalletAccessException(WalletAccessFailure.busy);
    final grant = _readback;
    if (grant != null && _now() >= grant.permit.expires) {
      _clearReadback();
    }
    _busy = true;
    try {
      return await body(_generation);
    } finally {
      _busy = false;
    }
  }

  void _ensureCurrent(int token) {
    if (token != _generation) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
  }

  /// The envelope is still the one this operation authorized against, and
  /// no device record has appeared in front of it.
  Future<void> _ensureUnchanged(String key, _Slot expected, int token) async {
    _ensureCurrent(token);
    final current = await _slot(key);
    if (current?.raw != expected.raw || await _deviceHolds(key)) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    _ensureCurrent(token);
  }

  /// One assertion with this layer's checks. Returns the derived key; the
  /// PRF output itself never leaves this method.
  Future<_Binding> _assert(
    PasskeyAssertionRequest request,
    int token, {
    Uint8List? expectedUserHandle,
  }) async {
    _ensureCurrent(token);
    final assertion = await _authenticator.getAssertion(request);
    try {
      _ensureCurrent(token);
      checkPasskeyAssertion(
        assertion,
        request,
        expectedUserHandle: expectedUserHandle,
      );
      return (
        credentialId: Uint8List.fromList(assertion.credentialId),
        userHandle: assertion.userHandle == null
            ? null
            : Uint8List.fromList(assertion.userHandle!),
        aesKey: PasskeyEnvelope.deriveKey(assertion.prf),
      );
    } finally {
      assertion.wipe();
    }
  }

  Future<Uint8List> _unlock(PasskeyEnvelope envelope, int token) async {
    final result = await _assert(
      PasskeyAssertionRequest(
        rpId: rpId,
        challenge: PasskeyEnvelope.randomBytes(32, _random),
        salt: envelope.salt,
        allowCredentials: [envelope.credentialId],
      ),
      token,
      expectedUserHandle: envelope.userHandle,
    );
    return result.aesKey;
  }

  /// Writes [next] over [expected] and proves the stored bytes open to
  /// [value] with this ceremony's key before anything relies on them.
  Future<_Slot> _commit(
    PasskeyEnvelope next,
    String value,
    Uint8List aesKey,
    int token, {
    required _Slot? expected,
  }) async {
    if (expected == null) {
      if (await _slot(next.key) != null) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
      _ensureCurrent(token);
    } else {
      await _ensureUnchanged(next.key, expected, token);
    }
    await _base.write(
      slotFor(next.key, rpId),
      next.encode(),
      requireAuthentication: false,
    );
    final slot = await _slot(next.key);
    final stored = slot?.envelope;
    if (stored == null ||
        stored.revision != next.revision ||
        stored.open(aesKey) != value) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    return slot!;
  }

  Future<void> _removeSlot(String key) async {
    await _base.delete(slotFor(key, rpId));
    if (await _base.read(
          slotFor(key, rpId),
          reason: 'Unlock your Gleec wallet',
        ) !=
        null) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  /// Lets the one readback that follows a password change open what was just
  /// written without a second ceremony, as the device vaults do.
  void _grantReadback(String key, _Slot stored, Uint8List aesKey, int token) {
    _readback?.wipe();
    _readback = _Readback(
      _Permit(key, stored.fingerprint, token, _now() + _readbackLifetime),
      Uint8List.fromList(aesKey),
      onExpiry: _clearReadback,
    );
  }

  void _clearReadback() {
    _readback?.wipe();
    _readback = null;
  }

  _Permit _permit(String key, _Slot slot, int token) =>
      _Permit(key, slot.fingerprint, token, _now() + _permitLifetime);

  String _issue(_Permit permit) {
    _permits.removeWhere((_, existing) => existing.expires < _now());
    final token =
        '$_permitPrefix${base64Url.encode(PasskeyEnvelope.randomBytes(18, _random))}';
    _permits[token] = permit;
    return token;
  }

  String _identifier() => base64Url
      .encode(PasskeyEnvelope.randomBytes(18, _random))
      .replaceAll('=', '');
}
