part of 'auth_bloc.dart';

/// Opens a wallet moved from another device or restored from a passkey
/// backup, with a password this device generates and keeps.
extension _ManagedImport on AuthBloc {
  Future<void> _onManagedImport(
    AuthManagedImportRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    if (_authOperation != null) return;
    final access = _walletAccess;
    if (access == null) {
      emit(
        AuthBlocState.error(
          AuthException(
            'Wallet import is unavailable',
            type: AuthExceptionType.generalAuthError,
          ),
        ),
      );
      return;
    }
    final operation = _beginAuthOperation();
    final secret = event.secret;
    final walletType = secret.type.walletType;
    try {
      await _pauseAuthUserWatcher();
      if (!_ownsAuthOperation(operation, emit)) return;
      emit(AuthBlocState.loading());
      WalletLoadTimeline.instance.mark(WalletLoadMark.signInStarted);
      final user = await access.importWallet(
        walletName: event.walletName,
        walletType: walletType,
        mnemonic: secret.seed,
        useDeviceProtection: event.useDeviceProtection,
        initialMetadata: _initialWalletMetadata(
          walletType: walletType,
          provenance: WalletProvenance.imported,
          createdAt: DateTime.now(),
          // The person confirmed holding the phrase on the other device;
          // moving the wallet does not change that.
          hasBackup: secret.phraseConfirmed,
          recoveryEvidence: secret.phraseConfirmed
              ? RecoveryEvidence.phraseConfirmed
              : RecoveryEvidence.none,
          activatedCoins: _filterBlockedAssets(enabledByDefaultCoins).toSet(),
        ),
      );
      if (!_ownsAuthOperation(operation, emit)) return;
      _emitLoggedInState(emit, user);
      _listenToAuthStateChanges();
    } catch (error, stackTrace) {
      if (!_ownsAuthOperation(operation, emit)) return;
      await _emitAuthFailure(
        emit: emit,
        errorMsg: switch (event.source) {
          ManagedImportSource.movedFromDevice =>
            'Unable to open the moved wallet',
          ManagedImportSource.passkeyBackup =>
            'Unable to open the restored wallet',
        },
        error: error,
        stackTrace: stackTrace,
        flow: AuthFlow.restore,
      );
    } finally {
      _endAuthOperation(operation);
    }
  }
}
