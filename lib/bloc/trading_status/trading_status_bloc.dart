import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show ActivationPolicyStatus;
import 'package:web_dex/bloc/trading_status/disallowed_feature.dart';
import 'package:web_dex/bloc/trading_status/app_geo_status.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';
import 'trading_status_service.dart';

part 'trading_status_event.dart';
part 'trading_status_state.dart';

class TradingStatusBloc extends Bloc<TradingStatusEvent, TradingStatusState> {
  TradingStatusBloc(this._service) : super(TradingStatusInitial()) {
    on<TradingStatusCheckRequested>(_onCheckRequested);
    on<TradingStatusWatchStarted>(_onWatchStarted);
  }

  final TradingStatusService _service;

  Future<void> _onCheckRequested(
    TradingStatusCheckRequested event,
    Emitter<TradingStatusState> emit,
  ) async {
    emit(TradingStatusLoadInProgress());
    try {
      final status = await _service.refreshStatus();
      emit(
        TradingStatusLoadSuccess(
          disallowedAssets: status.disallowedAssets,
          disallowedFeatures: status.disallowedFeatures,
        ),
      );
    } catch (_) {
      emit(TradingStatusLoadFailure());
    }
  }

  Future<void> _onWatchStarted(
    TradingStatusWatchStarted event,
    Emitter<TradingStatusState> emit,
  ) async {
    emit(TradingStatusLoadInProgress());
    emit(_stateFor(_service.currentStatus));
    await emit.forEach(_service.statusStream, onData: _stateFor);
  }

  TradingStatusState _stateFor(AppGeoStatus status) =>
      switch (status.lookupStatus) {
        ActivationPolicyStatus.loading => TradingStatusLoadInProgress(),
        ActivationPolicyStatus.unavailable => TradingStatusLoadFailure(),
        ActivationPolicyStatus.ready => TradingStatusLoadSuccess(
          disallowedAssets: status.disallowedAssets,
          disallowedFeatures: status.disallowedFeatures,
        ),
      };
}
