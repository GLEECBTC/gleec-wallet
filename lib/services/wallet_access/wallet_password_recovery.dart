part of 'wallet_access_service.dart';

/// Finishing, at password sign-in, a password change that was interrupted.
/// The journaled envelope yields the former password only to someone who
/// types the new one.
extension _PasswordRecovery on WalletAccessService {
  Future<KdfUser?> _recoverPasswordRotation(
    Wallet wallet,
    String password,
    bool? allowWeakPassword,
  ) => _runAccessOperation((revision) async {
    final users = await _sdk.auth.getUsers();
    final user = users.firstWhereOrNull(wallet.matchesKdfUser);
    if (user == null) return null;
    final WalletAccessRecord? record;
    try {
      record = await _recordFor(WalletAccessService.entryId(user));
    } on WalletAccessException {
      // What this build cannot read, it cannot recover either.
      return null;
    }
    final envelope = record?.rotationEnvelope;
    if (record == null || envelope == null) return null;
    final previous = await PasswordRotationEnvelope.open(
      password,
      envelope,
      record.entryId,
    );
    _ensureRevision(revision);
    // Ordinary sign-in will check a supplied old password.
    if (previous == null) return null;
    final options = await signInOptionsFor(
      user,
      allowWeakPassword: allowWeakPassword,
    );
    _ensureRevision(revision);
    final (active, confirmed) = await _signInAcrossRotation(
      user.walletId.name,
      options,
      password: password,
      previous: previous,
      revision: revision,
    );
    // Unconfirmed, the session is the caller's to show; nothing is repaired
    // on the strength of it.
    if (!confirmed) return active;
    if (WalletAccessService.entryId(active) != record.entryId) {
      await _closeEngineSession(active);
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    if (_isRevisionCurrent(revision)) {
      try {
        await _finishRotation(record, password, revision);
      } on Object {
        // KDF has verified the supplied new password. A failed device-vault
        // repair must not prevent password-only access; the journal is kept
        // and the repair retried at the next password sign-in.
      }
    }
    return active;
  });

  /// Opens the wallet with the new password, applying it first when the
  /// engine still holds the former one. The flag is false when the engine
  /// opened the session but could not be asked to confirm the new password.
  /// A session that the new password does not open is never returned.
  Future<(KdfUser, bool)> _signInAcrossRotation(
    String walletName,
    AuthOptions options, {
    required String password,
    required String previous,
    required _AccessRevision revision,
  }) async {
    /// Null when the engine cannot say.
    Future<bool?> accepts(KdfUser active, String candidate) async {
      try {
        await _sdk.auth.verifyPassword(
          password: candidate,
          expectedWalletId: active.walletId,
        );
        return true;
      } on AuthException catch (error) {
        return error.type == AuthExceptionType.incorrectPassword ? false : null;
      } on Object {
        return null;
      }
    }

    KdfUser? active;
    try {
      active = await _sdk.auth.signIn(
        walletName: walletName,
        password: password,
        options: options,
      );
    } on AuthException catch (error) {
      if (error.type != AuthExceptionType.incorrectPassword) rethrow;
    }
    if (active != null) {
      final accepted = await accepts(active, password);
      if (accepted != false) return (active, accepted ?? false);
      // The engine handed back a session it already had open, which the new
      // password does not match. The former one is applied to it below.
    }
    final session =
        active ??
        await _sdk.auth.signIn(
          walletName: walletName,
          password: previous,
          options: options,
        );
    try {
      await _sdk.auth.verifyPassword(
        password: previous,
        expectedWalletId: session.walletId,
      );
      final context = await _sdk.auth.captureSessionContext();
      _ensureRevision(revision);
      await _sdk.auth.updatePassword(
        currentPassword: previous,
        newPassword: password,
        expectedWalletId: session.walletId,
        expectedSession: context,
      );
    } on Object {
      // This session answers to the former password, not the one typed.
      await _closeEngineSession(session);
      rethrow;
    }
    final accepted = await accepts(session, password);
    if (accepted == false) {
      await _closeEngineSession(session);
      throw AuthException(
        'Wallet credential verification failed',
        type: AuthExceptionType.incorrectPassword,
      );
    }
    return (session, accepted ?? false);
  }
}
