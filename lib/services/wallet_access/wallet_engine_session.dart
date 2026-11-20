part of 'wallet_access_service.dart';

/// Keeps the engine's session and what the app shows in step when a sign-in
/// outlives the authorization it started under.
extension _EngineSession on WalletAccessService {
  /// Signs the engine in to [user], or returns the session it already holds
  /// for that wallet. The engine refuses a second sign-in, so a repeated
  /// unlock would otherwise fail for as long as that session stays open. The
  /// caller still verifies [password] against the returned session.
  Future<KdfUser> _openEngineSession(KdfUser user, String password) async {
    final current = await _sdk.auth.currentUser;
    if (current != null && current.walletId == user.walletId) return current;
    return _sdk.auth.signIn(
      walletName: user.walletId.name,
      password: password,
      options: user.walletId.authOptions,
    );
  }

  /// Runs the steps that follow an engine sign-in. However they end, the
  /// engine is never left signed in behind an app that reports a failure: the
  /// next attempt would be refused as already signed in.
  ///
  /// [complete] returns false when the engine opened another wallet than the
  /// one requested.
  Future<KdfUser> _settleEngineSignIn(
    KdfUser signedIn,
    _AccessRevision revision,
    Future<bool> Function() complete,
  ) async {
    try {
      if (await complete()) return signedIn;
    } on Object catch (error) {
      if (_sessionStandsUnconfirmed(error, revision)) {
        await _attachCovered(signedIn);
        return signedIn;
      }
      await _closeEngineSession(signedIn);
      rethrow;
    }
    await _closeEngineSession(signedIn);
    throw const WalletAccessException(WalletAccessFailure.staleOperation);
  }

  /// Whether [error] says nothing against a session the engine has opened:
  /// the app was left while the engine started, or the engine could not be
  /// asked to confirm it just now. Such a session is shown covered, as an
  /// observed one would be, and a fresh unlock confirms it.
  bool _sessionStandsUnconfirmed(Object error, _AccessRevision revision) =>
      error is AuthIdentityUnavailableException ||
      (error is AuthException &&
          error.type == AuthExceptionType.apiConnectionError) ||
      (error is WalletAccessException &&
          error.failure == WalletAccessFailure.staleOperation &&
          _onlyAuthorizationExpired(revision));

  /// Whether [revision] went stale only because the app lost focus or locked,
  /// rather than being superseded by another operation or a wallet change.
  bool _onlyAuthorizationExpired(_AccessRevision revision) =>
      identical(revision.owner, _operationOwner) &&
      revision.service == _revision &&
      revision.authorization != unlockCoordinator.authorizationGeneration;

  Future<void> _attachCovered(KdfUser user) async {
    await observeEngineUser(user);
    final attached = _sessionUser;
    if (attached == null ||
        WalletAccessService.entryId(attached) !=
            WalletAccessService.entryId(user)) {
      return;
    }
    try {
      // Names the wallet the engine is signed in to. It grants no unlock.
      await _writeChecked(WalletAccessService._lastKey, {
        'entryId': WalletAccessService.entryId(user),
        'walletId': user.walletId.toJson(),
      });
      await _writeChecked(WalletAccessService._signedOutKey, false);
    } on Object {
      // The next completed sign-in records it.
    }
  }

  /// Ends a session this service opened but could not hand to the app.
  Future<void> _closeEngineSession(KdfUser user) async {
    try {
      final current = await _sdk.auth.currentUser;
      if (current == null || current.walletId.name != user.walletId.name) {
        return;
      }
      await _sdk.auth.signOut();
    } on Object {
      // The caller's error stands. A session that could not be closed is
      // adopted by the next lifecycle check.
    }
  }
}
