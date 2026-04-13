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
  static const String _metadataMigrationWarning =
      'Wallet restored, but some wallet metadata could not be updated.';
  static const String _assetMigrationWarning =
      'Wallet restored, but some wallet assets could not be migrated.';
  static const String _alreadyMigratedWalletMessage =
      'This wallet appears to have already been migrated. '
      'Use the migrated wallet entry and its current password.';
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

  Future<void> _onLogout(
    AuthSignOutRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    _log.info('Logging out from a wallet');
    await _pauseAuthUserWatcher();
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
      _kdfSdk.streaming.disconnect();

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
      KdfUser? currentUser = await _kdfSdk.auth.currentUser;
      if (currentUser == null) {
        return emit(AuthBlocState.error(AuthException.notSignedIn()));
      }

      await _repairMissingWalletMetadata(currentUser);
      currentUser = await _kdfSdk.auth.currentUser;
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
      // After optimistic login, the SDK watcher fires with the bare user
      // before the background finalizer persists metadata. Suppress only if
      // the incoming metadata carries no new or changed values; allow updates
      // from finalizers (e.g. cleanup status, activated coins) through.
      if (state.status == AuthenticationStatus.completed &&
          state.currentUser?.walletId == event.currentUser!.walletId &&
          !_hasNewerMetadata(
            event.currentUser!.metadata,
            state.currentUser?.metadata ?? {},
          )) {
        return;
      }
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
    await _authChangesSubscription?.cancel();
    emit(AuthBlocState.initial());
  }

  Future<void> _onRegister(
    AuthRegisterRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      await _pauseAuthUserWatcher();
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
      final currentUser = await _kdfSdk.auth.register(
        password: event.password,
        walletName: event.wallet.name,
        options: AuthOptions(
          derivationMethod: event.wallet.config.type == WalletType.hdwallet
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
          allowWeakPassword: weakPasswordsAllowed,
        ),
      );

      final allowedDefaultCoins = _filterBlockedAssets(enabledByDefaultCoins);
      final optimisticUser = _buildOptimisticLoggedInUser(
        currentUser,
        walletType: event.wallet.config.type,
        provenance: WalletProvenance.generated,
        createdAt: DateTime.now(),
        hasBackup: false,
        activatedCoins: allowedDefaultCoins,
      );
      _emitLoggedInState(emit, optimisticUser);
      _listenToAuthStateChanges();

      unawaited(
        _runPostLoginFinalizer(
          context: 'wallet registration ${event.wallet.name}',
          action: () async {
            _log.info(
              'Registered a new wallet, setting up metadata in background...',
            );
            await _runBoundedPostLoginStep(
              logMessage: 'Failed to persist wallet type',
              action: () => _kdfSdk.setWalletType(event.wallet.config.type),
            );
            await _runBoundedPostLoginStep(
              logMessage: 'Failed to persist wallet provenance',
              action: () =>
                  _kdfSdk.setWalletProvenance(WalletProvenance.generated),
            );
            await _runBoundedPostLoginStep(
              logMessage: 'Failed to persist wallet creation date',
              action: () => _kdfSdk.setWalletCreatedAt(DateTime.now()),
            );
            await _runBoundedPostLoginStep(
              logMessage: 'Failed to persist seed backup state',
              action: () => _kdfSdk.confirmSeedBackup(hasBackup: false),
            );
            await _runBoundedPostLoginStep(
              logMessage: 'Failed to persist default activated coins',
              action: () => _kdfSdk.addActivatedCoins(allowedDefaultCoins),
            );
          },
        ),
      );
    } catch (e, s) {
      await _emitAuthFailure(
        emit: emit,
        errorMsg: 'Failed to register wallet ${event.wallet.name}',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<void> _onRestore(
    AuthRestoreRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      await _pauseAuthUserWatcher();
      if (await _didSignInExistingWallet(event.wallet, event.password)) {
        add(
          AuthSignInRequested(wallet: event.wallet, password: event.password),
        );
        _log.warning(
          'Wallet ${event.wallet.name} already exists, attempting sign-in',
        );
        return;
      }

      emit(AuthBlocState.loading());
      _log.info('Restoring wallet from a seed');
      final weakPasswordsAllowed = await _areWeakPasswordsAllowed();
      final currentUser = await _kdfSdk.auth.register(
        password: event.password,
        walletName: event.wallet.name,
        mnemonic: Mnemonic.plaintext(event.seed),
        options: AuthOptions(
          derivationMethod: event.wallet.config.type == WalletType.hdwallet
              ? DerivationMethod.hdWallet
              : DerivationMethod.iguana,
          allowWeakPassword: weakPasswordsAllowed,
        ),
      );
      final allowedDefaultCoins = _filterBlockedAssets(enabledByDefaultCoins);
      final availableWalletCoins = _filterOutUnsupportedCoins(
        event.wallet.config.activatedCoins,
      );
      final allowedWalletCoins = _filterBlockedAssets(availableWalletCoins);
      final optimisticUser = _buildOptimisticLoggedInUser(
        currentUser,
        walletType: event.wallet.config.type,
        provenance: WalletProvenance.imported,
        createdAt: DateTime.now(),
        hasBackup: event.wallet.config.hasBackup,
        activatedCoins: <String>{...allowedDefaultCoins, ...allowedWalletCoins},
      );
      _emitLoggedInState(emit, optimisticUser);
      _listenToAuthStateChanges();

      unawaited(
        _runPostLoginFinalizer(
          context: 'wallet restore ${event.wallet.name}',
          action: () async {
            final Set<String> warnings = <String>{};
            _log.info(
              'Successfully restored wallet from a seed. '
              'Finalizing metadata in background...',
            );
            await _runNonCriticalRestoreStep(
              warnings: warnings,
              warningMessage: _metadataMigrationWarning,
              logMessage: 'Failed to update restored wallet metadata',
              action: () async {
                await _kdfSdk.setWalletType(event.wallet.config.type);
                await _kdfSdk.setWalletProvenance(WalletProvenance.imported);
                await _kdfSdk.setWalletCreatedAt(DateTime.now());
                await _kdfSdk.confirmSeedBackup(
                  hasBackup: event.wallet.config.hasBackup,
                );
              },
            );
            await _runNonCriticalRestoreStep(
              warnings: warnings,
              warningMessage: _assetMigrationWarning,
              logMessage: 'Failed to migrate restored wallet assets',
              action: () async {
                await _kdfSdk.addActivatedCoins(allowedDefaultCoins);
                if (allowedWalletCoins.isNotEmpty) {
                  await _kdfSdk.addActivatedCoins(allowedWalletCoins);
                }
              },
            );
            if (warnings.isNotEmpty) {
              _log.warning(
                'Wallet restore completed with warnings: ${warnings.join(' ')}',
              );
            }
          },
        ),
      );
    } catch (e, s) {
      await _emitAuthFailure(
        emit: emit,
        errorMsg: 'Failed to restore existing wallet ${event.wallet.name}',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<void> _onLegacyMigration(
    AuthLegacyMigrationRequested event,
    Emitter<AuthBlocState> emit,
  ) async {
    try {
      await _pauseAuthUserWatcher();
      emit(AuthBlocState.loading());
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

      if (await _didSignInExistingWallet(targetWallet, event.kdfPassword)) {
        if (event.kdfPassword != event.legacyPassword) {
          _log.info('Target wallet already exists with different password');
          emit(
            AuthBlocState.error(
              AuthException(
                _alreadyMigratedWalletMessage,
                type: AuthExceptionType.generalAuthError,
              ),
            ),
          );
          return;
        }

        add(
          AuthSignInRequested(
            wallet: targetWallet,
            password: event.kdfPassword,
          ),
        );
        _log.warning(
          'Wallet ${targetWallet.name} already exists, attempting sign-in',
        );
        return;
      }

      _log.info('Registering migrated wallet ${targetWallet.name}');
      final weakPasswordsAllowed = await _areWeakPasswordsAllowed();
      try {
        await _kdfSdk.auth.ensureKdfHealthy();
      } catch (e) {
        _log.warning('Pre-register KDF health check failed: $e');
      }
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
      );
      final LegacyWalletSource? linkageSource =
          event.sourceWallet.legacySource;
      if (linkageSource != null) {
        await _kdfSdk.setMigratedLegacySource(
          source: linkageSource,
          cleanupStatus: LegacyMigrationCleanupStatus.incomplete,
        );
      }
      if (event.legacyWalletExtras.isNotEmpty) {
        await _kdfSdk.setLegacyWalletExtras(event.legacyWalletExtras);
      }
      final baseActivatedCoins = <String>{
        ..._filterBlockedAssets(enabledByDefaultCoins),
        ..._filterBlockedAssets(
          _filterOutUnsupportedCoins(targetWallet.config.activatedCoins),
        ),
      };
      final optimisticUser = _buildOptimisticLoggedInUser(
        currentUser,
        walletType: targetWallet.config.type,
        provenance: WalletProvenance.imported,
        createdAt: DateTime.now(),
        hasBackup: targetWallet.config.hasBackup,
        activatedCoins: baseActivatedCoins,
        migratedSource: event.sourceWallet.legacySource,
        cleanupStatus: LegacyMigrationCleanupStatus.incomplete,
        legacyWalletExtras: event.legacyWalletExtras,
      );
      _emitLoggedInState(emit, optimisticUser);
      _listenToAuthStateChanges();

      unawaited(
        _runPostLoginFinalizer(
          context: 'legacy migration ${event.sourceWallet.name}',
          action: () async {
            final Set<String> warnings = <String>{};
            _log.info(
              'Wallet registered, finishing legacy migration in background',
            );

            final LegacyWalletSource? source = event.sourceWallet.legacySource;
            if (source != null) {
              await _runBoundedPostLoginStep(
                logMessage: 'Failed to write migration linkage metadata',
                action: () => _kdfSdk.setMigratedLegacySource(
                  source: source,
                  cleanupStatus: LegacyMigrationCleanupStatus.incomplete,
                ),
              );
            }

            await _runNonCriticalRestoreStep(
              warnings: warnings,
              warningMessage: _metadataMigrationWarning,
              logMessage: 'Failed to update migrated wallet metadata',
              action: () async {
                await _kdfSdk.setWalletType(targetWallet.config.type);
                await _kdfSdk.setWalletProvenance(WalletProvenance.imported);
                await _kdfSdk.setWalletCreatedAt(DateTime.now());
                await _kdfSdk.confirmSeedBackup(
                  hasBackup: targetWallet.config.hasBackup,
                );
              },
            );

            await _runNonCriticalRestoreStep(
              warnings: warnings,
              warningMessage: _assetMigrationWarning,
              logMessage: 'Failed to migrate legacy wallet assets',
              action: () async {
                final specialCasesResult = await _walletsRepository
                    .importPreparedLegacySpecialCases(
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
                if (specialCasesResult.warningMessage != null) {
                  warnings.add(specialCasesResult.warningMessage!);
                }

                final allowedDefaultCoins = _filterBlockedAssets(
                  enabledByDefaultCoins,
                );
                await _kdfSdk.addActivatedCoins(allowedDefaultCoins);
                if (specialCasesResult.walletCoinIdsToActivate.isNotEmpty) {
                  final availableWalletCoins = _filterOutUnsupportedCoins(
                    specialCasesResult.walletCoinIdsToActivate,
                  );
                  final allowedWalletCoins = _filterBlockedAssets(
                    availableWalletCoins,
                  );
                  await _kdfSdk.addActivatedCoins(allowedWalletCoins);
                }
              },
            );

            _log.info('Cleaning up legacy wallet data');
            LegacyMigrationCleanupStatus cleanupStatus =
                LegacyMigrationCleanupStatus.incomplete;
            await _runNonCriticalRestoreStep(
              warnings: warnings,
              warningMessage:
                  'Wallet migrated, but legacy data could not be fully '
                  'removed.',
              logMessage: 'Legacy wallet cleanup failed',
              action: () async {
                final cleanupOutcome = await _walletsRepository
                    .cleanupMigratedLegacyWallet(
                      wallet: event.sourceWallet,
                      password: event.legacyPassword,
                      nativeSecrets: event.legacyNativeSecrets,
                    );
                cleanupStatus = cleanupOutcome.isComplete
                    ? LegacyMigrationCleanupStatus.complete
                    : LegacyMigrationCleanupStatus.incomplete;
              },
            );
            await _runNonCriticalRestoreStep(
              warnings: warnings,
              warningMessage:
                  'Wallet migrated, but cleanup status could not be persisted.',
              logMessage: 'Failed to persist legacy cleanup status',
              action: () => _kdfSdk.setLegacyCleanupStatus(cleanupStatus),
            );

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
    } catch (e, s) {
      // Registration may have succeeded before the failure (e.g. linkage
      // metadata write). Sign out to avoid leaving SDK auth active while
      // the UI shows an error state.
      try {
        if (await _kdfSdk.auth.isSignedIn()) {
          await _kdfSdk.auth.signOut();
        }
      } catch (signOutError, signOutStack) {
        _log.warning(
          'Failed to roll back SDK session after migration failure',
          signOutError,
          signOutStack,
        );
      }
      await _emitAuthFailure(
        emit: emit,
        errorMsg: 'Failed to migrate legacy wallet ${event.sourceWallet.name}',
        error: e,
        stackTrace: s,
      );
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
    } catch (error, stackTrace) {
      _log.shout(logMessage, error, stackTrace);
    }
  }

  KdfUser _buildOptimisticLoggedInUser(
    KdfUser user, {
    required WalletType walletType,
    required WalletProvenance provenance,
    required DateTime createdAt,
    required bool hasBackup,
    required Iterable<String> activatedCoins,
    LegacyWalletSource? migratedSource,
    LegacyMigrationCleanupStatus? cleanupStatus,
    Map<String, dynamic>? legacyWalletExtras,
  }) {
    final metadata = Map<String, dynamic>.from(user.metadata);
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

    return user.copyWith(metadata: metadata);
  }

  void _emitLoggedInState(
    Emitter<AuthBlocState> emit,
    KdfUser user, {
    String? message,
  }) {
    emit(AuthBlocState.loggedIn(user, message: message));
    _kdfSdk.streaming.connectIfNeeded();
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
  }) async {
    _log.shout(errorMsg, error, stackTrace);
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
      final currentUser = await _kdfSdk.auth.currentUser;
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
    if (state.isLoading) {
      _log.info('Skipping lifecycle auth check while auth flow is loading');
      return;
    }

    // Ensure KDF is healthy before checking user state
    // This helps recover from situations where MM2 becomes unavailable
    // (e.g., after app backgrounding on mobile platforms)
    try {
      await _kdfSdk.auth.ensureKdfHealthy();
    } catch (e) {
      _log.warning('Failed to ensure KDF health during lifecycle check: $e');
      // Continue anyway - the health check is best-effort
    }

    final KdfUser? currentUser;
    try {
      currentUser = await _kdfSdk.auth.currentUser;
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to read current user during lifecycle check',
        error,
        stackTrace,
      );
      return;
    }

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
        _kdfSdk.streaming.connectIfNeeded();
      } else {
        // User signed out - disconnect SSE to clean up resources
        _log.info('User signed out, disconnecting SSE...');
        _kdfSdk.streaming.disconnect();
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

  Future<void> _repairMissingWalletMetadata(KdfUser user) async {
    if (_isMissingMetadataStringValue(user.metadata['type'])) {
      final walletType = user.walletId.isHd
          ? WalletType.hdwallet
          : WalletType.iguana;
      await _kdfSdk.setWalletType(walletType);
    }

    if (_isMissingMetadataStringValue(user.metadata['wallet_provenance'])) {
      final isImported = user.metadata['isImported'];
      if (isImported is bool) {
        await _kdfSdk.setWalletProvenance(
          isImported ? WalletProvenance.imported : WalletProvenance.generated,
        );
      }
    }
  }

  /// Returns `true` if [incoming] contains at least one key whose value
  /// differs from [current], or a key that [current] does not have at all.
  /// Used to distinguish bare-user watcher re-emissions (no new data) from
  /// post-login finalizer updates that carry meaningful metadata changes.
  bool _hasNewerMetadata(
    Map<String, dynamic> incoming,
    Map<String, dynamic> current,
  ) {
    for (final entry in incoming.entries) {
      if (!current.containsKey(entry.key) || current[entry.key] != entry.value) {
        return true;
      }
    }
    return false;
  }

  bool _isMissingMetadataStringValue(dynamic value) {
    return value == null || value is String && value.trim().isEmpty;
  }
}
