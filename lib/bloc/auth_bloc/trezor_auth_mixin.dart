part of 'auth_bloc.dart';

/// Mixin that exposes Trezor authentication helpers for [AuthBloc].
mixin TrezorAuthMixin on Bloc<AuthBlocEvent, AuthBlocState> {
  KomodoDefiSdk get _sdk;
  Logger get _log;

  /// Registers handlers for Trezor specific events.
  void setupTrezorEventHandlers() {
    on<AuthTrezorInitAndAuthStarted>(_onTrezorInitAndAuth);
    on<AuthTrezorPinProvided>(_onTrezorProvidePin);
    on<AuthTrezorPassphraseProvided>(_onTrezorProvidePassphrase);
    on<AuthTrezorCancelled>(_onTrezorCancel);
  }

  /// Abstract method overriden in [AuthBloc] to start listening
  /// to authentication state changes.
  void _listenToAuthStateChanges();

  /// Detaches `watchCurrentUser` while [AuthBloc] drives an explicit auth flow.
  ///
  /// Bloc 9 dispatches different event types concurrently; the SDK emits
  /// transient `null` during `signIn` / `register` (e.g. `signOut`, KDF stop).
  /// Without pausing, [AuthModeChanged] can preserve
  /// [AuthenticationStatus.initializing] and leave the UI stuck loading.
  Future<void> _pauseAuthUserWatcher();

  /// Filters out geo-blocked assets from a list of coin IDs.
  /// Implemented in [AuthBloc].
  List<String> _filterBlockedAssets(List<String> coinIds);

  Future<void> _onTrezorInitAndAuth(
    AuthTrezorInitAndAuthStarted event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      await _pauseAuthUserWatcher();
      emit(AuthBlocState.loading());

      const authOptions = AuthOptions(
        derivationMethod: DerivationMethod.hdWallet,
        privKeyPolicy: PrivateKeyPolicy.trezor(),
      );

      final Stream<AuthenticationState> authStream = _sdk.auth.signInStream(
        walletName: '', // handled internally by sdk
        password: '', // handled internally by sdk
        options: authOptions,
      );

      await for (final authState in authStream) {
        final mappedState = await _handleAuthenticationState(authState);
        emit(mappedState);
        if (authState.status == AuthenticationStatus.completed ||
            authState.status == AuthenticationStatus.error ||
            authState.status == AuthenticationStatus.cancelled) {
          _listenToAuthStateChanges();
          break;
        }
      }
    } catch (e) {
      _log.shout('Trezor authentication failed', e);
      emit(
        AuthBlocState.error(
          AuthException(e.toString(), type: AuthExceptionType.generalAuthError),
        ),
      );
    }
  }

  Future<AuthBlocState> _handleAuthenticationState(
    AuthenticationState authState,
  ) async {
    switch (authState.status) {
      case AuthenticationStatus.initializing:
        return AuthBlocState.trezorInitializing(
          message:
              authState.message ?? LocaleKeys.trezorInitializingMessage.tr(),
          taskId: authState.taskId,
        );
      case AuthenticationStatus.waitingForDevice:
        return AuthBlocState.trezorInitializing(
          message:
              authState.message ??
              LocaleKeys.trezorWaitingForDeviceMessage.tr(),
          taskId: authState.taskId,
        );
      case AuthenticationStatus.waitingForDeviceConfirmation:
        return AuthBlocState.trezorAwaitingConfirmation(
          message:
              authState.message ??
              LocaleKeys.trezorAwaitingConfirmationMessage.tr(),
          taskId: authState.taskId,
        );
      case AuthenticationStatus.pinRequired:
        return AuthBlocState.trezorPinRequired(
          message:
              authState.message ?? LocaleKeys.trezorPinRequiredMessage.tr(),
          taskId: authState.taskId!,
        );
      case AuthenticationStatus.passphraseRequired:
        return AuthBlocState.trezorPassphraseRequired(
          message:
              authState.message ??
              LocaleKeys.trezorPassphraseRequiredMessage.tr(),
          taskId: authState.taskId!,
        );
      case AuthenticationStatus.authenticating:
        return AuthBlocState.loading();
      case AuthenticationStatus.completed:
        return _setupTrezorWallet(authState);
      case AuthenticationStatus.error:
        final mappedError = _mapTrezorErrorMessage(authState.error);
        return AuthBlocState.error(
          AuthException(mappedError, type: AuthExceptionType.generalAuthError),
        );
      case AuthenticationStatus.cancelled:
        return AuthBlocState.error(
          AuthException(
            LocaleKeys.trezorAuthCancelledMessage.tr(),
            type: AuthExceptionType.generalAuthError,
          ),
        );
    }
  }

  String _mapTrezorErrorMessage(String? errorMessage) {
    if (errorMessage == null || errorMessage.trim().isEmpty) {
      return LocaleKeys.trezorAuthFailedMessage.tr();
    }

    final normalized = errorMessage.toLowerCase();
    if (normalized.contains('cancel')) {
      return LocaleKeys.trezorAuthCancelledMessage.tr();
    }
    if (normalized.contains('invalid pin') ||
        (normalized.contains('pin') && normalized.contains('invalid'))) {
      return LocaleKeys.trezorErrorInvalidPin.tr();
    }

    return errorMessage;
  }

  /// Sets up the Trezor wallet after successful authentication.
  /// This includes setting the wallet type, confirming seed backup,
  /// and adding the default activated coins.
  Future<AuthBlocState> _setupTrezorWallet(
    AuthenticationState authState,
  ) async {
    // This should not happen, but if it does then trezor initialization failed
    // and we should not proceed.
    if (authState.user == null) {
      return AuthBlocState.error(
        AuthException(
          LocaleKeys.trezorInitializationFailed.tr(),
          type: AuthExceptionType.generalAuthError,
        ),
      );
    }

    await _sdk.setWalletType(WalletType.trezor);
    await _sdk.confirmSeedBackup(hasBackup: true);
    if (authState.user!.wallet.config.activatedCoins.isEmpty) {
      // If no coins are activated, we assume this is the first time
      // the user is setting up their Trezor wallet.
      // Filter out geo-blocked assets from default coins before adding to wallet
      final allowedDefaultCoins = _filterBlockedAssets(enabledByDefaultCoins);
      await _sdk.addActivatedCoins(allowedDefaultCoins);
    }

    // Refresh the current user to pull in the updated wallet metadata
    // configured above.
    final updatedUser = await _sdk.auth.currentUser;
    return AuthBlocState.loggedIn(updatedUser!);
  }

  Future<void> _onTrezorProvidePin(
    AuthTrezorPinProvided event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      final taskId = state.authenticationState?.taskId;
      if (taskId == null) {
        emit(
          AuthBlocState.error(
            AuthException(
              LocaleKeys.trezorNoTaskIdFound.tr(),
              type: AuthExceptionType.generalAuthError,
            ),
          ),
        );
        return;
      }

      await _sdk.auth.setHardwareDevicePin(taskId, event.pin);
    } catch (e) {
      _log.shout('Failed to provide PIN', e);
      emit(
        AuthBlocState.error(
          AuthException(
            LocaleKeys.trezorProvidePinFailed.tr(),
            type: AuthExceptionType.generalAuthError,
          ),
        ),
      );
    }
  }

  Future<void> _onTrezorProvidePassphrase(
    AuthTrezorPassphraseProvided event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      final taskId = state.authenticationState?.taskId;
      if (taskId == null) {
        emit(
          AuthBlocState.error(
            AuthException(
              LocaleKeys.trezorNoTaskIdFound.tr(),
              type: AuthExceptionType.generalAuthError,
            ),
          ),
        );
        return;
      }

      await _sdk.auth.setHardwareDevicePassphrase(taskId, event.passphrase);
    } catch (e) {
      _log.shout('Failed to provide passphrase', e);
      emit(
        AuthBlocState.error(
          AuthException(
            LocaleKeys.trezorProvidePassphraseFailed.tr(),
            type: AuthExceptionType.generalAuthError,
          ),
        ),
      );
    }
  }

  Future<void> _onTrezorCancel(
    AuthTrezorCancelled event,
    Emitter<AuthBlocState> emit,
  ) async {
    final taskId = state.authenticationState?.taskId;
    if (taskId != null) {
      try {
        await _sdk.auth.cancelHardwareDeviceInitialization(taskId);
      } catch (e) {
        _log.shout('Failed to cancel Trezor initialization', e);
      }
    }
    emit(AuthBlocState.initial());
  }
}
