import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show PrivateKeyPolicy;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_legacy_wallet_migration/komodo_legacy_wallet_migration.dart';
import 'package:logging/logging.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/analytics/events/auth_events.dart';
import 'package:web_dex/analytics/wallet_load_timeline.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/model/prepared_legacy_migration.dart';
import 'package:web_dex/model/wallet.dart';

part 'auth_bloc_event.dart';
part 'auth_bloc_state.dart';
part 'trezor_auth_mixin.dart';

/// AuthBloc is responsible for managing the authentication state of the
/// application. It handles events such as login and logout changes.
class AuthBloc extends Bloc<AuthBlocEvent, AuthBlocState> with TrezorAuthMixin {
  static const String _assetMigrationWarning =
      'Wallet restored, but some wallet assets could not be migrated.';
  static const Duration _postLoginStepTimeout = Duration(seconds: 5);

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
    on<AuthErrorReported>(_onErrorReported);
    on<AuthRegisterRequested>(_onRegister);
    on<AuthRestoreRequested>(_onRestore);
    on<AuthImportRequested>(_onImport);
    on<AuthLegacyMigrationRequested>(_onLegacyMigration);
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

  int _authRevision = 0;
  Object? _authOperation;

  Object _beginAuthOperation() {
    _authRevision++;
    return _authOperation = Object();
  }

  void _endAuthOperation(Object operation) {
    if (identical(_authOperation, operation)) _authOperation = null;
  }

  bool _ownsAuthOperation(Object operation, Emitter<AuthBlocState> emit) =>
      !emit.isDone && identical(_authOperation, operation);

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

  /// See [TrezorAuthMixin._pauseAuthUserWatcher].
  @override
  Future<void> _pauseAuthUserWatcher() async {
    await _authChangesSubscription?.cancel();
    _authChangesSubscription = null;
  }

  Future<bool> _areWeakPasswordsAllowed() async {
    final settings = await _settingsRepository.loadSettings();
    return settings.weakPasswordsAllowed;
  }

