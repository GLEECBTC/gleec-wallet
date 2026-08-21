import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/analytics/events.dart';
import 'package:web_dex/analytics/events/transaction_events.dart'
    show GaslessReceiveAnalyticsEventData, GaslessReceiveAnalyticsStatus;
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/gasless/tron_gasless_receive_reason.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';

class CoinAddressesBloc extends Bloc<CoinAddressesEvent, CoinAddressesState> {
  final KomodoDefiSdk sdk;
  final String assetId;
  final AnalyticsBloc analyticsBloc;

  StreamSubscription<AssetPubkeys>? _pubkeysSub;
  int _pubkeysSubscriptionGeneration = 0;
  Timer? _gaslessReceiveRefreshTimer;
  int _gaslessReceiveEvaluationGeneration = 0;

  /// Owner of [CoinAddressesState.status], [CoinAddressesState.addresses], and
  /// [CoinAddressesState.cantCreateNewAddressReasons].
  ///
  /// Deliberately separate from [_gaslessReceiveEvaluationGeneration]. Only
  /// [_onAddressesSubscriptionRequested], [_onPubkeysUpdated], and
  /// [_onPubkeysSubscriptionFailed] load the address list, and the first two
  /// emit `submitting` with an empty list before their first await. The
  /// GasFree-only handlers - the 30-second refresh and the foreground/
  /// background transition - legitimately supersede an in-flight *GasFree*
  /// evaluation, but they never emit `status`, so sharing one counter meant a
  /// timer tick landing mid-load aborted the load and left the coin page's
  /// address list pinned under a spinner (and the create-address button
  /// without its disabled reasons) until the page was reopened.
  int _addressesLoadGeneration = 0;
  String? _lastGaslessReceiveAnalyticsKey;
  bool _lastLoggedGaslessReceiveWasReady = false;
  bool _isForeground = true;

  CoinAddressesBloc(this.sdk, this.assetId, this.analyticsBloc)
    : super(const CoinAddressesState()) {
    on<CoinAddressesAddressCreationSubmitted>(_onCreateAddressSubmitted);
    on<CoinAddressesStarted>(_onStarted);
    on<CoinAddressesSubscriptionRequested>(_onAddressesSubscriptionRequested);
    on<CoinAddressesGaslessReceiveRefreshRequested>(
      _onGaslessReceiveRefreshRequested,
    );
    on<CoinAddressesGaslessReceiveVisibilityChanged>(
      _onGaslessReceiveVisibilityChanged,
    );
    on<CoinAddressesZeroBalanceVisibilityChanged>(_onHideZeroBalanceChanged);
    on<CoinAddressesPubkeysUpdated>(_onPubkeysUpdated);
    on<CoinAddressesPubkeysSubscriptionFailed>(_onPubkeysSubscriptionFailed);
  }

  Future<void> _onStarted(
    CoinAddressesStarted event,
    Emitter<CoinAddressesState> emit,
  ) async {
    add(const CoinAddressesSubscriptionRequested());
  }

  Future<void> _onCreateAddressSubmitted(
    CoinAddressesAddressCreationSubmitted event,
    Emitter<CoinAddressesState> emit,
  ) async {
    emit(
      state.copyWith(
        createAddressStatus: () => FormStatus.submitting,
        newAddressState: () => null,
      ),
    );
    try {
      final asset = getSdkAsset(sdk, assetId);
      final stream = sdk.pubkeys.watchCreateNewPubkey(asset);

      await for (final newAddressState in stream) {
        emit(state.copyWith(newAddressState: () => newAddressState));

        switch (newAddressState.status) {
          case NewAddressStatus.completed:
            final pubkey = newAddressState.address;
            final derivation = pubkey?.derivationPath;
            if (derivation != null) {
              try {
                final parsed = parseDerivationPath(derivation);
                analyticsBloc.logEvent(
                  HdAddressGeneratedEventData(
                    accountIndex: parsed.accountIndex,
                    addressIndex: parsed.addressIndex,
                    asset: assetId,
                  ),
                );
              } catch (_) {
                // Non-fatal: continue without analytics if derivation parsing fails
              }
            }

            add(const CoinAddressesSubscriptionRequested());

            emit(
              state.copyWith(
                createAddressStatus: () => FormStatus.success,
                newAddressState: () => null,
              ),
            );
            return;
          case NewAddressStatus.error:
            emit(
              state.copyWith(
                createAddressStatus: () => FormStatus.failure,
                errorMessage: () => _buildDisplayError(
                  newAddressState.error ?? LocaleKeys.somethingWrong.tr(),
                ),
                newAddressState: () => null,
              ),
            );
            return;
          case NewAddressStatus.cancelled:
            emit(
              state.copyWith(
                createAddressStatus: () => FormStatus.initial,
                newAddressState: () => null,
              ),
            );
            return;
          default:
            // continue listening for next events
            break;
        }
      }
    } catch (e) {
      emit(
        state.copyWith(
          createAddressStatus: () => FormStatus.failure,
          errorMessage: () => _buildDisplayError(e),
          newAddressState: () => null,
        ),
      );
    }
  }

