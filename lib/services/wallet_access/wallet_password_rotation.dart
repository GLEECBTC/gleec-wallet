part of 'wallet_access_service.dart';

/// Changing the wallet password across the engine, the vault and the journal,
/// and finishing a change that was interrupted.
///
/// A journaled envelope means "the engine may hold either password". It must
/// never outlive the knowledge that the engine kept the former one: a wallet
/// whose generated password nobody has seen opens only with its stored
/// credential.
extension _PasswordRotation on WalletAccessService {
  Future<PasswordChangeOutcome> _changePassword({
    required WalletId walletId,
    String? currentPassword,
    required String newPassword,
  }) => _runAccessOperation((revision) async {
    if (!SecurityUtils.checkPasswordRequirements(newPassword).isValid) {
      throw const WalletAccessException(WalletAccessFailure.incorrectPassword);
    }
    final user = await _resolve(walletId);
    final session = await _sdk.auth.captureSessionContext();
    final oldPassword = await _authorize(
      walletId,
      password: currentPassword,
      reason: 'Change wallet password',
      revision: revision,
    );
    final ensureCurrent = captureSensitiveOperation(walletId);
    void ensureDispatchable() {
      _ensureRevision(revision);
      _sdk.auth.ensureSessionContextCurrent(session);
      ensureCurrent();
    }

    final prior = await _recordFor(WalletAccessService.entryId(user));
    final record = prior != null && prior.managed
        ? await _journalRotation(
            prior,
            newPassword,
            oldPassword,
            ensureDispatchable,
          )
        : prior;
    await _dispatchPasswordChange(
      walletId: walletId,
      session: session,
      oldPassword: oldPassword,
      newPassword: newPassword,
      ensureDispatchable: ensureDispatchable,
      rotating: record?.rotationEnvelope == null ? null : record,
    );
    return _settlePasswordChange(
      user: user,
      record: record,
      newPassword: newPassword,
      revision: revision,
      ensureCurrent: ensureCurrent,
    );
  });

  /// Journals the former password sealed under the new one, so a change the
  /// engine completes can be finished even if the process dies meanwhile.
  Future<WalletAccessRecord> _journalRotation(
    WalletAccessRecord record,
    String newPassword,
    String oldPassword,
    void Function() ensureDispatchable,
  ) async {
    final envelope = await PasswordRotationEnvelope.seal(
      newPassword,
      oldPassword,
      record.entryId,
    );
    // Sealing is slow enough for the app to be left meanwhile. Nothing is
    // journaled for a change that can no longer reach the engine.
    ensureDispatchable();
    final rotating = record.copyWith(
      phase: 'rotating',
      rotationEnvelope: envelope,
    );
    try {
      await _saveRecord(rotating);
    } on Object {
      // A write can land and still report failure.
      await _withdrawRotation(rotating);
      rethrow;
    }
    return rotating;
  }

  /// Returns once the engine uses [newPassword]. Otherwise rethrows, after
  /// withdrawing [rotating] whenever the engine provably kept [oldPassword].
  Future<void> _dispatchPasswordChange({
    required WalletId walletId,
    required AuthSessionContext session,
    required String oldPassword,
    required String newPassword,
    required void Function() ensureDispatchable,
    required WalletAccessRecord? rotating,
  }) async {
    var dispatched = false;
    try {
      ensureDispatchable();
      await RpcDispatchGuard.run(
        () {
          ensureDispatchable();
          dispatched = true;
        },
        () => _sdk.auth.updatePassword(
          currentPassword: oldPassword,
          newPassword: newPassword,
          expectedWalletId: walletId,
          expectedSession: session,
        ),
        methods: const {'change_mnemonic_password'},
      );
    } on Object catch (error) {
      // Never sent, or refused: the engine keeps the former password. Any
      // other failure may have changed it, so the engine is asked which of
      // the two it accepts now.
      final refused =
          error is AuthException &&
          error.type == AuthExceptionType.incorrectPassword;
      final keptFormer = !dispatched || refused
          ? true
          : await _engineKeepsFormerPassword(
              walletId,
              session,
              oldPassword,
              newPassword,
            );
      if (keptFormer == false) return;
      if (keptFormer == true && rotating != null) {
        await _withdrawRotation(rotating);
      }
      rethrow;
    }
  }

  /// True when the engine still accepts [oldPassword], false when it accepts
  /// [newPassword] instead, null when it cannot say.
  Future<bool?> _engineKeepsFormerPassword(
    WalletId walletId,
    AuthSessionContext session,
    String oldPassword,
    String newPassword,
  ) async {
    Future<bool?> accepts(String password) async {
      try {
        await _sdk.auth.verifyPassword(
          password: password,
          expectedWalletId: walletId,
          expectedSession: session,
        );
        return true;
      } on AuthException catch (error) {
        return error.type == AuthExceptionType.incorrectPassword ? false : null;
      } on Object {
        return null;
      }
    }

    final former = await accepts(oldPassword);
    if (former != false) return former;
    return await accepts(newPassword) == true ? false : null;
  }

