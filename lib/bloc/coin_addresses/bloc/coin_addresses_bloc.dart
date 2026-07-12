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
      ),
    );

    try {
      final asset = getSdkAsset(sdk, assetId);
      // Prefer cached pubkeys to avoid unnecessary RPC delay
      final cached = sdk.pubkeys.lastKnown(asset.id);
      final addresses = (cached ?? await asset.getPubkeys(sdk)).keys;
      final isHdWallet = (await sdk.auth.currentUser)?.isHd ?? false;

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
      final reasons = await asset.getCantCreateNewAddressReasons(sdk);
      final isHdWallet = (await sdk.auth.currentUser)?.isHd ?? false;
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
    if (state.gaslessReceiveStatus == GaslessReceiveStatus.ready &&
        expiry != null &&
        !expiry.isAfter(DateTime.now().toUtc())) {
      emit(
        state.copyWith(
          gaslessReceiveStatus: () => GaslessReceiveStatus.checking,
          gaslessReceiveReason: () => GaslessReceiveReasonCode.remoteExpired,
          gaslessReceiveConfigExpiresAt: () => null,
          verifiedGasfreeAddress: () => null,
        ),
      );
    }

    try {
      final asset = getSdkAsset(sdk, assetId);
      final isHdWallet = (await sdk.auth.currentUser)?.isHd ?? false;
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
    if (!hasBoundTronGaslessReceiveCapability(sdk, asset)) {
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

    PubkeyInfo? canonical;
    for (final address in addresses) {
      if (isCanonicalTronGaslessPubkey(address, isHdWallet: isHdWallet)) {
        canonical = address;
        break;
      }
    }
    final candidate = canonical?.gasfreeAddress;
    if (candidate == null || candidate.isEmpty) {
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.custodyAddressMissing,
        expiresAt: remoteGate.expiresAt,
        shouldRefresh: true,
      );
    }

    try {
      final status = await sdk.withdrawals.gaslessAccountStatus(asset.id);
      switch (status.reasonCode) {
        case 'provider_temporarily_unavailable':
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.temporarilyUnavailable,
            reason: GaslessReceiveReasonCode.providerTemporarilyUnavailable,
            expiresAt: remoteGate.expiresAt,
            shouldRefresh: true,
          );
        case 'token_unsupported':
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.unsupported,
            reason: GaslessReceiveReasonCode.tokenUnsupported,
            expiresAt: remoteGate.expiresAt,
            shouldRefresh: true,
          );
        case 'token_decimals_mismatch':
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.unsupported,
            reason: GaslessReceiveReasonCode.tokenDecimalsMismatch,
            expiresAt: remoteGate.expiresAt,
            shouldRefresh: true,
          );
        case 'custody_address_mismatch':
          return _ResolvedGaslessReceive(
            status: GaslessReceiveStatus.securityMismatch,
            reason: GaslessReceiveReasonCode.custodyAddressMismatch,
            expiresAt: remoteGate.expiresAt,
            shouldRefresh: true,
          );
      }
      if (!status.providerAvailable) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.temporarilyUnavailable,
          reason: GaslessReceiveReasonCode.providerUnavailable,
          expiresAt: remoteGate.expiresAt,
          shouldRefresh: true,
        );
      }
      if (status.gasfreeAddress != candidate) {
        return _ResolvedGaslessReceive(
          status: GaslessReceiveStatus.securityMismatch,
          reason: GaslessReceiveReasonCode.custodyAddressMismatch,
          expiresAt: remoteGate.expiresAt,
          shouldRefresh: true,
        );
      }
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.ready,
        reason: GaslessReceiveReasonCode.ready,
        address: candidate,
        expiresAt: remoteGate.expiresAt,
        shouldRefresh: true,
      );
    } catch (_) {
      return _ResolvedGaslessReceive(
        status: GaslessReceiveStatus.temporarilyUnavailable,
        reason: GaslessReceiveReasonCode.accountStatusUnavailable,
        expiresAt: remoteGate.expiresAt,
        shouldRefresh: true,
      );
    }
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
