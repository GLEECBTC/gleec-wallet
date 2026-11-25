part of 'auth_bloc.dart';

/// Hands a session the engine has opened to the access layer, so that what
/// the app shows never disagrees with whether the engine is signed in.
extension _EngineSessionAttach on AuthBloc {
  /// Finishes a password change that was interrupted, if this password is the
  /// one it was changing to. Returns the user that recovery signed in, or
  /// null when ordinary sign-in should proceed.
  Future<KdfUser?> _recoverInterruptedPasswordChange(
    Wallet wallet,
    String password,
    bool allowWeakPassword,
  ) async {
    try {
      return await _walletAccess?.recoverPasswordRotation(
        wallet,
        password,
        allowWeakPassword: allowWeakPassword,
      );
    } on WalletAccessException catch (error) {
      // Recovery is a repair before sign-in, not a condition of it. Busy in
      // another tab or interrupted, it stays journaled and has closed any
      // session it opened; the engine still decides whether this password
      // opens the wallet.
      _log.fine('Password-change recovery skipped: ${error.failure.name}');
      return null;
    }
  }

  /// Completes a sign-in the engine has already performed.
  ///
  /// When the attempt can no longer count as an authentication, because the
  /// app was left while the engine started or the engine cannot confirm the
  /// session just now, the session is attached covered and still published:
  /// the lock screen asks for a fresh unlock. Reporting a failure instead
  /// would leave the engine signed in behind a signed-out app, and every
  /// retry refused as already signed in. Any other failure closes the engine
  /// session before it is reported, so a retry starts clean.
  Future<void> _attachSignedInSession(
    KdfUser user, {
    required Object? attempt,
    required String password,
  }) async {
    final access = _walletAccess;
    if (access == null) return;
    try {
      await access.didAuthenticate(
        user,
        expectedAttempt: attempt,
        password: password,
      );
    } on Object catch (error) {
      if (_sessionStandsUnconfirmed(error)) {
        try {
          await access.attachCoveredSession(user);
          return;
        } on Object {
          // The engine no longer holds this session; report the failure.
        }
      }
      await _abandonEngineSession(user);
      rethrow;
    }
  }

  bool _sessionStandsUnconfirmed(Object error) =>
      error is AuthIdentityUnavailableException ||
      (error is AuthException &&
          error.type == AuthExceptionType.apiConnectionError) ||
      (error is WalletAccessException &&
          error.failure == WalletAccessFailure.staleOperation);

  Future<void> _abandonEngineSession(KdfUser user) async {
    try {
      final current = await _kdfSdk.auth.currentUser;
      if (current?.walletId.name != user.walletId.name) return;
      await _kdfSdk.auth.signOut();
      await _walletAccess?.observeEngineUser(null);
    } on Object catch (error) {
      // The sign-in failure is what gets reported. A session that could not
      // be closed is adopted by the next lifecycle check.
      _log.warning(
        'Could not close the session of a failed sign-in '
        '(${error.runtimeType})',
      );
    }
  }
}