  /// The engine has accepted the new password. From here the caller is told
  /// what became of the stored credential, never that the change failed: the
  /// former password no longer opens the wallet.
  Future<PasswordChangeOutcome> _settlePasswordChange({
    required KdfUser user,
    required WalletAccessRecord? record,
    required String newPassword,
    required _AccessRevision revision,
    required void Function() ensureCurrent,
  }) async {
    final walletId = user.walletId;
    final deviceUnlock =
        record != null && record.managed && record.requiresAuthentication;
    try {
      await _sdk.auth.verifyPassword(
        password: newPassword,
        expectedWalletId: walletId,
      );
    } on AuthException catch (error) {
      // An engine that reports the change and then refuses the new password
      // contradicts itself. Everything stays journaled for recovery.
      if (error.type == AuthExceptionType.incorrectPassword) rethrow;
      return _unconfirmedChange(deviceUnlock);
    } on Object {
      return _unconfirmedChange(deviceUnlock);
    }
    if (record == null) {
      await _reattachAfterPasswordChange(user, revision, ensureCurrent);
      return PasswordChangeOutcome.completed;
    }
    void Function()? ensureCompletionCurrent;
    try {
      _ensureRevision(revision);
      ensureCompletionCurrent = await _finishRotation(
        record,
        newPassword,
        revision,
        waitForForeground: true,
        interactiveWalletId: walletId,
        ensureAuthorized: ensureCurrent,
      );
    } on Object {
      await _concedeStoredCredential(record);
      try {
        ensureCompletionCurrent = captureSensitiveOperation(walletId);
      } on Object {
        // Left or locked meanwhile: the session keeps whatever covers it.
      }
    }
    if (ensureCompletionCurrent != null) {
      await _reattachAfterPasswordChange(
        user,
        revision,
        ensureCompletionCurrent,
      );
    }
    return deviceUnlock && !await _storedCredentialFollows(record.entryId)
        ? PasswordChangeOutcome.deviceUnlockNeedsSetup
        : PasswordChangeOutcome.completed;
  }

  /// The engine reported the change but could not be asked to confirm the new
  /// password. Nothing stored is touched on that word alone: the journaled
  /// envelope finishes the change at the next password sign-in.
  PasswordChangeOutcome _unconfirmedChange(bool deviceUnlock) => deviceUnlock
      ? PasswordChangeOutcome.deviceUnlockNeedsSetup
      : PasswordChangeOutcome.completed;

  Future<bool> _storedCredentialFollows(String id) async {
    try {
      final record = await _recordFor(id);
      return record != null &&
          record.managed &&
          record.rotationEnvelope == null;
    } on Object {
      return false;
    }
  }

  /// The stored credential could not follow a password the engine verifiably
  /// uses. Records that the wallet now opens with the password alone, which
  /// is also what offers device unlock for setup again.
  Future<void> _concedeStoredCredential(WalletAccessRecord record) async {
    try {
      await _updateRecord(
        record.entryId,
        (current) =>
            current == null ||
                current.rotationEnvelope != record.rotationEnvelope
            ? null
            : current.copyWith(
                phase: 'ready',
                generated: false,
                managed: false,
                requiresAuthentication: true,
                protection: CredentialProtection.password,
                manager: PasswordManagerOutcome.offered,
                clearRotation: true,
              ),
      );
    } on Object {
      // The envelope left journaled finishes the change at the next password
      // sign-in.
    }
  }

  /// A password change leaves the engine session as it was, but the wallet
  /// now locks even if it did not before.
  Future<void> _reattachAfterPasswordChange(
    KdfUser user,
    _AccessRevision revision,
    void Function() ensureAuthorized,
  ) async {
    try {
      await _didAuthenticate(
        user,
        expectedRevision: revision,
        ensureAuthorized: ensureAuthorized,
      );
    } on Object {
      // Sign-in already recorded this wallet; only its lock is outstanding.
      try {
        ensureAuthorized();
        _ensureRevision(revision);
      } on Object {
        return;
      }
      unlockCoordinator.attachWallet(
        WalletAccessService.entryId(user),
        requiresAuthentication: true,
        authenticated: true,
        sessionIdentity: _sessionIdentity,
      );
    }
  }

  /// Removes a journaled change the engine never applied, so the stored
  /// credential is again the one that opens the wallet.
  Future<void> _withdrawRotation(WalletAccessRecord rotating) async {
    final envelope = rotating.rotationEnvelope;
    if (envelope == null) return;
    try {
      await _updateRecord(
        rotating.entryId,
        (current) => current == null || current.rotationEnvelope != envelope
            ? null
            : current.copyWith(phase: 'ready', clearRotation: true),
      );
    } on Object {
      // Left journaled, it is withdrawn the next time the engine accepts the
      // stored credential.
    }
  }

  Future<void Function()?> _finishRotation(
    WalletAccessRecord record,
    String newPassword,
    _AccessRevision revision, {
    bool waitForForeground = false,
    WalletId? interactiveWalletId,
    void Function()? ensureAuthorized,
  }) async {
    _ensureRevision(revision);
    ensureAuthorized?.call();
    if (record.requiresAuthentication && record.managed) {
      await _writeProtectedVerified(
        record.credentialKey,
        newPassword,
        revision,
        waitForForeground: waitForForeground,
      );
      if (await _readManaged(
            record,
            reason: 'Confirm updated wallet protection',
            purpose: 'verifyWrite',
            revision: revision,
            waitForForeground: waitForForeground,
            expectedCredential: newPassword,
          ) !=
          newPassword) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
    } else {
      await _backend.delete(record.credentialKey);
      if (await _backend.metadata(record.credentialKey) != null) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
    }
    final ensureCurrent = waitForForeground
        ? record.requiresAuthentication && record.managed
              ? captureSensitiveOperation(interactiveWalletId!)
              : ensureAuthorized
        : null;
    final keepsManaged = record.requiresAuthentication && record.managed;
    await _saveRecord(
      record.copyWith(
        phase: 'ready',
        generated: false,
        managed: keepsManaged,
        requiresAuthentication: true,
        protection: keepsManaged
            ? record.protection
            : CredentialProtection.password,
        manager: PasswordManagerOutcome.offered,
        clearRotation: true,
      ),
    );
    ensureCurrent?.call();
    return ensureCurrent;
  }
}