  Future<void> _onAddressesSubscriptionRequested(
    CoinAddressesSubscriptionRequested event,
    Emitter<CoinAddressesState> emit,
  ) async {
    final evaluationGeneration = ++_gaslessReceiveEvaluationGeneration;
    final addressesLoadGeneration = ++_addressesLoadGeneration;
    _pubkeysSubscriptionGeneration += 1;
    final previousPubkeysSubscription = _pubkeysSub;
    _pubkeysSub = null;
    final failClosed = _shouldFailClosedGaslessReceive;
    emit(
      state.copyWith(
        status: () => FormStatus.submitting,
        createAddressStatus: () => FormStatus.initial,
        addresses: () => const <PubkeyInfo>[],
        cantCreateNewAddressReasons: () => null,
        newAddressState: () => null,
        gaslessReceiveStatus: failClosed
            ? () => GaslessReceiveStatus.checking
            : null,
        gaslessReceiveReason: failClosed ? () => null : null,
        verifiedGasfreeAddress: failClosed ? () => null : null,
        gaslessReceiveWalletPubkeyHash: failClosed ? () => null : null,
        gaslessAccountStatus: () => null,
        gaslessAccountStatusObservedAt: () => null,
      ),
    );
    await previousPubkeysSubscription?.cancel();

    try {
      final asset = getSdkAsset(sdk, assetId);
      final walletAddresses = await _readCurrentWalletAddresses(asset);
      if (walletAddresses == null) {
        add(const CoinAddressesSubscriptionRequested());
        return;
      }
      final addresses = walletAddresses.addresses;
      final reasons = await asset.getCantCreateNewAddressReasons(sdk);
      final currentUser = walletAddresses.user;
      if (!await _isCurrentWallet(currentUser.walletId)) {
        add(const CoinAddressesSubscriptionRequested());
        return;
      }
      final isHdWallet = currentUser.isHd;
      final walletPubkeyHash = currentUser.walletId.pubkeyHash?.trim();
      if (emit.isDone || addressesLoadGeneration != _addressesLoadGeneration) {
        return;
      }
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration) {
        // A newer GasFree evaluation owns the gas-free fields and will emit a
        // terminal one. Nothing else owns `status`, so land the address load
        // rather than leaving `submitting` behind.
        _emitAddressLoadSuccess(emit, addresses: addresses, reasons: reasons);
        await _startWatchingPubkeys(asset);
        return;
      }
      if (asset.isTronGaslessReceiveConfiguredAsset) {
        emit(
          state.copyWith(
            status: () => FormStatus.success,
            addresses: () => addresses,
            cantCreateNewAddressReasons: () => reasons,
            errorMessage: () => null,
            gaslessReceiveStatus: () => GaslessReceiveStatus.checking,
            gaslessReceiveReason: () => null,
            verifiedGasfreeAddress: () => null,
            gaslessReceiveWalletPubkeyHash: () => null,
          ),
        );
      }
      final gaslessReceive = await _resolveGaslessReceive(
        asset,
        addresses,
        isHdWallet: isHdWallet,
        isPrimarySoftwareWallet: _isPrimarySoftwareWallet(currentUser),
      );
      if (emit.isDone || addressesLoadGeneration != _addressesLoadGeneration) {
        return;
      }
      if (!await _isCurrentWallet(currentUser.walletId)) {
        add(const CoinAddressesSubscriptionRequested());
        return;
      }
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration) {
        _emitAddressLoadSuccess(emit, addresses: addresses, reasons: reasons);
        await _startWatchingPubkeys(asset);
        return;
      }
      emit(
        state.copyWith(
          status: () => FormStatus.success,
          addresses: () => addresses,
          cantCreateNewAddressReasons: () => reasons,
          errorMessage: () => null,
          gaslessReceiveStatus: () => gaslessReceive.status,
          gaslessReceiveReason: () => gaslessReceive.reason,
          verifiedGasfreeAddress: () => gaslessReceive.address,
          gaslessReceiveWalletPubkeyHash: () =>
              _readyWalletPubkeyHash(gaslessReceive, walletPubkeyHash),
          gaslessAccountStatus: () => gaslessReceive.accountStatus,
          gaslessAccountStatusObservedAt: () => gaslessReceive.observedAt,
        ),
      );
      _logGaslessReceiveDecision(gaslessReceive);
      _scheduleGaslessReceiveRefresh(gaslessReceive);

