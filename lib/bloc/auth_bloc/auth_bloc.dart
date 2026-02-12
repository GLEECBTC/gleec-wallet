import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show PrivateKeyPolicy;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

part 'auth_bloc_event.dart';
part 'auth_bloc_state.dart';
part 'trezor_auth_mixin.dart';

/// AuthBloc is responsible for managing the authentication state of the
/// application. It handles events such as login and logout changes.
class AuthBloc extends Bloc<AuthBlocEvent, AuthBlocState> with TrezorAuthMixin {
  /// Handles [AuthBlocEvent]s and emits [AuthBlocState]s.
  /// [_kdfSdk] is an instance of [KomodoDefiSdk] used for authentication.
  AuthBloc(
    this._kdfSdk,
    this._walletsRepository,
    this._settingsRepository,
    this._tradingStatusService,
  ) : super(AuthBlocState.initial()) {
    on<AuthModeChanged>(_onAuthChanged);
    on<AuthStateClearRequested>(_onClearState);
    on<AuthSignOutRequested>(_onLogout);
    on<AuthSignInRequested>(_onLogIn);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthRestoreRequested>(_onRestore);
    on<AuthSeedBackupConfirmed>(_onSeedBackupConfirmed);
    on<AuthWalletDownloadRequested>(_onWalletDownloadRequested);
    on<AuthStateRestoreRequested>(_onStateRestoreRequested);
    on<AuthLifecycleCheckRequested>(_onLifecycleCheckRequested);
    setupTrezorEventHandlers();
  }

  final KomodoDefiSdk _kdfSdk;
  final WalletsRepository _walletsRepository;
  final SettingsRepository _settingsRepository;
  final TradingStatusService _tradingStatusService;
  StreamSubscription<KdfUser?>? _authChangesSubscription;
  @override
  final _log = Logger('AuthBloc');

  @override
  KomodoDefiSdk get _sdk => _kdfSdk;

  /// Filters out geo-blocked assets from a list of coin IDs.
  /// This ensures that blocked assets are not added to wallet metadata during
  /// registration or restoration.
  ///
  /// TODO: UX Improvement - For faster wallet creation/restoration, consider
  /// adding all default coins to metadata initially, then removing blocked ones
  /// when bouncer status is confirmed. This would require:
  /// 1. Reactive metadata updates when trading status changes
  /// 2. Coordinated cleanup across wallet metadata and activated coins
  /// 3. Handling edge cases where user manually re-adds a blocked coin
  /// See TradingStatusService._currentStatus for related startup optimizations.
  @override
  List<String> _filterBlockedAssets(List<String> coinIds) {
    return coinIds.where((coinId) {
      final assets = _kdfSdk.assets.findAssetsByConfigId(coinId);
      if (assets.isEmpty) return true; // Keep unknown assets for now
      return !_tradingStatusService.isAssetBlocked(assets.single.id);
    }).toList();
  }

  @override
  Future<void> close() async {
    await _authChangesSubscription?.cancel();
    await super.close();
  }

  Future<bool> _areWeakPasswordsAllowed() async {
    final settings = await _settingsRepository.loadSettings();
    return settings.weakPasswordsAllowed;
  }

  Future<void> _onLogout(
    AuthSignOutRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    _log.info('Logging out from a wallet');
    emit(AuthBlocState.loading());
    try {
      await _kdfSdk.auth.signOut();
    } catch (e, s) {
      // Do not crash the app on sign-out errors (e.g., KDF not stopping in time).
      // Log and continue to clear local auth state so UI can recover.
      _log.shout('Error during sign out, proceeding to reset state', e, s);
    } finally {
      // Explicitly disconnect SSE on sign-out
      _log.info('User signed out, disconnecting SSE...');
      try {
        _kdfSdk.streaming.disconnect();
      } on StateError {
        // SDK has been disposed, skip disconnect
        _log.info('SDK already disposed, skipping SSE disconnect');
      }
      
      await _authChangesSubscription?.cancel();
      emit(AuthBlocState.initial());
    }
  }

