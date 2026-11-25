part of 'passkey_credential_backend.dart';

/// Switching protection and removing records. Each change is verified before
/// the step that makes it take effect, so an interruption leaves the wallet
/// opening exactly as it did before.
extension _PasskeyChanges on PasskeyCredentialBackend {
  Future<void> _bindExisting(String key, String value) => _exclusive((
    token,
  ) async {
    // A record the device vault cannot describe is not switched away from.
    final device = await _base.metadata(key);
    var slot = await _slot(key);
    if (device == null && slot?.envelope != null) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    final revision =
        max(device?.revision ?? 0, slot?.envelope?.revision ?? 0) + 1;
    // Behind a device record an envelope is inert: one an interrupted switch
    // left there must not stand in the way of this one.
    if (device != null && slot != null) {
      await _removeSlot(key);
      slot = null;
    }
    final salt = PasskeyEnvelope.randomBytes(
      PasskeyEnvelope.saltLength,
      _random,
    );
    final binding = await _chooseAndVerify(salt, token);
    try {
      final next = _sealBinding(
        key,
        value,
        binding,
        salt: salt,
        revision: revision,
      );
      await _commit(next, value, binding.aesKey, token, expected: slot);
      if (device != null) await _retireDeviceRecord(key, token);
    } finally {
      binding.aesKey.fillRange(0, binding.aesKey.length, 0);
    }
  });