  Future<void> _disconnectStreamingForAuthLifecycle(String context) async {
    try {
      await _kdfSdk.disconnectStreaming();
    } catch (error, stackTrace) {
      _log.shout(
        'Failed to clean up KDF streams during $context',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _onLogout(
    AuthSignOutRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    final operation = _beginAuthOperation();
    _log.info('Logging out from a wallet');
    await _pauseAuthUserWatcher();
    if (!_ownsAuthOperation(operation, emit)) return;
    emit(AuthBlocState.loading());
    try {
      // Disable KDF streams while the authenticated KDF client is still alive.
      await _disconnectStreamingForAuthLifecycle('sign-out');
      if (!_ownsAuthOperation(operation, emit)) return;
      await _kdfSdk.auth.signOut();
    } catch (e, s) {
      // Do not crash the app on sign-out errors (e.g., KDF not stopping in time).
      // Log and continue to clear local auth state so UI can recover.
      _log.shout('Error during sign out, proceeding to reset state', e, s);
    } finally {
      // Explicitly disconnect SSE on sign-out
      if (_ownsAuthOperation(operation, emit)) {
        _log.info('User signed out, disconnecting SSE...');
        await _disconnectStreamingForAuthLifecycle('sign-out finalization');
      }
      if (_ownsAuthOperation(operation, emit)) {
        await _authChangesSubscription?.cancel();
        if (_ownsAuthOperation(operation, emit)) {
          _endAuthOperation(operation);
          WalletLoadTimeline.instance.reset();
          logAuthEvent(const AuthLogoutEventData(reason: 'user_initiated'));
          emit(AuthBlocState.initial());
        }
      }
    }
  }

  Future<void> _onLogIn(
    AuthSignInRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    final operation = _beginAuthOperation();
    final revision = _authRevision;
    try {
      if (event.wallet.isLegacyWallet) {
        await _pauseAuthUserWatcher();
        emit(
          AuthBlocState.error(
            AuthException(
              'Legacy wallets must be migrated through the compatibility flow.',
              type: AuthExceptionType.generalAuthError,
            ),
          ),
        );
        return;
      }

      await _pauseAuthUserWatcher();
      emit(AuthBlocState.loading());

      _log.info('Logging in to an existing wallet.');

      WalletLoadTimeline.instance.mark(WalletLoadMark.signInStarted);
      final weakPasswordsAllowed = await _areWeakPasswordsAllowed();
      if (!_ownsAuthOperation(operation, emit)) return;
      // `signIn` already returns the authenticated user, so the two
      // `currentUser` round trips this used to make were re-asking KDF for
      // something it had just handed over.
      final currentUser = await _kdfSdk.auth.signIn(
        walletName: event.wallet.name,
        password: event.password,
        options: AuthOptions(
          derivationMethod: event.wallet.config.type == WalletType.hdwallet
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
          allowWeakPassword: weakPasswordsAllowed,
        ),
      );

      if (!_ownsAuthOperation(operation, emit)) return;
      _log.info('Successfully logged in to wallet');
      _emitLoggedInState(emit, currentUser);
      _listenToAuthStateChanges();
      logAuthEvent(
        AuthSignInSucceededEventData(
          method: AuthMethod.password.value,
          flow: AuthFlow.signIn.value,
          hdType: event.wallet.config.type.name,
          durationMs:
              WalletLoadTimeline.instance.elapsedMsBetween(
                WalletLoadMark.signInStarted,
                WalletLoadMark.signedIn,
              ) ??
              0,
        ),
      );

      // Older wallets may need app metadata. Scope repair to this runtime
      // session so a delayed write cannot cross reauthentication.
      unawaited(
        _runPostLoginFinalizer(
          context: 'wallet sign-in ${event.wallet.name}',
          action: () => _runBoundedPostLoginStep(
            logMessage: 'Failed to repair missing wallet metadata',
            action: () async {
              final session = await _kdfSdk.auth.captureSessionContext();
              if (_authRevision != revision) return;
              await _repairMissingWalletMetadata(currentUser, session);
            },
          ),
        ),
      );
    } catch (e, s) {
      if (!_ownsAuthOperation(operation, emit)) return;
      logAuthEvent(
        AuthSignInFailedEventData(
          method: AuthMethod.password.value,
          flow: AuthFlow.signIn.value,
          failureType: e is AuthException
              ? e.type.name
              : AuthExceptionType.generalAuthError.name,
        ),
      );
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
    } finally {
      _endAuthOperation(operation);
    }
  }

  Future<void> _onAuthChanged(
    AuthModeChanged event,
    Emitter<AuthBlocState> emit,
  ) async {
    if (event is _AuthUserObserved && event.revision != _authRevision) return;
    if (event.currentUser == null) {
      final priorStatus = state.status;
      if (priorStatus == AuthenticationStatus.initializing ||
          priorStatus == AuthenticationStatus.authenticating) {
        _log.fine(
          'Ignoring null user from watcher during active auth flow '
          '(status=$priorStatus)',
        );
        return;
      }
    }

    if (event.currentUser != null) {
      emit(
        AuthBlocState(
          mode: event.mode,
          currentUser: event.currentUser,
          authenticationState: AuthenticationState.completed(
            event.currentUser!,
          ),
        ),
      );
    } else {
      final priorAuthState = state.authenticationState;
      final preserveErrorState =
          priorAuthState?.status == AuthenticationStatus.error;
      emit(
        AuthBlocState(
          mode: event.mode,
          currentUser: null,
          authenticationState: preserveErrorState ? priorAuthState : null,
          authError: preserveErrorState ? state.authError : null,
        ),
      );
    }
  }

  Future<void> _onErrorReported(
    AuthErrorReported event,
    Emitter<AuthBlocState> emit,
  ) async {
    emit(AuthBlocState.error(event.error));
  }

  Future<void> _onClearState(
    AuthStateClearRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    final revision = ++_authRevision;
    _authOperation = null;
    await _authChangesSubscription?.cancel();
    if (revision != _authRevision || emit.isDone) return;
    WalletLoadTimeline.instance.reset();
    emit(AuthBlocState.initial());
  }

  Future<void> _onRegister(
    AuthRegisterRequested event,
    Emitter<AuthBlocState> emit,
  ) => _createWallet(event.wallet, event.password, emit);

  Future<void> _onRestore(
    AuthRestoreRequested event,
    Emitter<AuthBlocState> emit,
  ) => _createWallet(event.wallet, event.password, emit, seed: event.seed);

  Future<void> _onImport(
    AuthImportRequested event,
    Emitter<AuthBlocState> emit,
  ) => _createWallet(event.wallet, event.password, emit, seed: event.seed);

  Future<void> _createWallet(
    Wallet wallet,
    String password,
    Emitter<AuthBlocState> emit, {
    String? seed,
  }) async {
    final operation = _beginAuthOperation();
    try {
      await _pauseAuthUserWatcher();
      if (!_ownsAuthOperation(operation, emit)) return;
      emit(AuthBlocState.loading());
      WalletLoadTimeline.instance.mark(WalletLoadMark.signInStarted);
      final weakPasswordsAllowed = await _areWeakPasswordsAllowed();
      if (!_ownsAuthOperation(operation, emit)) return;
      final activatedCoins = <String>{
        ..._filterBlockedAssets(enabledByDefaultCoins),
        if (seed != null)
          ..._filterBlockedAssets(
            _filterOutUnsupportedCoins(wallet.config.activatedCoins),
          ),
      };
      final user = await _kdfSdk.auth.register(
        password: password,
        walletName: wallet.name,
        mnemonic: seed == null ? null : Mnemonic.plaintext(seed),
        options: AuthOptions(
          derivationMethod: wallet.config.type == WalletType.hdwallet
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
          allowWeakPassword: weakPasswordsAllowed,
        ),
        initialMetadata: _initialWalletMetadata(
          walletType: wallet.config.type,
          provenance: seed == null
              ? WalletProvenance.generated
              : WalletProvenance.imported,
          createdAt: DateTime.now(),
          hasBackup: seed != null && wallet.config.hasBackup,
          activatedCoins: activatedCoins,
        ),
      );
      if (!_ownsAuthOperation(operation, emit)) return;
      _emitLoggedInState(emit, user);
      _listenToAuthStateChanges();
    } catch (error, stackTrace) {
      if (!_ownsAuthOperation(operation, emit)) return;
      await _emitAuthFailure(
        emit: emit,
        errorMsg: 'Failed to create wallet ${wallet.name}',
        error: error,
        stackTrace: stackTrace,
        flow: seed == null ? AuthFlow.register : AuthFlow.restore,
      );
    } finally {
      _endAuthOperation(operation);
    }
  }

  Future<void> _onLegacyMigration(
    AuthLegacyMigrationRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    final operation = _beginAuthOperation();
    try {
      await _pauseAuthUserWatcher();
      emit(AuthBlocState.loading());
      WalletLoadTimeline.instance.mark(WalletLoadMark.signInStarted);
      _log.info(
        'Starting legacy migration for ${event.sourceWallet.name} '
        '-> ${event.targetWalletName}',
      );

      final Wallet targetWallet = event.sourceWallet.copyWith(
        name: event.targetWalletName,
        config: event.sourceWallet.config.copyWith(
          isLegacyWallet: false,
          type: WalletType.iguana,
        ),
      );

      _log.info('Registering migrated wallet ${targetWallet.name}');
      final weakPasswordsAllowed = await _areWeakPasswordsAllowed();
      try {
        await _kdfSdk.auth.ensureKdfHealthy();
      } catch (e) {
        _log.warning('Pre-register KDF health check failed: $e');
      }
      if (!_ownsAuthOperation(operation, emit)) return;
      final baseActivatedCoins = <String>{
        ..._filterBlockedAssets(enabledByDefaultCoins),
        ..._filterBlockedAssets(
          _filterOutUnsupportedCoins(targetWallet.config.activatedCoins)
              .where(
                (coinId) => !_kdfSdk.assets
                    .findAssetsByConfigId(coinId)
                    .any((asset) => asset.id.subClass == CoinSubClass.zhtlc),
              )
              .toList(),
        ),
      };
      final currentUser = await _kdfSdk.auth.register(
        password: event.kdfPassword,
        walletName: targetWallet.name,
        mnemonic: Mnemonic.plaintext(event.seedPhrase),
        options: AuthOptions(
          derivationMethod: targetWallet.config.type == WalletType.hdwallet
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
          allowWeakPassword: weakPasswordsAllowed,
        ),
        initialMetadata: _initialWalletMetadata(
          walletType: targetWallet.config.type,
          provenance: WalletProvenance.imported,
          createdAt: DateTime.now(),
          hasBackup: targetWallet.config.hasBackup,
          activatedCoins: baseActivatedCoins,
          migratedSource: event.sourceWallet.legacySource,
          cleanupStatus: LegacyMigrationCleanupStatus.incomplete,
          legacyWalletExtras: event.legacyWalletExtras,
        ),
      );
      if (!_ownsAuthOperation(operation, emit)) return;
      final session = await _kdfSdk.auth.captureSessionContext();
      if (!_ownsAuthOperation(operation, emit)) return;
      _emitLoggedInState(emit, currentUser);
      _listenToAuthStateChanges();

      unawaited(
        _runPostLoginFinalizer(
          context: 'legacy migration ${event.sourceWallet.name}',
          action: () async {
            final Set<String> warnings = <String>{};
            _log.info(
              'Wallet registered, finishing legacy migration in background',
            );

            _kdfSdk.auth.ensureSessionContextCurrent(session);

            await _runNonCriticalRestoreStep(
              warnings: warnings,
              warningMessage: _assetMigrationWarning,
              logMessage: 'Failed to migrate legacy wallet assets',
              action: () async {
                final specialCasesResult = await _walletsRepository
                    .importPreparedLegacySpecialCases(
                      expectedWalletId: currentUser.walletId,
                      migration: PreparedLegacyMigration(
                        sourceWallet: event.sourceWallet,
                        seedPhrase: event.seedPhrase,
                        nativeLegacySecrets: event.legacyNativeSecrets,
                        suggestedTargetWalletName: event.targetWalletName,
                        requiresNameConfirmation: false,
                        requiresNewKdfPassword: false,
                        requestedZhtlcCoinIds: event.requestedZhtlcCoinIds,
                        zhtlcSyncPolicy: event.zhtlcSyncPolicy,
                        legacyWalletExtras: event.legacyWalletExtras,
                      ),
                      baseActivatedCoinIds: targetWallet.config.activatedCoins,
                    );
                _kdfSdk.auth.ensureSessionContextCurrent(session);
                if (specialCasesResult.warningMessage != null) {
                  warnings.add(specialCasesResult.warningMessage!);
                }

                final allowedDefaultCoins = _filterBlockedAssets(
                  enabledByDefaultCoins,
                );
                await _kdfSdk.addActivatedCoins(
                  allowedDefaultCoins,
                  expectedWalletId: currentUser.walletId,
                  expectedSession: session,
                );
                if (specialCasesResult.walletCoinIdsToActivate.isNotEmpty) {
                  final availableWalletCoins = _filterOutUnsupportedCoins(
                    specialCasesResult.walletCoinIdsToActivate,
                  );
                  final allowedWalletCoins = _filterBlockedAssets(
                    availableWalletCoins,
                  );
                  await _kdfSdk.addActivatedCoins(
                    allowedWalletCoins,
                    expectedWalletId: currentUser.walletId,
                    expectedSession: session,
                  );
                }
              },
            );

            _kdfSdk.auth.ensureSessionContextCurrent(session);
            _log.info('Cleaning up legacy wallet data');
            LegacyMigrationCleanupStatus cleanupStatus =
                LegacyMigrationCleanupStatus.incomplete;
            try {
              final cleanupOutcome = await _walletsRepository
                  .cleanupMigratedLegacyWallet(
                    wallet: event.sourceWallet,
                    password: event.legacyPassword,
                    nativeSecrets: event.legacyNativeSecrets,
                  );
              cleanupStatus = cleanupOutcome.isComplete
                  ? LegacyMigrationCleanupStatus.complete
                  : LegacyMigrationCleanupStatus.incomplete;
            } catch (error, stackTrace) {
              warnings.add(
                'Wallet migrated, but legacy data could not be fully removed.',
              );
              _log.shout('Legacy wallet cleanup failed', error, stackTrace);
            }
            try {
              await _kdfSdk.auth.updateMetadataForSession(session, {
                legacyCleanupStatusMetadataKey: cleanupStatus.name,
              });
            } catch (error, stackTrace) {
              warnings.add(
                'Wallet migrated, but cleanup status could not be persisted.',
              );
              _log.shout(
                'Failed to persist legacy cleanup status',
                error,
                stackTrace,
              );
            }

            await _refreshWalletsAfterLegacyMutation();
            if (warnings.isNotEmpty) {
              _log.warning(
                'Legacy migration completed with warnings: '
                '${warnings.join(' ')}',
              );
            }
          },
        ),
      );
    } on WalletChangedDisconnectException {
      // A replacement session must survive a stale migration finalizer.
      _listenToAuthStateChanges();
      return;
    } catch (e, s) {
      if (!_ownsAuthOperation(operation, emit)) return;
      await _emitAuthFailure(
        emit: emit,
        errorMsg: 'Failed to migrate legacy wallet ${event.sourceWallet.name}',
        error: e,
        stackTrace: s,
        flow: AuthFlow.legacyMigration,
      );
    } finally {
      _endAuthOperation(operation);
    }
  }

  Future<void> _runNonCriticalRestoreStep({
    required Set<String> warnings,
    required String warningMessage,
    required String logMessage,
    required Future<void> Function() action,
  }) async {
    try {
      await action().timeout(_postLoginStepTimeout);
    } on WalletChangedDisconnectException {
      rethrow;
    } catch (error, stackTrace) {
      warnings.add(warningMessage);
      _log.shout(logMessage, error, stackTrace);
    }
  }

  Future<void> _runBoundedPostLoginStep({
    required String logMessage,
    required Future<void> Function() action,
  }) async {
    try {
      await action().timeout(_postLoginStepTimeout);
    } on WalletChangedDisconnectException {
      rethrow;
    } catch (error, stackTrace) {
      _log.shout(logMessage, error, stackTrace);
    }
  }

  Map<String, dynamic> _initialWalletMetadata({
    required WalletType walletType,
    required WalletProvenance provenance,
    required DateTime createdAt,
    required bool hasBackup,
    required Iterable<String> activatedCoins,
    LegacyWalletSource? migratedSource,
    LegacyMigrationCleanupStatus? cleanupStatus,
    Map<String, dynamic>? legacyWalletExtras,
  }) {
    final metadata = <String, dynamic>{};
    metadata['type'] = walletType.name;
    metadata['wallet_provenance'] = provenance.name;
    metadata['wallet_created_at'] = createdAt.millisecondsSinceEpoch;
    metadata['has_backup'] = hasBackup;
    metadata['activated_coins'] = <String>{...activatedCoins}.toList();

    if (migratedSource != null) {
      metadata[legacySourceKindMetadataKey] = migratedSource.kind.name;
      metadata[legacySourceWalletIdMetadataKey] =
          migratedSource.originalWalletId;
      metadata[legacySourceWalletNameMetadataKey] =
          migratedSource.originalWalletName;
      if (cleanupStatus != null) {
        metadata[legacyCleanupStatusMetadataKey] = cleanupStatus.name;
      }
    }

    if (legacyWalletExtras != null && legacyWalletExtras.isNotEmpty) {
      metadata[legacyWalletExtrasMetadataKey] = Map<String, dynamic>.from(
        legacyWalletExtras,
      );
    }

    return metadata;
  }

  void _emitLoggedInState(
    Emitter<AuthBlocState> emit,
    KdfUser user, {
    String? message,
  }) {
    // Starts the time-to-first-balance window. Idempotent, so the login and
    // session-restore paths can both call it and the earliest one wins.
    WalletLoadTimeline.instance.markSignedIn();
    emit(AuthBlocState.loggedIn(user, message: message));
    _kdfSdk.connectStreaming();
  }

  Future<void> _runPostLoginFinalizer({
    required String context,
    required Future<void> Function() action,
  }) async {
    try {
      await action();
    } catch (error, stackTrace) {
      _log.shout(
        'Post-login finalization failed for $context',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _emitAuthFailure({
    required Emitter<AuthBlocState> emit,
    required String errorMsg,
    required Object error,
    required StackTrace stackTrace,
    required AuthFlow flow,
  }) async {
    _log.shout(errorMsg, error, stackTrace);
    logAuthEvent(
      AuthSignInFailedEventData(
        method: AuthMethod.password.value,
        flow: flow.value,
        failureType: error is AuthException
            ? error.type.name
            : AuthExceptionType.generalAuthError.name,
      ),
    );
    emit(
      AuthBlocState.error(
        error is AuthException
            ? error
            : AuthException(errorMsg, type: AuthExceptionType.generalAuthError),
      ),
    );
    await _authChangesSubscription?.cancel();
  }

  Future<void> _refreshWalletsAfterLegacyMutation() async {
    _walletsRepository.invalidateCache();
    try {
      await _walletsRepository.refreshWallets();
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to refresh wallet list after legacy migration mutation',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _onSeedBackupConfirmed(
    AuthSeedBackupConfirmed event,
    Emitter<AuthBlocState> emit,
  ) async {
    final expectedWalletId = event.expectedWalletId;
    if (state.currentUser?.walletId != expectedWalletId) {
      return;
    }

    final user = await _kdfSdk.auth.currentUser;
    if (emit.isDone ||
        user?.walletId != expectedWalletId ||
        state.currentUser?.walletId != expectedWalletId) {
      return;
    }

    try {
      // The auth layer checks identity while holding the metadata write lock.
      // A UI check alone cannot protect a queued write during a wallet switch.
      await _kdfSdk.confirmSeedBackup(expectedWalletId: expectedWalletId);
    } on WalletChangedDisconnectException {
      return;
    }
    if (emit.isDone || state.currentUser?.walletId != expectedWalletId) return;

    final updatedUser = await _kdfSdk.auth.currentUser;
    if (emit.isDone ||
        updatedUser?.walletId != expectedWalletId ||
        state.currentUser?.walletId != expectedWalletId) {
      return;
    }
    emit(AuthBlocState(mode: AuthorizeMode.logIn, currentUser: updatedUser));
  }

  Future<void> _onWalletDownloadRequested(
    AuthWalletDownloadRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    final expectedWalletId = event.expectedWalletId;
    try {
      final user = await _kdfSdk.auth.currentUser;
      if (emit.isDone || user?.walletId != expectedWalletId) return;
      final wallet = user!.wallet;

      await _walletsRepository.downloadEncryptedWallet(
        wallet,
        event.password,
        expectedWalletId: expectedWalletId,
      );

      await _kdfSdk.confirmSeedBackup(expectedWalletId: expectedWalletId);
      final updatedUser = await _kdfSdk.auth.currentUser;
      if (emit.isDone || updatedUser?.walletId != expectedWalletId) return;
      emit(AuthBlocState(mode: AuthorizeMode.logIn, currentUser: updatedUser));
    } on WalletChangedDisconnectException {
      // The export belongs to the original wallet, not its replacement.
      return;
    } catch (e, s) {
      _log.shout('Failed to download wallet data', e, s);
      final currentUser = await _kdfSdk.auth.currentUser;
      if (emit.isDone || currentUser?.walletId != expectedWalletId) return;
      emit(
        AuthBlocState(
          mode: currentUser != null
              ? AuthorizeMode.logIn
              : AuthorizeMode.noLogin,
          currentUser: currentUser,
          authError: AuthException(
            'Failed to download wallet data',
            type: AuthExceptionType.generalAuthError,
          ),
          authenticationState: AuthenticationState.error(
            'Failed to download wallet data',
          ),
        ),
      );
    }
  }

  Future<void> _onStateRestoreRequested(
    AuthStateRestoreRequested event,
    Emitter<AuthBlocState> emit,
  ) => _restoreObservedSession(emit);

  Future<void> _onLifecycleCheckRequested(
    AuthLifecycleCheckRequested event,
    Emitter<AuthBlocState> emit,
  ) => _restoreObservedSession(emit, ensureHealthy: true);

  Future<void> _restoreObservedSession(
    Emitter<AuthBlocState> emit, {
    bool ensureHealthy = false,
  }) async {
    if (_authOperation != null || state.isLoading) return;
    final revision = _authRevision;
    try {
      if (ensureHealthy) await _kdfSdk.auth.ensureKdfHealthy();
      if (_authOperation != null || revision != _authRevision || emit.isDone) {
        return;
      }
      final session = await _kdfSdk.auth.captureSessionContext();
      final user = await _kdfSdk.auth.currentUser;
      if (emit.isDone ||
          _authOperation != null ||
          revision != _authRevision ||
          !_kdfSdk.auth.isSessionContextCurrent(session) ||
          user == null) {
        return;
      }
      _emitLoggedInState(emit, user);
      _listenToAuthStateChanges();
    } on AuthSessionChangedException {
      // An interactive flow or a signed-out runtime owns the next state.
    } catch (error, stackTrace) {
      _log.warning('Failed to restore authentication state', error, stackTrace);
    }
  }

  @override
  void _listenToAuthStateChanges() {
    final revision = _authRevision;
    _authChangesSubscription?.cancel();
    _authChangesSubscription = _kdfSdk.auth.watchCurrentUser().listen((
      user,
    ) async {
      if (isClosed || revision != _authRevision) return;
      final AuthorizeMode event = user != null
          ? AuthorizeMode.logIn
          : AuthorizeMode.noLogin;
      add(
        _AuthUserObserved(mode: event, currentUser: user, revision: revision),
      );

      // Tie SSE connection lifecycle to authentication state
      if (user != null) {
        // User authenticated - connect SSE for balance/tx history streaming
        _log.info('User authenticated, connecting SSE for streaming...');
        _kdfSdk.connectStreaming();
      } else {
        // User signed out - disconnect SSE to clean up resources
        _log.info('User signed out, disconnecting SSE...');
        await _disconnectStreamingForAuthLifecycle('auth-state change');
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

  Future<void> _repairMissingWalletMetadata(
    KdfUser user,
    AuthSessionContext session,
  ) async {
    final updates = <String, dynamic>{};
    if (_isMissingMetadataStringValue(user.metadata['type'])) {
      updates['type'] = user.walletId.isHd
          ? WalletType.hdwallet.name
          : WalletType.iguana.name;
    }
    if (_isMissingMetadataStringValue(user.metadata['wallet_provenance'])) {
      final isImported = user.metadata['isImported'];
      if (isImported is bool) {
        updates['wallet_provenance'] = isImported
            ? WalletProvenance.imported.name
            : WalletProvenance.generated.name;
      }
    }
    if (updates.isNotEmpty) {
      await _kdfSdk.auth.updateMetadataForSession(session, updates);
    }
  }

  bool _isMissingMetadataStringValue(dynamic value) {
    return value == null || value is String && value.trim().isEmpty;
  }
}
