import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';

/// Owns security settings navigation, seed backup progress and unbanning.
/// Private-key authorization, results and delivery belong to the screen-scoped
/// PrivateKeyExportBloc and its injected service. Legacy export flags below are
/// retained for compatibility; they do not authorize the current export flow.
class SecuritySettingsBloc
    extends Bloc<SecuritySettingsEvent, SecuritySettingsState> {
  /// Creates a new SecuritySettingsBloc.
  ///
  /// [initialState] The initial state for the bloc.
  /// [kdfSdk] The Komodo DeFi SDK instance for authentication operations.
  SecuritySettingsBloc(super.initialState, {required KomodoDefiSdk? kdfSdk})
    : _kdfSdk = kdfSdk {
    // Seed phrase events
    on<ResetEvent>(_onReset);
    on<ShowSeedEvent>(_onShowSeed);
    on<SeedConfirmEvent>(_onSeedConfirm);
    on<SeedConfirmedEvent>(_onSeedConfirmed);
    on<ShowSeedWordsEvent>(_onShowSeedWords);
    on<ShowSeedCopiedEvent>(_onSeedCopied);
    on<PasswordUpdateEvent>(_onPasswordUpdate);

    // Private key events - hybrid security approach
    on<AuthenticateForPrivateKeysEvent>(_onAuthenticateForPrivateKeys);
    on<ShowPrivateKeysEvent>(_onShowPrivateKeys);
    on<ShowPrivateKeysWordsEvent>(_onShowPrivateKeysWords);
    on<ShowPrivateKeysCopiedEvent>(_onPrivateKeysCopied);
    on<PrivateKeysDownloadRequestedEvent>(_onPrivateKeysDownloadRequested);
    on<ClearAuthenticationErrorEvent>(_onClearAuthenticationError);

    // Unban pubkeys events
    on<UnbanPubkeysEvent>(_onUnbanPubkeys);
    on<UnbanPubkeysCompletedEvent>(_onUnbanPubkeysCompleted);
    on<UnbanPubkeysFailedEvent>(_onUnbanPubkeysFailed);
  }

  /// The Komodo DeFi SDK instance for authentication operations.
  /// This is optional to support testing scenarios.
  final KomodoDefiSdk? _kdfSdk;

  /// Handles resetting the security settings to initial state.
  void _onReset(ResetEvent event, Emitter<SecuritySettingsState> emit) {
    emit(SecuritySettingsState.initialState());
  }

  /// Handles showing the seed phrase backup screen.
  void _onShowSeed(ShowSeedEvent event, Emitter<SecuritySettingsState> emit) {
    final newState = state.copyWith(
      step: SecuritySettingsStep.seedShow,
      showSeedWords: false,
      // Entering the flow is the honest start of "how long did backing up
      // take" - the confirmation screen alone would omit the reading and
      // writing-down that is most of the work.
      backupStartedAt: DateTime.now(),
    );
    emit(newState);
  }

  /// Handles toggling seed word visibility and tracking if user has viewed them.
  Future<void> _onShowSeedWords(
    ShowSeedWordsEvent event,
    Emitter<SecuritySettingsState> emit,
  ) async {
    final newState = state.copyWith(
      step: SecuritySettingsStep.seedShow,
      showSeedWords: event.isShow,
      isSeedSaved: state.isSeedSaved || event.isShow,
    );
    emit(newState);
  }

  /// Handles proceeding to seed phrase confirmation.
  void _onSeedConfirm(
    SeedConfirmEvent event,
    Emitter<SecuritySettingsState> emit,
  ) {
    final newState = state.copyWith(
      step: SecuritySettingsStep.seedConfirm,
      showSeedWords: false,
    );
    emit(newState);
  }

  /// Handles successful seed phrase confirmation.
  Future<void> _onSeedConfirmed(
    SeedConfirmedEvent event,
    Emitter<SecuritySettingsState> emit,
  ) async {
    final newState = state.copyWith(
      step: SecuritySettingsStep.seedSuccess,
      showSeedWords: false,
    );
    emit(newState);
  }

  /// Handles seed phrase being copied to clipboard.
  Future<void> _onSeedCopied(
    ShowSeedCopiedEvent event,
    Emitter<SecuritySettingsState> emit,
  ) async {
    emit(state.copyWith(isSeedSaved: true));
  }

  /// Handles showing the password update screen.
  void _onPasswordUpdate(
    PasswordUpdateEvent event,
    Emitter<SecuritySettingsState> emit,
  ) {
    final newState = state.copyWith(
      step: SecuritySettingsStep.passwordUpdate,
      showSeedWords: false,
    );
    emit(newState);
  }

  /// Legacy sign-in presence check retained for compatibility navigation.
  /// This does not validate a password or authorize private-key extraction.
  /// The current export flow uses PrivateKeyExportBloc's password boundary.
  Future<void> _onAuthenticateForPrivateKeys(
    AuthenticateForPrivateKeysEvent event,
    Emitter<SecuritySettingsState> emit,
  ) async {
    emit(state.copyWith(isAuthenticating: true, clearAuthError: true));

    try {
      // Verify user is authenticated without handling sensitive data
      if (_kdfSdk == null) {
        throw Exception('SDK not available');
      }

      final currentUser = await _kdfSdk.auth.currentUser;
      if (currentUser == null) {
        emit(
          state.copyWith(
            isAuthenticating: false,
            authError: 'User not authenticated',
          ),
        );
        return;
      }

      // Preserve the legacy navigation signal; this grants no export access.
      emit(
        state.copyWith(
          isAuthenticating: false,
          privateKeyAuthenticationSuccess: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isAuthenticating: false,
          authError: 'Authentication failed',
        ),
      );
    }
  }

  /// Handles showing the private keys screen.
  ///
  /// The export BLoC owns results; this event only selects the result screen.
  void _onShowPrivateKeys(
    ShowPrivateKeysEvent event,
    Emitter<SecuritySettingsState> emit,
  ) {
    final newState = state.copyWith(
      step: SecuritySettingsStep.privateKeyShow,
      showPrivateKeys: false,
      // Reset authentication success flag after use
      privateKeyAuthenticationSuccess: false,
      backupStartedAt: DateTime.now(),
    );
    emit(newState);
  }

  /// Handles toggling private key visibility in the UI.
  ///
  /// **Security Note**: This only controls UI visibility state.
  /// This compatibility flag does not control the current export BLoC.
  Future<void> _onShowPrivateKeysWords(
    ShowPrivateKeysWordsEvent event,
    Emitter<SecuritySettingsState> emit,
  ) async {
    final newState = state.copyWith(
      step: SecuritySettingsStep.privateKeyShow,
      showPrivateKeys: event.isShow,
      arePrivateKeysSaved: state.arePrivateKeysSaved || event.isShow,
    );
    emit(newState);
  }

  /// Handles private keys being copied to clipboard.
  Future<void> _onPrivateKeysCopied(
    ShowPrivateKeysCopiedEvent event,
    Emitter<SecuritySettingsState> emit,
  ) async {
    emit(state.copyWith(arePrivateKeysSaved: true));
  }

  /// Handles private keys being downloaded to a file.
  Future<void> _onPrivateKeysDownloadRequested(
    PrivateKeysDownloadRequestedEvent event,
    Emitter<SecuritySettingsState> emit,
  ) async {
    emit(state.copyWith(arePrivateKeysSaved: true));
  }

  /// Handles clearing authentication errors.
  void _onClearAuthenticationError(
    ClearAuthenticationErrorEvent event,
    Emitter<SecuritySettingsState> emit,
  ) {
    emit(state.copyWith(clearAuthError: true));
  }

  /// Handles unbanning all banned public keys.
  ///
  /// This method directly calls the SDK to unban pubkeys without requiring
  /// password authentication, as it's considered a non-destructive operation
  /// that improves wallet functionality.
  Future<void> _onUnbanPubkeys(
    UnbanPubkeysEvent event,
    Emitter<SecuritySettingsState> emit,
  ) async {
    if (_kdfSdk == null) {
      add(const UnbanPubkeysFailedEvent('SDK not available'));
      return;
    }

    emit(
      state.copyWith(
        isUnbanningPubkeys: true,
        unbanError: null,
        clearUnbanError: true,
      ),
    );

    try {
      final result = await _kdfSdk.pubkeys.unbanPubkeys(UnbanBy.all());
      add(UnbanPubkeysCompletedEvent(result));
    } catch (e) {
      add(UnbanPubkeysFailedEvent(e.toString()));
    }
  }

  /// Handles successful completion of pubkey unbanning.
  void _onUnbanPubkeysCompleted(
    UnbanPubkeysCompletedEvent event,
    Emitter<SecuritySettingsState> emit,
  ) {
    emit(
      state.copyWith(
        isUnbanningPubkeys: false,
        unbanResult: event.result,
        unbanError: null,
        clearUnbanError: true,
      ),
    );
  }

  /// Handles failed pubkey unbanning.
  void _onUnbanPubkeysFailed(
    UnbanPubkeysFailedEvent event,
    Emitter<SecuritySettingsState> emit,
  ) {
    emit(
      state.copyWith(
        isUnbanningPubkeys: false,
        unbanError: event.error,
        unbanResult: null,
      ),
    );
  }
}