  /// The switch itself. A caller that read the credential with purpose
  /// `delete` lets the vault authorize this without another prompt.
  Future<void> _retireDeviceRecord(String key, int token) async {
    try {
      final authorization = await _base.prepareDelete(
        key,
        reason: 'Switch this wallet to your passkey',
      );
      _ensureCurrent(token);
      await _base.delete(key, authorization: authorization);
    } catch (error, stack) {
      final CredentialRecordInfo? device;
      try {
        device = await _base.metadata(key);
      } on Object {
        Error.throwWithStackTrace(error, stack);
      }
      // The removal landed even though its reply did not: the verified
      // envelope now governs the wallet, which is what was asked for.
      if (device == null) return;
      try {
        await _base.delete(PasskeyCredentialBackend.slotFor(key, rpId));
      } on Object {
        // Inert while the device record exists; removed with the wallet.
      }
      Error.throwWithStackTrace(error, stack);
    }
    if (await _base.metadata(key) != null) {
      try {
        await _base.delete(PasskeyCredentialBackend.slotFor(key, rpId));
      } on Object {
        // Inert while the device record exists; removed with the wallet.
      }
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  PasskeyEnvelope _sealBinding(
    String key,
    String value,
    _Binding binding, {
    required Uint8List salt,
    required int revision,
  }) => PasskeyEnvelope.seal(
    key: key,
    revision: revision,
    rpId: rpId,
    credentialId: binding.credentialId,
    userHandle: binding.userHandle,
    enrollmentId: _identifier(),
    salt: salt,
    aesKey: binding.aesKey,
    value: value,
    random: _random,
  );

  /// The user picks any passkey they hold for [rpId], and [salt] becomes
  /// that binding's own PRF input. A second assertion for exactly that
  /// passkey must reproduce the key before anything depends on it: an
  /// envelope later unlocks cannot open would strand a password the user
  /// may never have seen, as the browser vault's verified enrollment guards.
  Future<_Binding> _chooseAndVerify(Uint8List salt, int token) async {
    final chosen = await _assert(
      PasskeyAssertionRequest(
        rpId: rpId,
        challenge: PasskeyEnvelope.randomBytes(32, _random),
        salt: salt,
      ),
      token,
    );
    try {
      final again = await _assert(
        PasskeyAssertionRequest(
          rpId: rpId,
          challenge: PasskeyEnvelope.randomBytes(32, _random),
          salt: salt,
          allowCredentials: [chosen.credentialId],
        ),
        token,
        expectedUserHandle: chosen.userHandle,
      );
      try {
        if (!passkeyBytesEqual(again.aesKey, chosen.aesKey)) {
          throw const WalletAccessException(WalletAccessFailure.prfUnavailable);
        }
      } finally {
        again.aesKey.fillRange(0, again.aesKey.length, 0);
      }
      return chosen;
    } catch (_) {
      chosen.aesKey.fillRange(0, chosen.aesKey.length, 0);
      rethrow;
    }
  }

  Future<void> _rebind(String key, String value, int expectedRevision) =>
      _exclusive((token) async {
        final slot = await _passkeySlot(key, expectedRevision);
        final salt = PasskeyEnvelope.randomBytes(
          PasskeyEnvelope.saltLength,
          _random,
        );
        final binding = await _chooseAndVerify(salt, token);
        try {
          final next = _sealBinding(
            key,
            value,
            binding,
            salt: salt,
            revision: expectedRevision + 1,
          );
          await _commit(next, value, binding.aesKey, token, expected: slot);
        } finally {
          binding.aesKey.fillRange(0, binding.aesKey.length, 0);
        }
      });

  Future<void> _replaceWithDevice(
    String key,
    String value,
    int expectedRevision, {
    bool requireAuthentication = true,
  }) => _exclusive((token) async {
    // Only where the vault has no protected tier: never a way around one
    // that can protect the record, or will once device unlock is set up.
    if (!requireAuthentication) {
      final capabilities = await _base.capabilities();
      if (!capabilities.unattendedReturn || capabilities.deviceAuthentication) {
        throw const WalletAccessException(WalletAccessFailure.unavailable);
      }
    }
    await _passkeySlot(key, expectedRevision);
    _ensureCurrent(token);
    await _base.write(key, value, requireAuthentication: requireAuthentication);
    // The device record governs the wallet from here; the envelope is inert.
    try {
      await _removeSlot(key);
    } on Object {
      // Removed with the wallet or by the next binding.
    }
  });

  /// The governing passkey envelope at exactly [expectedRevision].
  Future<_Slot> _passkeySlot(String key, int expectedRevision) async {
    if (await _deviceHolds(key)) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    final slot = await _slot(key);
    if (slot == null) {
      throw const WalletAccessException(WalletAccessFailure.walletUnavailable);
    }
    if (slot.envelope?.revision != expectedRevision) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    return slot;
  }

  Future<String?> _prepareDelete(String key, String reason) async {
    if (await _deviceHolds(key)) {
      return _base.prepareDelete(key, reason: reason);
    }
    if (await _slot(key) == null) return null;
    return _exclusive((token) async {
      final slot = await _slot(key);
      if (slot == null) return null;
      final prior = _readPermit;
      _readPermit = null;
      if (prior != null && prior.valid(key, slot, token, _now())) {
        return _issue(prior);
      }
      final envelope = slot.envelope;
      // An envelope nobody can open protects nothing, so removing it needs
      // no ceremony; the engine still guards the wallet's own deletion.
      if (envelope != null) {
        final aesKey = await _unlock(envelope, token);
        try {
          envelope.open(aesKey);
        } finally {
          aesKey.fillRange(0, aesKey.length, 0);
        }
      }
      await _ensureUnchanged(key, slot, token);
      return _issue(_permit(key, slot, token));
    });
  }

  Future<String?> _prepareDeleteAfterPassword(
    String key,
    int expectedRevision,
  ) => _exclusive((token) async {
    final slot = await _passkeySlot(key, expectedRevision);
    _ensureCurrent(token);
    return _issue(_permit(key, slot, token));
  });

  Future<void> _delete(String key, String? authorization) async {
    if (authorization?.startsWith(PasskeyCredentialBackend._permitPrefix) ??
        false) {
      return _exclusive((token) async {
        final permit = _permits.remove(authorization);
        final slot = await _slot(key);
        if (slot == null) {
          if (await _deviceHolds(key)) {
            throw const WalletAccessException(
              WalletAccessFailure.staleOperation,
            );
          }
          return;
        }
        if (permit == null ||
            !permit.valid(key, slot, token, _now()) ||
            await _deviceHolds(key)) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
        await _removeSlot(key);
      });
    }
    if (await _deviceHolds(key)) {
      await _base.delete(key, authorization: authorization);
      // Removing a wallet's record leaves no envelope behind, inert or not.
      if (await _slot(key) != null) await _removeSlot(key);
      return;
    }
    if (await _slot(key) == null) {
      return _base.delete(key, authorization: authorization);
    }
    // A passkey record is removed only with this layer's own permit.
    throw const WalletAccessException(WalletAccessFailure.staleOperation);
  }
}
