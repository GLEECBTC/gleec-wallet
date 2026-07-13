import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/analytics/events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_receive_gate.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';

class CoinAddressesBloc extends Bloc<CoinAddressesEvent, CoinAddressesState> {
  final KomodoDefiSdk sdk;
  final String assetId;
  final AnalyticsBloc analyticsBloc;
  final TronGaslessReceiveGate _gaslessReceiveGate;

  StreamSubscription<AssetPubkeys>? _pubkeysSub;
  Timer? _gaslessReceiveRefreshTimer;
  int _gaslessReceiveEvaluationGeneration = 0;

  CoinAddressesBloc(
    this.sdk,
    this.assetId,
    this.analyticsBloc, {
    TronGaslessReceiveGate? gaslessReceiveGate,
  }) : _gaslessReceiveGate =
           gaslessReceiveGate ??
           HttpTronGaslessReceiveGate(
             endpoint: tronGaslessControlUrl,
             expectedNetwork: tronGaslessNetworkPath(tronGaslessBaseUrl) ?? '',
             expectedServiceProvider: tronGaslessServiceProvider,
           ),
       super(const CoinAddressesState()) {
    on<CoinAddressesAddressCreationSubmitted>(_onCreateAddressSubmitted);
    on<CoinAddressesStarted>(_onStarted);
    on<CoinAddressesSubscriptionRequested>(_onAddressesSubscriptionRequested);
    on<CoinAddressesGaslessReceiveRefreshRequested>(
      _onGaslessReceiveRefreshRequested,
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
    final failClosed = _shouldFailClosedGaslessReceive;
    emit(
      state.copyWith(
        status: () => FormStatus.submitting,
        gaslessReceiveStatus: failClosed
            ? () => GaslessReceiveStatus.checking
            : null,
        gaslessReceiveReason: failClosed ? () => null : null,
        gaslessReceiveConfigExpiresAt: failClosed ? () => null : null,
        verifiedGasfreeAddress: failClosed ? () => null : null,
        gaslessReceiveWalletPubkeyHash: failClosed ? () => null : null,
      ),
    );

    try {
      final asset = getSdkAsset(sdk, assetId);
      // Prefer cached pubkeys to avoid unnecessary RPC delay
      final cached = sdk.pubkeys.lastKnown(asset.id);
      final addresses = (cached ?? await asset.getPubkeys(sdk)).keys;
      final currentUser = await sdk.auth.currentUser;
      final isHdWallet = currentUser?.isHd ?? false;
      final walletPubkeyHash = currentUser?.walletId.pubkeyHash?.trim();

      final reasons = await asset.getCantCreateNewAddressReasons(sdk);
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
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
            gaslessReceiveConfigExpiresAt: () => null,
            verifiedGasfreeAddress: () => null,
            gaslessReceiveWalletPubkeyHash: () => null,
          ),
        );
      }
      final gaslessReceive = await _resolveGaslessReceive(
        asset,
        addresses,
        isHdWallet: isHdWallet,
      );
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
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
          gaslessReceiveConfigExpiresAt: () => gaslessReceive.expiresAt,
          verifiedGasfreeAddress: () => gaslessReceive.address,
          gaslessReceiveWalletPubkeyHash: () =>
              _readyWalletPubkeyHash(gaslessReceive, walletPubkeyHash),
        ),
      );
      _scheduleGaslessReceiveRefresh(gaslessReceive);

      await _startWatchingPubkeys(asset);
    } catch (e) {
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
        return;
      }
      final failClosed = _shouldFailClosedGaslessReceive;
      emit(
        state.copyWith(
          status: () => FormStatus.failure,
          errorMessage: () => _buildDisplayError(e),
          gaslessReceiveStatus: failClosed
              ? () => GaslessReceiveStatus.temporarilyUnavailable
              : null,
          gaslessReceiveReason: failClosed
              ? () => GaslessReceiveReasonCode.accountStatusUnavailable
              : null,
          gaslessReceiveConfigExpiresAt: failClosed ? () => null : null,
          verifiedGasfreeAddress: failClosed ? () => null : null,
          gaslessReceiveWalletPubkeyHash: failClosed ? () => null : null,
        ),
      );
    }
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
    final evaluationGeneration = ++_gaslessReceiveEvaluationGeneration;
    try {
      final asset = getSdkAsset(sdk, assetId);
      if (asset.isTronGaslessReceiveConfiguredAsset ||
          state.gaslessReceiveStatus == GaslessReceiveStatus.ready) {
        // A pubkey replacement or duplicate candidate invalidates the prior
        // custody attestation immediately. Clear QR/copy authorization before
        // the first asynchronous provider or wallet lookup can yield.
        emit(
          state.copyWith(
            addresses: () => event.addresses,
            gaslessReceiveStatus: () => GaslessReceiveStatus.checking,
            gaslessReceiveReason: () => null,
            verifiedGasfreeAddress: () => null,
            gaslessReceiveWalletPubkeyHash: () => null,
          ),
        );
      }
      final reasons = await asset.getCantCreateNewAddressReasons(sdk);
      final currentUser = await sdk.auth.currentUser;
      final isHdWallet = currentUser?.isHd ?? false;
      final walletPubkeyHash = currentUser?.walletId.pubkeyHash?.trim();
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
        return;
      }
      final gaslessReceive = await _resolveGaslessReceive(
        asset,
        event.addresses,
        isHdWallet: isHdWallet,
      );
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: () => FormStatus.success,
          addresses: () => event.addresses,
          cantCreateNewAddressReasons: () => reasons,
          errorMessage: () => null,
          gaslessReceiveStatus: () => gaslessReceive.status,
          gaslessReceiveReason: () => gaslessReceive.reason,
          gaslessReceiveConfigExpiresAt: () => gaslessReceive.expiresAt,
          verifiedGasfreeAddress: () => gaslessReceive.address,
          gaslessReceiveWalletPubkeyHash: () =>
              _readyWalletPubkeyHash(gaslessReceive, walletPubkeyHash),
        ),
      );
      _scheduleGaslessReceiveRefresh(gaslessReceive);
    } catch (e) {
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
        return;
      }
      final failClosed = _shouldFailClosedGaslessReceive;
      emit(
        state.copyWith(
          errorMessage: () => _buildDisplayError(e),
          gaslessReceiveStatus: failClosed
              ? () => GaslessReceiveStatus.temporarilyUnavailable
              : null,
          gaslessReceiveReason: failClosed
              ? () => GaslessReceiveReasonCode.accountStatusUnavailable
              : null,
          gaslessReceiveConfigExpiresAt: failClosed ? () => null : null,
          verifiedGasfreeAddress: failClosed ? () => null : null,
          gaslessReceiveWalletPubkeyHash: failClosed ? () => null : null,
        ),
      );
    }
  }

  Future<void> _onGaslessReceiveRefreshRequested(
    CoinAddressesGaslessReceiveRefreshRequested event,
    Emitter<CoinAddressesState> emit,
  ) async {
    final evaluationGeneration = ++_gaslessReceiveEvaluationGeneration;
    final expiry = state.gaslessReceiveConfigExpiresAt;
    if (state.gaslessReceiveStatus == GaslessReceiveStatus.ready) {
      // A sensitive recheck revokes the rendered QR before the first await;
      // the SDK likewise revokes the older per-wallet evidence/request epoch.
      final remoteExpired =
          expiry == null || !expiry.isAfter(DateTime.now().toUtc());
      emit(
        state.copyWith(
          gaslessReceiveStatus: () => GaslessReceiveStatus.checking,
          gaslessReceiveReason: () =>
              remoteExpired ? GaslessReceiveReasonCode.remoteExpired : null,
          gaslessReceiveConfigExpiresAt: () => remoteExpired ? null : expiry,
          verifiedGasfreeAddress: () => null,
          gaslessReceiveWalletPubkeyHash: () => null,
        ),
      );
    }

    try {
      final asset = getSdkAsset(sdk, assetId);
      final currentUser = await sdk.auth.currentUser;
      final isHdWallet = currentUser?.isHd ?? false;
      final walletPubkeyHash = currentUser?.walletId.pubkeyHash?.trim();
      final gaslessReceive = await _resolveGaslessReceive(
        asset,
        state.addresses,
        isHdWallet: isHdWallet,
      );
      if (evaluationGeneration != _gaslessReceiveEvaluationGeneration ||
          emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          gaslessReceiveStatus: () => gaslessReceive.status,
          gaslessReceiveReason: () => gaslessReceive.reason,
          gaslessReceiveConfigExpiresAt: () => gaslessReceive.expiresAt,
          verifiedGasfreeAddress: () => gaslessReceive.address,
          gaslessReceiveWalletPubkeyHash: () =>
              _readyWalletPubkeyHash(gaslessReceive, walletPubkeyHash),
        ),
      );
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
          gaslessReceiveConfigExpiresAt: () => null,
          verifiedGasfreeAddress: () => null,
          gaslessReceiveWalletPubkeyHash: () => null,
        ),
      );
      _scheduleGaslessReceiveRefresh(unavailable);
    }
  }

  Future<_ResolvedGaslessReceive> _resolveGaslessReceive(
    Asset asset,
    List<PubkeyInfo> addresses, {
    required bool isHdWallet,
  }) async {
    if (!asset.isTronGaslessRecoveryEligibleAsset) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.unsupported,
        reason: GaslessReceiveReasonCode.assetUnsupported,
      );
    }
    if (!tronGaslessEnabled) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.disabled,
        reason: GaslessReceiveReasonCode.buildFeatureDisabled,
      );
    }
    if (!hasValidTronGaslessProviderConfig ||
        !asset.isTronGaslessConfiguredAsset) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.securityMismatch,
        reason: GaslessReceiveReasonCode.providerConfigurationInvalid,
      );
    }
    if (!tronGaslessReceiveEnabled) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.disabled,
        reason: GaslessReceiveReasonCode.receiveBuildDisabled,
      );
    }
    final hasBoundReceive = hasBoundTronGaslessReceiveCapability(sdk, asset);
    if (!hasBoundReceive && !tronGaslessStatusAttestedReceiveEnabled) {
      return const _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.disabled,
        reason: GaslessReceiveReasonCode.boundRelayRequired,
        shouldRefresh: true,
      );
    }

    TronGaslessReceiveGateDecision remoteGate;
    try {
      remoteGate = await _gaslessReceiveGate.evaluate();
    } catch (_) {
      remoteGate = const TronGaslessReceiveGateDecision(
        outcome: TronGaslessReceiveGateOutcome.unavailable,
        reason: GaslessReceiveReasonCode.remoteUnavailable,
      );
    }

    if (remoteGate.outcome == TronGaslessReceiveGateOutcome.enabled) {
      final expiresAt = remoteGate.expiresAt;
      if (remoteGate.reason != GaslessReceiveReasonCode.remoteEnabled ||
          expiresAt == null) {
        return const _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.remoteSchemaMismatch,
          shouldRefresh: true,
        );
      }
      if (!expiresAt.isAfter(DateTime.now().toUtc())) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.stale,
          reason: GaslessReceiveReasonCode.remoteExpired,
          expiresAt: expiresAt,
          shouldRefresh: true,
        );
      }
    }

    switch (remoteGate.outcome) {
      case TronGaslessReceiveGateOutcome.disabled:
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.disabled,
          reason: remoteGate.reason,
          expiresAt: remoteGate.expiresAt,
          shouldRefresh: true,
        );
      case TronGaslessReceiveGateOutcome.unavailable:
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.temporarilyUnavailable,
          reason: remoteGate.reason,
          expiresAt: remoteGate.expiresAt,
          shouldRefresh: true,
        );
      case TronGaslessReceiveGateOutcome.expired:
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.stale,
          reason: remoteGate.reason,
          expiresAt: remoteGate.expiresAt,
          shouldRefresh: true,
        );
      case TronGaslessReceiveGateOutcome.invalid:
        final missingEndpoint =
            remoteGate.reason ==
            GaslessReceiveReasonCode.controlEndpointMissing;
        return _ResolvedGaslessReceive(
          status: missingEndpoint
              ? GaslessReceiveStatus.disabled
              : GaslessReceiveStatus.securityMismatch,
          reason: remoteGate.reason,
          expiresAt: remoteGate.expiresAt,
          shouldRefresh: !missingEndpoint,
        );
      case TronGaslessReceiveGateOutcome.enabled:
        break;
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
        expiresAt: remoteGate.expiresAt,
      );
    }
    final candidate = canonical.singleOrNull?.gasfreeAddress?.trim();
    if (candidate == null || candidate.isEmpty) {
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.custodyAddressMissing,
        expiresAt: remoteGate.expiresAt,
        shouldRefresh: true,
      );
    }

    try {
      final status = hasBoundReceive
          ? await sdk.withdrawals.gaslessAccountStatus(asset.id)
          : await sdk.withdrawals.gaslessAccountStatusForReceive(
              asset.id,
              expectedGasfreeAddress: candidate,
            );
      if (!status.hasExplicitAvailability) {
        return _legacyStatusUnavailable(status.reasonCode, remoteGate);
      }
      if (status.reasonCode != null) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.statusAttestationMissing,
          expiresAt: remoteGate.expiresAt,
        );
      }
      final degradedShapeFailure = _degradedStatusShapeFailure(status);
      if (degradedShapeFailure != null) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: degradedShapeFailure,
          expiresAt: remoteGate.expiresAt,
        );
      }
      switch (status.availability) {
        case GaslessAccountAvailability.available:
          break;
        case GaslessAccountAvailability.pendingTransfer:
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.temporarilyUnavailable,
            reason: GaslessReceiveReasonCode.pendingTransfer,
            expiresAt: remoteGate.expiresAt,
            shouldRefresh: true,
          );
        case GaslessAccountAvailability.tokenUnsupported:
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.unsupported,
            reason: GaslessReceiveReasonCode.tokenUnsupported,
            expiresAt: remoteGate.expiresAt,
          );
        case GaslessAccountAvailability.providerUnreachable:
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.temporarilyUnavailable,
            reason: GaslessReceiveReasonCode.providerTemporarilyUnavailable,
            expiresAt: remoteGate.expiresAt,
            shouldRefresh: true,
          );
      }
      final serviceProvider = status.serviceProvider?.trim();
      if (serviceProvider == null || serviceProvider.isEmpty) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.statusAttestationMissing,
          expiresAt: remoteGate.expiresAt,
        );
      }
      if (serviceProvider != tronGaslessServiceProvider.trim()) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.providerIdentityMismatch,
          expiresAt: remoteGate.expiresAt,
        );
      }
      final authoritativeAddress = status.gasfreeAddress.trim();
      if (authoritativeAddress != candidate) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.custodyAddressMismatch,
          expiresAt: remoteGate.expiresAt,
          shouldRefresh: true,
        );
      }
      if (status.active == null ||
          status.frozenBalance == null ||
          status.spendableBalance == null ||
          status.transferFee == null ||
          status.maxWithdrawable == null) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.statusAttestationMissing,
          expiresAt: remoteGate.expiresAt,
        );
      }
      if (!hasWalletTronGaslessReceiveCapability(sdk, asset)) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.statusAttestationMissing,
          expiresAt: remoteGate.expiresAt,
        );
      }
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.ready,
        reason: GaslessReceiveReasonCode.ready,
        address: authoritativeAddress,
        expiresAt: remoteGate.expiresAt,
        shouldRefresh: true,
      );
    } catch (_) {
      try {
        final capabilityFailure = _capabilityFailure(
          sdk.gaslessCapability(asset).reasonCode,
          remoteGate,
        );
        if (capabilityFailure != null) return capabilityFailure;
      } catch (_) {
        // Fall through to the privacy-safe unavailable state.
      }
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.accountStatusUnavailable,
        expiresAt: remoteGate.expiresAt,
        shouldRefresh: true,
      );
    }
  }

  _ResolvedGaslessReceive _legacyStatusUnavailable(
    String? reasonCode,
    TronGaslessReceiveGateDecision remoteGate,
  ) {
    final reason = switch (reasonCode) {
      'runtime_restart_required' =>
        GaslessReceiveReasonCode.runtimeRestartRequired,
      'provider_temporarily_unavailable' =>
        GaslessReceiveReasonCode.providerTemporarilyUnavailable,
      'provider_identity_mismatch' =>
        GaslessReceiveReasonCode.providerIdentityMismatch,
      'token_unsupported' => GaslessReceiveReasonCode.tokenUnsupported,
      'token_decimals_mismatch' =>
        GaslessReceiveReasonCode.tokenDecimalsMismatch,
      'custody_address_mismatch' =>
        GaslessReceiveReasonCode.custodyAddressMismatch,
      _ => GaslessReceiveReasonCode.statusAttestationMissing,
    };
    final status = switch (reason) {
      GaslessReceiveReasonCode.runtimeRestartRequired =>
        GaslessReceiveStatus.disabled,
      GaslessReceiveReasonCode.tokenUnsupported =>
        GaslessReceiveStatus.unsupported,
      GaslessReceiveReasonCode.providerIdentityMismatch ||
      GaslessReceiveReasonCode.custodyAddressMismatch ||
      GaslessReceiveReasonCode.tokenDecimalsMismatch ||
      GaslessReceiveReasonCode.statusAttestationMissing =>
        GaslessReceiveStatus.securityMismatch,
      _ => GaslessReceiveStatus.temporarilyUnavailable,
    };
    return _ResolvedGaslessReceive(
      status: status,
      reason: reason,
      expiresAt: remoteGate.expiresAt,
      shouldRefresh: status == GaslessReceiveStatus.temporarilyUnavailable,
    );
  }

  GaslessReceiveReasonCode? _degradedStatusShapeFailure(
    GaslessAccountStatusResponse status,
  ) {
    if (status.availability == GaslessAccountAvailability.available) {
      return null;
    }
    // The V1 wire uses null—not an empty placeholder—to prove that no provider
    // identity was accepted for a balance/recovery-only response.
    if (status.serviceProvider != null) {
      return GaslessReceiveReasonCode.providerIdentityMismatch;
    }
    if (status.spendableBalance != null ||
        status.transferFee != null ||
        status.activationFee != null ||
        status.maxWithdrawable != null) {
      return GaslessReceiveReasonCode.statusAttestationMissing;
    }
    // Pending may retain trusted provider state for presentation. Unsupported
    // and unreachable responses are local-custody snapshots and must not carry
    // any provider-derived account state.
    if (status.availability != GaslessAccountAvailability.pendingTransfer &&
        (status.active != null || status.frozenBalance != null)) {
      return GaslessReceiveReasonCode.statusAttestationMissing;
    }
    return null;
  }

  _ResolvedGaslessReceive? _capabilityFailure(
    String? reasonCode,
    TronGaslessReceiveGateDecision remoteGate,
  ) {
    final (status, reason, shouldRefresh) = switch (reasonCode) {
      'runtime_restart_required' => (
        GaslessReceiveStatus.disabled,
        GaslessReceiveReasonCode.runtimeRestartRequired,
        false,
      ),
      'token_decimals_mismatch' => (
        GaslessReceiveStatus.securityMismatch,
        GaslessReceiveReasonCode.tokenDecimalsMismatch,
        false,
      ),
      'custody_address_mismatch' => (
        GaslessReceiveStatus.securityMismatch,
        GaslessReceiveReasonCode.custodyAddressMismatch,
        false,
      ),
      'provider_identity_mismatch' || 'degraded_provider_identity_present' => (
        GaslessReceiveStatus.securityMismatch,
        GaslessReceiveReasonCode.providerIdentityMismatch,
        false,
      ),
      'invalid_account_status' ||
      'availability_unattested' ||
      'account_status_unconfirmed' ||
      'unexpected_ready_reason' => (
        GaslessReceiveStatus.securityMismatch,
        GaslessReceiveReasonCode.statusAttestationMissing,
        false,
      ),
      'token_unsupported' => (
        GaslessReceiveStatus.unsupported,
        GaslessReceiveReasonCode.tokenUnsupported,
        false,
      ),
      'pending_transfer' => (
        GaslessReceiveStatus.temporarilyUnavailable,
        GaslessReceiveReasonCode.pendingTransfer,
        true,
      ),
      'provider_unreachable' => (
        GaslessReceiveStatus.temporarilyUnavailable,
        GaslessReceiveReasonCode.providerTemporarilyUnavailable,
        true,
      ),
      _ => (null, null, false),
    };
    if (status == null || reason == null) return null;
    return _ResolvedGaslessReceive(
      status: status,
      reason: reason,
      expiresAt: remoteGate.expiresAt,
      shouldRefresh: shouldRefresh,
    );
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

  void _scheduleGaslessReceiveRefresh(_ResolvedGaslessReceive resolved) {
    _gaslessReceiveRefreshTimer?.cancel();
    _gaslessReceiveRefreshTimer = null;
    if (!resolved.shouldRefresh || isClosed) return;

    var delay = const Duration(minutes: 1);
    final expiresAt = resolved.expiresAt;
    if (expiresAt != null) {
      final untilExpiry = expiresAt.difference(DateTime.now().toUtc());
      if (untilExpiry > Duration.zero && untilExpiry < delay) {
        // Fire just after the authorization expires so the handler clears an
        // old ready address before awaiting the next remote response.
        delay = untilExpiry + const Duration(milliseconds: 1);
      }
    }

    _gaslessReceiveRefreshTimer = Timer(delay, () {
      if (!isClosed) {
        add(const CoinAddressesGaslessReceiveRefreshRequested());
      }
    });
  }

  void _onPubkeysSubscriptionFailed(
    CoinAddressesPubkeysSubscriptionFailed event,
    Emitter<CoinAddressesState> emit,
  ) {
    _gaslessReceiveEvaluationGeneration += 1;
    final failClosed = _shouldFailClosedGaslessReceive;
    emit(
      state.copyWith(
        status: () => FormStatus.failure,
        errorMessage: () => event.error,
        gaslessReceiveStatus: failClosed
            ? () => GaslessReceiveStatus.temporarilyUnavailable
            : null,
        gaslessReceiveReason: failClosed
            ? () => GaslessReceiveReasonCode.accountStatusUnavailable
            : null,
        gaslessReceiveConfigExpiresAt: failClosed ? () => null : null,
        verifiedGasfreeAddress: failClosed ? () => null : null,
        gaslessReceiveWalletPubkeyHash: failClosed ? () => null : null,
      ),
    );
  }

  bool get _shouldFailClosedGaslessReceive =>
      state.gaslessReceiveStatus != GaslessReceiveStatus.initial &&
      state.gaslessReceiveStatus != GaslessReceiveStatus.unsupported;

  Future<void> _startWatchingPubkeys(Asset asset) async {
    try {
      await _pubkeysSub?.cancel();
      _pubkeysSub = null;
      // Pre-cache pubkeys to ensure that any newly created pubkeys are available
      // when we start watching. UI flickering between old and new states is
      // avoided this way. The watchPubkeys function yields the last known pubkeys
      // when the pubkeys stream is first activated.
      await sdk.pubkeys.precachePubkeys(asset);
      _pubkeysSub = sdk.pubkeys
          .watchPubkeys(asset, activateIfNeeded: true)
          .listen(
            (AssetPubkeys assetPubkeys) {
              if (!isClosed) {
                add(CoinAddressesPubkeysUpdated(assetPubkeys.keys));
              }
            },
            onError: (Object err) {
              if (!isClosed) {
                add(
                  CoinAddressesPubkeysSubscriptionFailed(
                    _buildDisplayError(err),
                  ),
                );
              }
            },
          );
    } catch (e) {
      if (!isClosed) {
        add(CoinAddressesPubkeysSubscriptionFailed(_buildDisplayError(e)));
      }
    }
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
    _gaslessReceiveRefreshTimer?.cancel();
    _gaslessReceiveRefreshTimer = null;
    await _pubkeysSub?.cancel();
    _pubkeysSub = null;
    _gaslessReceiveGate.dispose();
    return super.close();
  }
}

class _ResolvedGaslessReceive {
  const _ResolvedGaslessReceive({
    required this.status,
    required this.reason,
    this.address,
    this.expiresAt,
    this.shouldRefresh = false,
  });

  final GaslessReceiveStatus status;
  final GaslessReceiveReasonCode reason;
  final String? address;
  final DateTime? expiresAt;
  final bool shouldRefresh;
}