  Future<void> _onLogIn(
    AuthSignInRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      if (event.wallet.isLegacyWallet) {
        return add(
          AuthRestoreRequested(
            wallet: event.wallet,
            password: event.password,
            seed: await event.wallet.getLegacySeed(event.password),
          ),
        );
      }

      emit(AuthBlocState.loading());

      _log.info('Logging in to an existing wallet.');
      final weakPasswordsAllowed = await _areWeakPasswordsAllowed();
      await _kdfSdk.auth.signIn(
        walletName: event.wallet.name,
        password: event.password,
        options: AuthOptions(
          derivationMethod: event.wallet.config.type == WalletType.hdwallet
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
          allowWeakPassword: weakPasswordsAllowed,
        ),
      );
      final KdfUser? currentUser = await _kdfSdk.auth.currentUser;
      if (currentUser == null) {
        return emit(AuthBlocState.error(AuthException.notSignedIn()));
      }

      _log.info('Successfully logged in to wallet');
      emit(AuthBlocState.loggedIn(currentUser));
      
      // Explicitly connect SSE after successful login
      _log.info('User authenticated, connecting SSE for streaming...');
      _kdfSdk.streaming.connectIfNeeded();
      
      _listenToAuthStateChanges();
    } catch (e, s) {
      if (e is AuthException) {
        // Preserve the original error type for specific errors like incorrect password
        _log.shout(
          'Auth error during login for wallet ${event.wallet.name}',
          e,
          s,
        );
        emit(AuthBlocState.error(e));
      } else {
        // For non-auth exceptions, use a generic error type
        final errorMsg = 'Failed to login wallet ${event.wallet.name}';
        _log.shout(errorMsg, e, s);
        emit(
          AuthBlocState.error(
            AuthException(errorMsg, type: AuthExceptionType.generalAuthError),
          ),
        );
      }
      await _authChangesSubscription?.cancel();
    }
  }

  Future<void> _onAuthChanged(
    AuthModeChanged event,
    Emitter<AuthBlocState> emit,
  ) async {
    emit(AuthBlocState(mode: event.mode, currentUser: event.currentUser));
  }

  Future<void> _onClearState(
    AuthStateClearRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    await _authChangesSubscription?.cancel();
    emit(AuthBlocState.initial());
  }

  Future<void> _onRegister(
    AuthRegisterRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      emit(AuthBlocState.loading());
      if (await _didSignInExistingWallet(event.wallet, event.password)) {
        add(
          AuthSignInRequested(wallet: event.wallet, password: event.password),
        );
        _log.warning(
          'Wallet ${event.wallet.name} already exists, attempting sign-in',
        );
        return;
      }

      _log.info('Registering a new wallet');
      final weakPasswordsAllowed = await _areWeakPasswordsAllowed();
      await _kdfSdk.auth.register(
        password: event.password,
        walletName: event.wallet.name,
        options: AuthOptions(
          derivationMethod: event.wallet.config.type == WalletType.hdwallet
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
          allowWeakPassword: weakPasswordsAllowed,
        ),
      );

      _log.info(
        'Registered a new wallet, setting up metadata and logging in...',
      );
      await _kdfSdk.setWalletType(event.wallet.config.type);
      await _kdfSdk.confirmSeedBackup(hasBackup: false);
      // Filter out geo-blocked assets from default coins before adding to wallet
      final allowedDefaultCoins = _filterBlockedAssets(enabledByDefaultCoins);
      await _kdfSdk.addActivatedCoins(allowedDefaultCoins);

      final currentUser = await _kdfSdk.auth.currentUser;
      if (currentUser == null) {
        throw Exception('Registration failed: user is not signed in');
      }
      emit(AuthBlocState.loggedIn(currentUser));
      _listenToAuthStateChanges();
    } catch (e, s) {
      final errorMsg = 'Failed to register wallet ${event.wallet.name}';
      _log.shout(errorMsg, e, s);
      emit(
        AuthBlocState.error(
          AuthException(errorMsg, type: AuthExceptionType.generalAuthError),
        ),
      );
      await _authChangesSubscription?.cancel();
    }
  }

  Future<void> _onRestore(
    AuthRestoreRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      // Legacy wallets: sanitize base name, try sign-in, then resolve
      // uniqueness only if needed. Non-legacy restores (seed imports) keep the
      // user-provided name unchanged.
      Wallet workingWallet = event.wallet;
      if (event.wallet.isLegacyWallet) {
        final String baseName = _walletsRepository.sanitizeLegacyMigrationName(
          event.wallet.name,
        );
        final Wallet sanitizedBaseWallet = event.wallet.copyWith(
          name: baseName,
        );

        // Attempt sign-in with sanitized base name first to avoid creating a
        // suffixed duplicate when a migrated wallet already exists.
        if (await _didSignInExistingWallet(
          sanitizedBaseWallet,
          event.password,
        )) {
          add(
            AuthSignInRequested(
              wallet: sanitizedBaseWallet,
              password: event.password,
            ),
          );
          _log.warning('Wallet $baseName already exists, attempting sign-in');
          return;
        }

        // Otherwise, resolve the lowest available unique name for registration.
        final String uniqueName = await _walletsRepository
            .resolveUniqueWalletName(baseName);
        workingWallet = event.wallet.copyWith(name: uniqueName);
      }

      if (await _didSignInExistingWallet(workingWallet, event.password)) {
        add(
          AuthSignInRequested(wallet: workingWallet, password: event.password),
        );
        _log.warning(
          'Wallet ${workingWallet.name} already exists, attempting sign-in',
        );
        return;
      }

      emit(AuthBlocState.loading());
      _log.info('Restoring wallet from a seed');
      final weakPasswordsAllowed = await _areWeakPasswordsAllowed();
      await _kdfSdk.auth.register(
        password: event.password,
        walletName: workingWallet.name,
        mnemonic: Mnemonic.plaintext(event.seed),
        options: AuthOptions(
          derivationMethod: workingWallet.config.type == WalletType.hdwallet
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
          allowWeakPassword: weakPasswordsAllowed,
        ),
      );

      _log.info(
        'Successfully restored wallet from a seed. '
        'Setting up wallet metadata and logging in...',
      );
      await _kdfSdk.setWalletType(workingWallet.config.type);
      await _kdfSdk.confirmSeedBackup(
        hasBackup: workingWallet.config.hasBackup,
      );
      // Filter out geo-blocked assets from default coins before adding to wallet
      final allowedDefaultCoins = _filterBlockedAssets(enabledByDefaultCoins);
      await _kdfSdk.addActivatedCoins(allowedDefaultCoins);
      if (workingWallet.config.activatedCoins.isNotEmpty) {
        // Seed import files and legacy wallets may contain removed or unsupported
        // coins, so we filter them out before adding them to the wallet metadata.
        final availableWalletCoins = _filterOutUnsupportedCoins(
          workingWallet.config.activatedCoins,
        );
        // Also filter out geo-blocked assets from restored wallet coins
        final allowedWalletCoins = _filterBlockedAssets(availableWalletCoins);
        await _kdfSdk.addActivatedCoins(allowedWalletCoins);
      }

      // Delete legacy wallet on successful restoration & login to avoid
      // duplicates in the wallet list
      if (event.wallet.isLegacyWallet) {
        _log.info(
          'Migration successful. '
          'Deleting legacy wallet ${workingWallet.name}',
        );
        await _walletsRepository.deleteWallet(
          event.wallet,
          password: event.password,
        );
      }

      final currentUser = await _kdfSdk.auth.currentUser;
      if (currentUser == null) {
        throw Exception('Restoration from seed failed: user is not signed in');
      }

      emit(AuthBlocState.loggedIn(currentUser));
      _listenToAuthStateChanges();
    } catch (e, s) {
      final errorMsg = 'Failed to restore existing wallet ${event.wallet.name}';
      _log.shout(errorMsg, e, s);
      emit(
        AuthBlocState.error(
          AuthException(errorMsg, type: AuthExceptionType.generalAuthError),
        ),
      );
      await _authChangesSubscription?.cancel();
    }
  }

  Future<bool> _didSignInExistingWallet(Wallet wallet, String password) async {
    final existingWallets = await _kdfSdk.auth.getUsers();
    final walletExists = existingWallets.any(
      (KdfUser user) => user.walletId.name == wallet.name,
    );
    if (walletExists) {
      return true;
    }

    return false;
  }

  Future<void> _onSeedBackupConfirmed(
    AuthSeedBackupConfirmed event,
    Emitter<AuthBlocState> emit,
  ) async {
    // emit the current user again to pull in the updated seed backup status
    // and make the backup notification banner disappear
    await _kdfSdk.confirmSeedBackup();
    emit(
      AuthBlocState(
        mode: AuthorizeMode.logIn,
        currentUser: await _kdfSdk.auth.currentUser,
      ),
    );
  }

  Future<void> _onWalletDownloadRequested(
    AuthWalletDownloadRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      final Wallet? wallet = (await _kdfSdk.auth.currentUser)?.wallet;
      if (wallet == null) return;

      await _walletsRepository.downloadEncryptedWallet(wallet, event.password);

      await _kdfSdk.confirmSeedBackup();
      emit(
        AuthBlocState(
          mode: AuthorizeMode.logIn,
          currentUser: await _kdfSdk.auth.currentUser,
        ),
      );
    } catch (e, s) {
      _log.shout('Failed to download wallet data', e, s);
    }
  }

  Future<void> _onStateRestoreRequested(
    AuthStateRestoreRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    final bool signedIn = await _kdfSdk.auth.isSignedIn();
    final KdfUser? user = signedIn ? await _kdfSdk.auth.currentUser : null;
    emit(
      AuthBlocState(
        mode: signedIn ? AuthorizeMode.logIn : AuthorizeMode.noLogin,
        currentUser: user,
      ),
    );

    if (signedIn) {
      _listenToAuthStateChanges();
    }
  }

  Future<void> _onLifecycleCheckRequested(
    AuthLifecycleCheckRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    // Ensure KDF is healthy before checking user state
    // This helps recover from situations where MM2 becomes unavailable
    // (e.g., after app backgrounding on mobile platforms)
    try {
      await _kdfSdk.auth.ensureKdfHealthy();
    } catch (e) {
      _log.warning('Failed to ensure KDF health during lifecycle check: $e');
      // Continue anyway - the health check is best-effort
    }

    final currentUser = await _kdfSdk.auth.currentUser;

    // Do not emit any state if the user is currently attempting to log in.
    // TODO(takenagain)!: This is a temporary workaround to avoid emitting
    // AuthBlocState.loggedIn while the user is still logging in.
    // This should be replaced with a more robust solution.
    if (currentUser != null && !state.isLoading) {
      emit(AuthBlocState.loggedIn(currentUser));
      _listenToAuthStateChanges();
    }
  }

  @override
  void _listenToAuthStateChanges() {
    _authChangesSubscription?.cancel();
    _authChangesSubscription = _kdfSdk.auth.watchCurrentUser().listen((user) {
      final AuthorizeMode event = user != null
          ? AuthorizeMode.logIn
          : AuthorizeMode.noLogin;
      add(AuthModeChanged(mode: event, currentUser: user));
      
      // Tie SSE connection lifecycle to authentication state
      if (user != null) {
        // User authenticated - connect SSE for balance/tx history streaming
        _log.info('User authenticated, connecting SSE for streaming...');
        try {
          _kdfSdk.streaming.connectIfNeeded();
        } on StateError {
          // SDK has been disposed, skip connect
          _log.info('SDK already disposed, skipping SSE connect');
        }
      } else {
        // User signed out - disconnect SSE to clean up resources
        _log.info('User signed out, disconnecting SSE...');
        try {
          _kdfSdk.streaming.disconnect();
        } on StateError {
          // SDK has been disposed, skip disconnect
          _log.info('SDK already disposed, skipping SSE disconnect');
        }
      }
    });
  }

  List<String> _filterOutUnsupportedCoins(List<String> coins) {
    final unsupportedAssets = coins.where(
      (coin) => _kdfSdk.assets.findAssetsByConfigId(coin).isEmpty,
    );
    _log.warning(
      'Skipping import of unsupported assets: '
      '${unsupportedAssets.map((coin) => coin).join(', ')}',
    );

    final supportedAssets = coins
        .map((coin) => _kdfSdk.assets.findAssetsByConfigId(coin))
        .where((assets) => assets.isNotEmpty)
        .map((assets) => assets.single.id.id);
    _log.info('Import supported assets: ${supportedAssets.join(', ')}');

    return supportedAssets.toList();
  }
}
