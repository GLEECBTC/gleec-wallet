part of 'auth_bloc.dart';

/// Opens a wallet with the credential this device keeps for it.
extension _ManagedSignIn on AuthBloc {
  Future<void> _onManagedSignIn(
    AuthManagedSignInRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    if (_authOperation != null) return;
    final access = _walletAccess;
    if (access == null) return;
    // A sheet that outlived the sign-in can ask again. Starting over would
    // revoke the open session's authorizations and show the app signed out
    // while the engine keeps the wallet open.
    if (state.currentUser?.walletId.name == event.wallet.name) return;
    final operation = _beginAuthOperation();
    try {
      await _pauseAuthUserWatcher();
      emit(AuthBlocState.loading());
      final user = await access.signInManaged(
        event.wallet,
        automatic: event.automatic,
      );
      if (!_ownsAuthOperation(operation, emit)) return;
      _emitLoggedInState(emit, user);
      _listenToAuthStateChanges();
    } catch (error, stackTrace) {
      final canceled =
          error is WalletAccessException &&
          error.failure == WalletAccessFailure.canceled;
      _logManagedSignInFailure(
        error,
        stackTrace,
        canceled: canceled,
        automatic: event.automatic,
      );
      if (!_ownsAuthOperation(operation, emit)) return;
      if (canceled && event.automatic) {
        // The browser cancels an automatic attempt it cannot prompt for, not
        // the user. Reset quietly; the sheet's unlock is still there.
        emit(AuthBlocState.initial());
        return;
      }
      emit(
        AuthBlocState.error(
          AuthException(
            canceled
                ? 'authManagedUnlockCanceled'.tr()
                : 'authManagedUnlockFailed'.tr(),
            type: AuthExceptionType.generalAuthError,
          ),
        ),
      );
    } finally {
      _endAuthOperation(operation);
    }
  }
}