      await _startWatchingPubkeys(asset);
    } catch (e) {
      if (emit.isDone || addressesLoadGeneration != _addressesLoadGeneration) {
        return;
      }
      final ownsGaslessEvaluation =
          evaluationGeneration == _gaslessReceiveEvaluationGeneration;
      final failClosed =
          ownsGaslessEvaluation && _shouldFailClosedGaslessReceive;
      const unavailable = _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.accountStatusUnavailable,
        shouldRefresh: true,
      );
      emit(
        state.copyWith(
          status: () => FormStatus.failure,
          addresses: () => const <PubkeyInfo>[],
          cantCreateNewAddressReasons: () => null,
          newAddressState: () => null,
          errorMessage: () => _buildDisplayError(e),
          gaslessReceiveStatus: failClosed
              ? () => GaslessReceiveStatus.temporarilyUnavailable
              : null,
          gaslessReceiveReason: failClosed
              ? () => GaslessReceiveReasonCode.accountStatusUnavailable
              : null,
          verifiedGasfreeAddress: failClosed ? () => null : null,
          gaslessReceiveWalletPubkeyHash: failClosed ? () => null : null,
          gaslessAccountStatus: ownsGaslessEvaluation ? () => null : null,
          gaslessAccountStatusObservedAt: ownsGaslessEvaluation
              ? () => null
              : null,
        ),
      );
      if (failClosed) {
        _logGaslessReceiveDecision(unavailable);
        _scheduleGaslessReceiveRefresh(unavailable);
      }
    }
  }

  /// Lands the address-list half of a load whose GasFree evaluation was
  /// superseded mid-flight.
  ///
  /// See [_addressesLoadGeneration] for why these three fields need an owner
  /// of their own: the superseding handler emits a terminal GasFree state but
  /// never a terminal [FormStatus], so without this the `submitting` set
  /// before the first await would never be cleared.
  void _emitAddressLoadSuccess(
    Emitter<CoinAddressesState> emit, {
    required List<PubkeyInfo> addresses,
    required Set<CantCreateNewAddressReason>? reasons,
  }) {
    emit(
      state.copyWith(
        status: () => FormStatus.success,
        addresses: () => addresses,
        cantCreateNewAddressReasons: () => reasons,
        errorMessage: () => null,
      ),
    );
  }

  void _onHideZeroBalanceChanged(
    CoinAddressesZeroBalanceVisibilityChanged event,
    Emitter<CoinAddressesState> emit,
  ) {
    emit(state.copyWith(hideZeroBalance: () => event.hideZeroBalance));
  }

  Future<void> _onPubkeysUpdated(
    CoinAddressesPubkeysUpdated event,
    Emitter<CoinAddressesState> emit,
  ) async {
    final eventSubscriptionGeneration = event.subscriptionGeneration;
    if (eventSubscriptionGeneration != null &&
        eventSubscriptionGeneration != _pubkeysSubscriptionGeneration) {
      return;
    }
    final evaluationGeneration = ++_gaslessReceiveEvaluationGeneration;
    final addressesLoadGeneration = ++_addressesLoadGeneration;
    try {
      final asset = getSdkAsset(sdk, assetId);
      final revokeGasless =
          asset.isTronGaslessReceiveConfiguredAsset ||
          state.gaslessReceiveStatus == GaslessReceiveStatus.ready;
      if (revokeGasless) {
        // A pubkey replacement or duplicate candidate invalidates the prior
        // custody attestation immediately. Clear QR/copy authorization before
        // the first asynchronous provider or wallet lookup can yield.
        _logGaslessReceiveRevocation(
          GaslessReceiveReasonCode.custodyAddressMismatch,
        );
      }
      // Watcher payloads can have been queued by the previous wallet. Never
      // render them until a fresh SDK read has been bounded by matching
      // authenticated-wallet observations.
      emit(
        state.copyWith(
          status: () => FormStatus.submitting,
          addresses: () => const <PubkeyInfo>[],
          cantCreateNewAddressReasons: () => null,
          newAddressState: () => null,
          gaslessReceiveStatus: revokeGasless
              ? () => GaslessReceiveStatus.checking
              : null,
          gaslessReceiveReason: revokeGasless ? () => null : null,
          verifiedGasfreeAddress: revokeGasless ? () => null : null,
          gaslessReceiveWalletPubkeyHash: revokeGasless ? () => null : null,
          gaslessAccountStatus: revokeGasless ? () => null : null,
          gaslessAccountStatusObservedAt: revokeGasless ? () => null : null,
        ),
      );
      final walletAddresses = await _readCurrentWalletAddresses(asset);
      if (walletAddresses == null) {
        add(const CoinAddressesSubscriptionRequested());
        return;
      }
      final addresses = walletAddresses.addresses;
      final currentUser = walletAddresses.user;
      final reasons = await asset.getCantCreateNewAddressReasons(sdk);
      if (emit.isDone || addressesLoadGeneration != _addressesLoadGeneration) {
        return;
      }
      if (!await _isCurrentWallet(currentUser.walletId)) {
        add(const CoinAddressesSubscriptionRequested());
        return;
      }
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration) {
        // A newer GasFree evaluation owns the gas-free fields and will emit a
        // terminal one. Nothing else owns `status`, so land the address load
        // rather than leaving `submitting` behind.
        _emitAddressLoadSuccess(emit, addresses: addresses, reasons: reasons);
        return;
      }
      final gaslessReceive = await _resolveGaslessReceive(
        asset,
        addresses,
        isHdWallet: currentUser.isHd,
        isPrimarySoftwareWallet: _isPrimarySoftwareWallet(currentUser),
      );
      if (emit.isDone || addressesLoadGeneration != _addressesLoadGeneration) {
        return;
      }
      if (!await _isCurrentWallet(currentUser.walletId)) {
        add(const CoinAddressesSubscriptionRequested());
        return;
      }
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration) {
        _emitAddressLoadSuccess(emit, addresses: addresses, reasons: reasons);
        return;
      }
      emit(
        state.copyWith(
          status: () => FormStatus.success,
          addresses: () => addresses,
          cantCreateNewAddressReasons: () => reasons,
          errorMessage: () => null,
          gaslessReceiveStatus: () => gaslessReceive.status,
          gaslessReceiveReason: () => gaslessReceive.reason,
          verifiedGasfreeAddress: () => gaslessReceive.address,
          gaslessReceiveWalletPubkeyHash: () => _readyWalletPubkeyHash(
            gaslessReceive,
            currentUser.walletId.pubkeyHash?.trim(),
          ),
          gaslessAccountStatus: () => gaslessReceive.accountStatus,
          gaslessAccountStatusObservedAt: () => gaslessReceive.observedAt,
        ),
      );
      _logGaslessReceiveDecision(gaslessReceive);
      _scheduleGaslessReceiveRefresh(gaslessReceive);
    } catch (e) {
      if (emit.isDone || addressesLoadGeneration != _addressesLoadGeneration) {
        return;
      }
      final ownsGaslessEvaluation =
          evaluationGeneration == _gaslessReceiveEvaluationGeneration;
      final failClosed =
          ownsGaslessEvaluation && _shouldFailClosedGaslessReceive;
      const unavailable = _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.accountStatusUnavailable,
        shouldRefresh: true,
      );
      emit(
        state.copyWith(
          // Without this the handler's own pre-emit `submitting` survived the
          // failure, so the addresses section rendered a spinner forever and
          // the error below never reached the user - `ErrorDisplay` is gated
          // on `FormStatus.failure`.
          status: () => FormStatus.failure,
          addresses: () => const <PubkeyInfo>[],
          cantCreateNewAddressReasons: () => null,
          newAddressState: () => null,
          errorMessage: () => _buildDisplayError(e),
          gaslessReceiveStatus: failClosed
              ? () => GaslessReceiveStatus.temporarilyUnavailable
              : null,
          gaslessReceiveReason: failClosed
              ? () => GaslessReceiveReasonCode.accountStatusUnavailable
              : null,
          verifiedGasfreeAddress: failClosed ? () => null : null,
          gaslessReceiveWalletPubkeyHash: failClosed ? () => null : null,
          gaslessAccountStatus: ownsGaslessEvaluation ? () => null : null,
          gaslessAccountStatusObservedAt: ownsGaslessEvaluation
              ? () => null
              : null,
        ),
      );
      if (failClosed) {
        _logGaslessReceiveDecision(unavailable);
        _scheduleGaslessReceiveRefresh(unavailable);
      }
    }
  }

  Future<void> _onGaslessReceiveRefreshRequested(
    CoinAddressesGaslessReceiveRefreshRequested event,
    Emitter<CoinAddressesState> emit,
  ) async {
    final evaluationGeneration = ++_gaslessReceiveEvaluationGeneration;
    final now = DateTime.now().toUtc();
    final observedAt = state.gaslessAccountStatusObservedAt?.toUtc();
    final accountStatusExpired =
        observedAt == null ||
        observedAt.isAfter(now) ||
        now.difference(observedAt) > const Duration(minutes: 1);
    // A scheduled refresh starts halfway through the 60-second status TTL.
    // Keep a still-valid Ready presentation stable while it runs; every
    // sensitive action independently revalidates the cached domain state.
    // Once the typed KDF status has expired, revoke before the first await.
    if (state.gaslessReceiveStatus == GaslessReceiveStatus.ready &&
        accountStatusExpired) {
      _logGaslessReceiveRevocation(
        GaslessReceiveReasonCode.accountStatusExpired,
      );
      emit(
        state.copyWith(
          gaslessReceiveStatus: () => GaslessReceiveStatus.checking,
          gaslessReceiveReason: () =>
              GaslessReceiveReasonCode.accountStatusExpired,
          verifiedGasfreeAddress: () => null,
          gaslessReceiveWalletPubkeyHash: () => null,
          gaslessAccountStatus: () => null,
          gaslessAccountStatusObservedAt: () => null,
        ),
      );
    }

    try {
      final asset = getSdkAsset(sdk, assetId);
      final walletAddresses = await _readCurrentWalletAddresses(asset);
      if (walletAddresses == null) {
        add(const CoinAddressesSubscriptionRequested());
        return;
      }
      final currentUser = walletAddresses.user;
      final gaslessReceive = await _resolveGaslessReceive(
        asset,
        walletAddresses.addresses,
        isHdWallet: currentUser.isHd,
        isPrimarySoftwareWallet: _isPrimarySoftwareWallet(currentUser),
      );
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
        return;
      }
      if (!await _isCurrentWallet(currentUser.walletId)) {
        add(const CoinAddressesSubscriptionRequested());
        return;
      }
      emit(
        state.copyWith(
          addresses: () => walletAddresses.addresses,
          gaslessReceiveStatus: () => gaslessReceive.status,
          gaslessReceiveReason: () => gaslessReceive.reason,
          verifiedGasfreeAddress: () => gaslessReceive.address,
          gaslessReceiveWalletPubkeyHash: () => _readyWalletPubkeyHash(
            gaslessReceive,
            currentUser.walletId.pubkeyHash?.trim(),
          ),
          gaslessAccountStatus: () => gaslessReceive.accountStatus,
          gaslessAccountStatusObservedAt: () => gaslessReceive.observedAt,
        ),
      );
      _logGaslessReceiveDecision(gaslessReceive);
      _scheduleGaslessReceiveRefresh(gaslessReceive);
    } catch (_) {
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
        return;
      }
      final unavailable = const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.accountStatusUnavailable,
        shouldRefresh: true,
      );
      emit(
        state.copyWith(
          gaslessReceiveStatus: () => unavailable.status,
          gaslessReceiveReason: () => unavailable.reason,
          verifiedGasfreeAddress: () => null,
          gaslessReceiveWalletPubkeyHash: () => null,
          gaslessAccountStatus: () => null,
          gaslessAccountStatusObservedAt: () => null,
        ),
      );
      _logGaslessReceiveDecision(unavailable);
      _scheduleGaslessReceiveRefresh(unavailable);
    }
  }

  void _onGaslessReceiveVisibilityChanged(
    CoinAddressesGaslessReceiveVisibilityChanged event,
    Emitter<CoinAddressesState> emit,
  ) {
    _isForeground = event.isForeground;
    if (event.isForeground) {
      add(const CoinAddressesGaslessReceiveRefreshRequested());
      return;
    }

    _gaslessReceiveEvaluationGeneration += 1;
    _gaslessReceiveRefreshTimer?.cancel();
    _gaslessReceiveRefreshTimer = null;
    if (state.gaslessReceiveStatus == GaslessReceiveStatus.ready ||
        state.gaslessReceiveStatus == GaslessReceiveStatus.checking) {
      _logGaslessReceiveRevocation(GaslessReceiveReasonCode.appBackgrounded);
      emit(
        state.copyWith(
          gaslessReceiveStatus: () => GaslessReceiveStatus.stale,
          gaslessReceiveReason: () => GaslessReceiveReasonCode.appBackgrounded,
          verifiedGasfreeAddress: () => null,
          gaslessReceiveWalletPubkeyHash: () => null,
          gaslessAccountStatusObservedAt: () => null,
        ),
      );
    }
  }

  /// Synchronous action-time gate used immediately before a GasFree QR or
  /// clipboard write. A failed check queues a fresh observation but never
  /// allows the stale action to continue.
  bool revalidateGaslessReceiveForAction({
    required String custodyAddress,
    required String walletEpoch,
  }) {
    final observedAt = state.gaslessAccountStatusObservedAt;
    final status = state.gaslessAccountStatus;
    final now = DateTime.now().toUtc();
    final observedRecently =
        observedAt != null &&
        !observedAt.toUtc().isAfter(now) &&
        now.difference(observedAt.toUtc()) <= const Duration(minutes: 1);
    var allowed =
        _isForeground &&
        state.gaslessReceiveStatus == GaslessReceiveStatus.ready &&
        observedRecently &&
        state.verifiedGasfreeAddress?.trim() == custodyAddress.trim() &&
        state.gaslessReceiveWalletPubkeyHash?.trim() == walletEpoch.trim() &&
        status != null &&
        isVerifiedTronGaslessReceiveStatus(
          status,
          custodyAddress: custodyAddress,
          expectedServiceProvider: tronGaslessServiceProvider,
        );
    if (allowed) {
      try {
        final asset = getSdkAsset(sdk, assetId);
        allowed =
            asset.isTronGaslessReceiveConfiguredAsset &&
            hasTronGaslessReceiveCapability(sdk, asset);
      } catch (_) {
        allowed = false;
      }
    }
    if (!allowed && !isClosed) {
      final reason = !_isForeground
          ? GaslessReceiveReasonCode.appBackgrounded
          : state.gaslessReceiveWalletPubkeyHash?.trim() != walletEpoch.trim()
          ? GaslessReceiveReasonCode.custodyAddressMismatch
          : GaslessReceiveReasonCode.accountStatusExpired;
      _logGaslessReceiveRevocation(reason);
      add(const CoinAddressesGaslessReceiveRefreshRequested());
    }
    return allowed;
  }

  Future<_ResolvedGaslessReceive> _resolveGaslessReceive(
    Asset asset,
    List<PubkeyInfo> addresses, {
    required bool isHdWallet,
    required bool isPrimarySoftwareWallet,
  }) async {
    if (!asset.isTronGaslessRecoveryEligibleAsset) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.unsupported,
        reason: GaslessReceiveReasonCode.assetUnsupported,
      );
    }
    if (!hasValidTronGaslessProviderConfig ||
        !isTronGaslessAssetEligible(asset)) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.securityMismatch,
        reason: GaslessReceiveReasonCode.providerConfigurationInvalid,
      );
    }
    if (!isPrimarySoftwareWallet) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.unsupported,
        reason: GaslessReceiveReasonCode.walletUnsupported,
      );
    }

    final canonical = addresses
        .where(
          (address) =>
              isCanonicalTronGaslessPubkey(address, isHdWallet: isHdWallet),
        )
        .toList(growable: false);
    if (canonical.length > 1) {
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.securityMismatch,
        reason: GaslessReceiveReasonCode.canonicalAddressAmbiguous,
      );
    }
    final candidate = canonical.singleOrNull?.gasfreeAddress;
    if (candidate == null || candidate.isEmpty) {
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.custodyAddressMissing,
        shouldRefresh: true,
      );
    }
    if (candidate != candidate.trim()) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.securityMismatch,
        reason: GaslessReceiveReasonCode.custodyAddressMismatch,
      );
    }

    late final GaslessAccountStatusResponse accountStatus;
    late final DateTime observedAt;
    try {
      accountStatus = await sdk.withdrawals.gaslessAccountStatus(asset.id);
      observedAt = DateTime.now().toUtc();
      final serviceProvider = accountStatus.serviceProvider;
      if (serviceProvider != null &&
          serviceProvider != tronGaslessServiceProvider.trim()) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.providerIdentityMismatch,
        );
      }
      final authoritativeAddress = accountStatus.gasfreeAddress;
      if (authoritativeAddress != candidate) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.custodyAddressMismatch,
        );
      }
      switch (accountStatus.availability) {
        case GaslessAccountAvailability.available:
          if (!isVerifiedTronGaslessReceiveStatus(
            accountStatus,
            custodyAddress: candidate,
            expectedServiceProvider: tronGaslessServiceProvider,
          )) {
            return _ResolvedGaslessReceive(
              status: GaslessReceiveStatus.securityMismatch,
              reason: GaslessReceiveReasonCode.providerIdentityMismatch,
            );
          }
        case GaslessAccountAvailability.pendingTransfer:
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.temporarilyUnavailable,
            reason: GaslessReceiveReasonCode.pendingTransfer,
            shouldRefresh: true,
            accountStatus: accountStatus,
            observedAt: observedAt,
          );
        case GaslessAccountAvailability.tokenUnsupported:
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.unsupported,
            reason: GaslessReceiveReasonCode.tokenUnsupported,
            shouldRefresh: true,
            accountStatus: accountStatus,
            observedAt: observedAt,
          );
        case GaslessAccountAvailability.providerUnreachable:
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.temporarilyUnavailable,
            reason: GaslessReceiveReasonCode.providerTemporarilyUnavailable,
            shouldRefresh: true,
            accountStatus: accountStatus,
            observedAt: observedAt,
          );
      }
    } catch (error) {
      final mapped = _mapGaslessAccountStatusError(error);
      if (mapped != null) return mapped;
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.accountStatusUnavailable,
        shouldRefresh: true,
      );
    }

    // The build switches authorize new receives only. The account-status probe
    // above remains active so existing custody balances, pending transfers,
    // and recovery state never disappear when a receive rail is disabled.
    if (!tronGaslessReceiveEnabled) {
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.disabled,
        reason: GaslessReceiveReasonCode.receiveBuildDisabled,
        shouldRefresh: true,
        accountStatus: accountStatus,
        observedAt: observedAt,
      );
    }

    return _ResolvedGaslessReceive(
      status: GaslessReceiveStatus.ready,
      reason: GaslessReceiveReasonCode.ready,
      address: accountStatus.gasfreeAddress,
      shouldRefresh: true,
      accountStatus: accountStatus,
      observedAt: observedAt,
    );
  }

  bool _isPrimarySoftwareWallet(KdfUser? user) =>
      user != null &&
      user.walletId.authOptions.privKeyPolicy ==
          const PrivateKeyPolicy.contextPrivKey();

  @visibleForTesting
  static ({
    GaslessReceiveStatus status,
    GaslessReceiveReasonCode reason,
    bool shouldRefresh,
  })?
  mapGaslessAccountStatusErrorForTesting(Object error) {
    final resolved = _mapGaslessAccountStatusError(error);
    if (resolved == null) return null;
    return (
      status: resolved.status,
      reason: resolved.reason,
      shouldRefresh: resolved.shouldRefresh,
    );
  }

  static _ResolvedGaslessReceive? _mapGaslessAccountStatusError(Object error) {
    if (error is FormatException || error is ArgumentError) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.securityMismatch,
        reason: GaslessReceiveReasonCode.malformedAccountStatus,
      );
    }
    if (error is GaslessTransferException) {
      final (status, reason, shouldRefresh) = switch (error.code) {
        GaslessTransferErrorCode.serviceProviderMismatch => (
          GaslessReceiveStatus.securityMismatch,
          GaslessReceiveReasonCode.providerIdentityMismatch,
          false,
        ),
        GaslessTransferErrorCode.custodyAddressMismatch => (
          GaslessReceiveStatus.securityMismatch,
          GaslessReceiveReasonCode.custodyAddressMismatch,
          false,
        ),
        GaslessTransferErrorCode.tokenDecimalMismatch => (
          GaslessReceiveStatus.securityMismatch,
          GaslessReceiveReasonCode.tokenDecimalsMismatch,
          false,
        ),
        GaslessTransferErrorCode.responseMismatch => (
          GaslessReceiveStatus.securityMismatch,
          GaslessReceiveReasonCode.malformedAccountStatus,
          false,
        ),
        GaslessTransferErrorCode.unsupportedToken ||
        GaslessTransferErrorCode.wrongCoinType ||
        GaslessTransferErrorCode.coinNotSupported ||
        GaslessTransferErrorCode.notEthCoin => (
          GaslessReceiveStatus.unsupported,
          GaslessReceiveReasonCode.assetUnsupported,
          false,
        ),
        GaslessTransferErrorCode.configurationInvalid ||
        GaslessTransferErrorCode.capabilityNotReady ||
        GaslessTransferErrorCode.gaslessNotConfigured ||
        GaslessTransferErrorCode.coinNotFound when !error.retryable => (
          GaslessReceiveStatus.disabled,
          GaslessReceiveReasonCode.reactivationRequired,
          false,
        ),
        GaslessTransferErrorCode.providerUnavailable ||
        GaslessTransferErrorCode.providerTimeout ||
        GaslessTransferErrorCode.traceUnavailable => (
          GaslessReceiveStatus.temporarilyUnavailable,
          GaslessReceiveReasonCode.providerTemporarilyUnavailable,
          true,
        ),
        _ when error.kind == GaslessTransferErrorKind.providerResponse => (
          GaslessReceiveStatus.securityMismatch,
          GaslessReceiveReasonCode.malformedAccountStatus,
          false,
        ),
        _
            when !error.retryable &&
                (error.kind == GaslessTransferErrorKind.configuration ||
                    error.kind ==
                        GaslessTransferErrorKind.capabilityNotReady) =>
          (
            GaslessReceiveStatus.disabled,
            GaslessReceiveReasonCode.reactivationRequired,
            false,
          ),
        _ => (
          GaslessReceiveStatus.temporarilyUnavailable,
          GaslessReceiveReasonCode.accountStatusUnavailable,
          error.retryable,
        ),
      };
      return _ResolvedGaslessReceive(
        status: status,
        reason: reason,
        shouldRefresh: shouldRefresh,
      );
    }
    return null;
  }

  String? _readyWalletPubkeyHash(
    _ResolvedGaslessReceive resolved,
    String? walletPubkeyHash,
  ) {
    final normalized = walletPubkeyHash?.trim();
    return resolved.status == GaslessReceiveStatus.ready &&
            normalized != null &&
            normalized.isNotEmpty
        ? normalized
        : null;
  }

  void _logGaslessReceiveDecision(_ResolvedGaslessReceive resolved) {
    if (_lastLoggedGaslessReceiveWasReady &&
        resolved.status != GaslessReceiveStatus.ready) {
      _logGaslessReceiveRevocation(resolved.reason);
    }
    _lastLoggedGaslessReceiveWasReady =
        resolved.status == GaslessReceiveStatus.ready;
    final key = '${resolved.status.name}:${resolved.reason.code}';
    if (_lastGaslessReceiveAnalyticsKey == key) return;
    _lastGaslessReceiveAnalyticsKey = key;
    analyticsBloc.logEvent(
      GaslessReceiveAnalyticsEventData(
        status: _gaslessReceiveAnalyticsStatus(resolved.status),
        reason: resolved.reason,
      ),
    );
  }

  void _logGaslessReceiveRevocation(GaslessReceiveReasonCode reason) {
    if (!_lastLoggedGaslessReceiveWasReady &&
        state.gaslessReceiveStatus != GaslessReceiveStatus.ready) {
      return;
    }
    _lastLoggedGaslessReceiveWasReady = false;
    final key = 'revoked:${reason.code}';
    if (_lastGaslessReceiveAnalyticsKey == key) return;
    _lastGaslessReceiveAnalyticsKey = key;
    analyticsBloc.logEvent(
      GaslessReceiveAnalyticsEventData(
        status: GaslessReceiveAnalyticsStatus.revoked,
        reason: reason,
      ),
    );
  }

  GaslessReceiveAnalyticsStatus _gaslessReceiveAnalyticsStatus(
    GaslessReceiveStatus status,
  ) => switch (status) {
    GaslessReceiveStatus.initial => GaslessReceiveAnalyticsStatus.initial,
    GaslessReceiveStatus.checking => GaslessReceiveAnalyticsStatus.checking,
    GaslessReceiveStatus.ready => GaslessReceiveAnalyticsStatus.ready,
    GaslessReceiveStatus.stale => GaslessReceiveAnalyticsStatus.stale,
    GaslessReceiveStatus.temporarilyUnavailable =>
      GaslessReceiveAnalyticsStatus.temporarilyUnavailable,
    GaslessReceiveStatus.disabled => GaslessReceiveAnalyticsStatus.disabled,
    GaslessReceiveStatus.unsupported =>
      GaslessReceiveAnalyticsStatus.unsupported,
    GaslessReceiveStatus.securityMismatch =>
      GaslessReceiveAnalyticsStatus.securityMismatch,
  };

  void _scheduleGaslessReceiveRefresh(_ResolvedGaslessReceive resolved) {
    _gaslessReceiveRefreshTimer?.cancel();
    _gaslessReceiveRefreshTimer = null;
    if (!resolved.shouldRefresh || isClosed) return;

    // Refresh the typed status before the action-time one-minute freshness
    // boundary. QR and copy still recheck it synchronously.
    _gaslessReceiveRefreshTimer = Timer(const Duration(seconds: 30), () {
      if (!isClosed) {
        add(const CoinAddressesGaslessReceiveRefreshRequested());
      }
    });
  }

  void _onPubkeysSubscriptionFailed(
    CoinAddressesPubkeysSubscriptionFailed event,
    Emitter<CoinAddressesState> emit,
  ) {
    final eventSubscriptionGeneration = event.subscriptionGeneration;
    if (eventSubscriptionGeneration != null &&
        eventSubscriptionGeneration != _pubkeysSubscriptionGeneration) {
      return;
    }
    _gaslessReceiveEvaluationGeneration += 1;
    // This emits a terminal `status`, so it must also supersede any in-flight
    // address load rather than let one land on top of the failure.
    _addressesLoadGeneration += 1;
    final failClosed = _shouldFailClosedGaslessReceive;
    const unavailable = _ResolvedGaslessReceive(
      status: GaslessReceiveStatus.temporarilyUnavailable,
      reason: GaslessReceiveReasonCode.accountStatusUnavailable,
      shouldRefresh: true,
    );
    emit(
      state.copyWith(
        status: () => FormStatus.failure,
        addresses: () => const <PubkeyInfo>[],
        cantCreateNewAddressReasons: () => null,
        newAddressState: () => null,
        errorMessage: () => event.error,
        gaslessReceiveStatus: failClosed
            ? () => GaslessReceiveStatus.temporarilyUnavailable
            : null,
        gaslessReceiveReason: failClosed
            ? () => GaslessReceiveReasonCode.accountStatusUnavailable
            : null,
        verifiedGasfreeAddress: failClosed ? () => null : null,
        gaslessReceiveWalletPubkeyHash: failClosed ? () => null : null,
        gaslessAccountStatus: failClosed ? () => null : null,
        gaslessAccountStatusObservedAt: failClosed ? () => null : null,
      ),
    );
    if (failClosed) {
      _logGaslessReceiveDecision(unavailable);
      _scheduleGaslessReceiveRefresh(unavailable);
    }
  }

  bool get _shouldFailClosedGaslessReceive =>
      state.gaslessReceiveStatus != GaslessReceiveStatus.initial &&
      state.gaslessReceiveStatus != GaslessReceiveStatus.unsupported;

  Future<void> _startWatchingPubkeys(Asset asset) async {
    final subscriptionGeneration = ++_pubkeysSubscriptionGeneration;
    try {
      await _pubkeysSub?.cancel();
      _pubkeysSub = null;
      // Pre-cache pubkeys to ensure that any newly created pubkeys are available
      // when we start watching. UI flickering between old and new states is
      // avoided this way. The watchPubkeys function yields the last known pubkeys
      // when the pubkeys stream is first activated.
      await sdk.pubkeys.precachePubkeys(asset);
      if (subscriptionGeneration != _pubkeysSubscriptionGeneration ||
          isClosed) {
        return;
      }
      _pubkeysSub = sdk.pubkeys
          .watchPubkeys(asset, activateIfNeeded: true)
          .listen(
            (AssetPubkeys assetPubkeys) {
              if (!isClosed &&
                  subscriptionGeneration == _pubkeysSubscriptionGeneration) {
                add(
                  CoinAddressesPubkeysUpdated(
                    assetPubkeys.keys,
                    subscriptionGeneration: subscriptionGeneration,
                  ),
                );
              }
            },
            onError: (Object err) {
              if (!isClosed &&
                  subscriptionGeneration == _pubkeysSubscriptionGeneration) {
                add(
                  CoinAddressesPubkeysSubscriptionFailed(
                    _buildDisplayError(err),
                    subscriptionGeneration: subscriptionGeneration,
                  ),
                );
              }
            },
          );
    } catch (e) {
      if (!isClosed &&
          subscriptionGeneration == _pubkeysSubscriptionGeneration) {
        add(
          CoinAddressesPubkeysSubscriptionFailed(
            _buildDisplayError(e),
            subscriptionGeneration: subscriptionGeneration,
          ),
        );
      }
    }
  }

  Future<({KdfUser user, List<PubkeyInfo> addresses})?>
  _readCurrentWalletAddresses(Asset asset) async {
    final initialUser = await sdk.auth.currentUser;
    if (initialUser == null) throw AuthException.notSignedIn();

    // PubkeyManager captures and revalidates the authenticated wallet around
    // cache access and refresh. Confirm the same identity again here because
    // this BLoC combines those addresses with wallet-scoped GasFree status.
    final addresses = (await asset.getPubkeys(sdk)).keys;
    final verifiedUser = await sdk.auth.currentUser;
    if (verifiedUser == null) throw AuthException.notSignedIn();
    if (verifiedUser.walletId != initialUser.walletId) {
      return null;
    }
    return (user: verifiedUser, addresses: addresses);
  }

  Future<bool> _isCurrentWallet(WalletId expected) async {
    final currentUser = await sdk.auth.currentUser;
    return currentUser != null && currentUser.walletId == expected;
  }

  String _buildDisplayError(Object error) {
    if (_isNetworkLikeError(error)) {
      return LocaleKeys.connectionToServersFailing.tr(args: [assetId]);
    }

    return formatKdfUserFacingError(error);
  }

  bool _isNetworkLikeError(Object error) {
    if (error is SdkError) {
      return error.category == SdkErrorCategory.network;
    }

    if (error is MmRpcException) {
      const networkErrorTypes = {
        'Transport',
        'Timeout',
        'TaskTimedOut',
        'UnreachableNodes',
        'ClientConnectionFailed',
        'ConnectToNodeError',
      };
      if (networkErrorTypes.contains(error.errorType)) {
        return true;
      }
      return _containsNetworkMarkers(
        '${error.message ?? ''} ${error.path ?? ''}',
      );
    }

    if (error is GeneralErrorResponse) {
      const networkErrorTypes = {
        'Transport',
        'Timeout',
        'TaskTimedOut',
        'UnreachableNodes',
        'ClientConnectionFailed',
        'ConnectToNodeError',
      };
      if (error.errorType != null &&
          networkErrorTypes.contains(error.errorType)) {
        return true;
      }
      return _containsNetworkMarkers(error.error ?? '');
    }

    return _containsNetworkMarkers(error.toString());
  }

  bool _containsNetworkMarkers(String input) {
    final normalized = input.toLowerCase();
    return normalized.contains('failed to fetch') ||
        normalized.contains('network') ||
        normalized.contains('connection') ||
        normalized.contains('timeout') ||
        normalized.contains('unreachable');
  }

  @override
  Future<void> close() async {
    _gaslessReceiveEvaluationGeneration += 1;
    _addressesLoadGeneration += 1;
    _pubkeysSubscriptionGeneration += 1;
    _gaslessReceiveRefreshTimer?.cancel();
    _gaslessReceiveRefreshTimer = null;
    await _pubkeysSub?.cancel();
    _pubkeysSub = null;
    return super.close();
  }
}

class _ResolvedGaslessReceive {
  const _ResolvedGaslessReceive({
    required this.status,
    required this.reason,
    this.address,
    this.shouldRefresh = false,
    this.accountStatus,
    this.observedAt,
  });

  final GaslessReceiveStatus status;
  final GaslessReceiveReasonCode reason;
  final String? address;
  final bool shouldRefresh;
  final GaslessAccountStatusResponse? accountStatus;
  final DateTime? observedAt;
}
