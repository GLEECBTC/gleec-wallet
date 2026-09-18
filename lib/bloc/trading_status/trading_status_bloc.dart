import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
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
    // Seed immediately with cached status if available; continue with stream.
    try {
      final status = _service.currentStatus;
      emit(
        TradingStatusLoadSuccess(
          disallowedAssets: status.disallowedAssets,
          disallowedFeatures: status.disallowedFeatures,
        ),
      );
    } catch (_) {
      // Service not initialized yet; will emit once stream produces data.
    }
    await emit.forEach(
      _service.statusStream,
      onData: (AppGeoStatus status) => TradingStatusLoadSuccess(
        disallowedAssets: status.disallowedAssets,
        disallowedFeatures: status.disallowedFeatures,
      ),
      onError: (error, stackTrace) => TradingStatusLoadFailure(),
    );
  }
}
