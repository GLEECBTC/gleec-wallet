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
import 'package:web_dex/shared/utils/kdf_error_display.dart';

class CoinAddressesBloc extends Bloc<CoinAddressesEvent, CoinAddressesState> {
  final KomodoDefiSdk sdk;
  final String assetId;
  final AnalyticsBloc analyticsBloc;

  StreamSubscription<AssetPubkeys>? _pubkeysSub;
  CoinAddressesBloc(this.sdk, this.assetId, this.analyticsBloc)
    : super(const CoinAddressesState()) {
    on<CoinAddressesAddressCreationSubmitted>(_onCreateAddressSubmitted);
    on<CoinAddressesStarted>(_onStarted);
    on<CoinAddressesSubscriptionRequested>(_onAddressesSubscriptionRequested);
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
    emit(state.copyWith(status: () => FormStatus.submitting));

    try {
      final asset = getSdkAsset(sdk, assetId);
      // Prefer cached pubkeys to avoid unnecessary RPC delay
      final cached = sdk.pubkeys.lastKnown(asset.id);
      final addresses = (cached ?? await asset.getPubkeys(sdk)).keys;

      final reasons = await asset.getCantCreateNewAddressReasons(sdk);

      emit(
        state.copyWith(
          status: () => FormStatus.success,
          addresses: () => addresses,
          cantCreateNewAddressReasons: () => reasons,
          errorMessage: () => null,
        ),
      );

      await _startWatchingPubkeys(asset);
    } catch (e) {
      emit(
        state.copyWith(
          status: () => FormStatus.failure,
          errorMessage: () => _buildDisplayError(e),
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
    try {
      final asset = getSdkAsset(sdk, assetId);
      final reasons = await asset.getCantCreateNewAddressReasons(sdk);
      emit(
        state.copyWith(
          status: () => FormStatus.success,
          addresses: () => event.addresses,
          cantCreateNewAddressReasons: () => reasons,
          errorMessage: () => null,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: () => _buildDisplayError(e)));
    }
  }

  void _onPubkeysSubscriptionFailed(
    CoinAddressesPubkeysSubscriptionFailed event,
    Emitter<CoinAddressesState> emit,
  ) {
    emit(
      state.copyWith(
        status: () => FormStatus.failure,
        errorMessage: () => event.error,
      ),
    );
  }

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

    if (error is SdkError) {
      return _localizedSdkError(error);
    }

    if (error is MmRpcException) {
      return error.localizedMessage;
    }

    if (error is GeneralErrorResponse) {
      return error.localizedMessage;
    }

    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return LocaleKeys.somethingWrong.tr();
    }

    const exceptionPrefix = 'Exception: ';
    if (raw.startsWith(exceptionPrefix)) {
      final message = raw.substring(exceptionPrefix.length).trim();
      if (message.isNotEmpty) {
        return message;
      }
    }

    return raw;
  }

  String _localizedSdkError(SdkError error) {
    final localized = error.messageKey.tr(args: error.messageArgs);
    return localized == error.messageKey ? error.fallbackMessage : localized;
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
    await _pubkeysSub?.cancel();
    _pubkeysSub = null;
    return super.close();
  }
}
