import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/shared/utils/utils.dart';

import 'models/price_chart_data.dart';
import 'price_chart_event.dart';
import 'price_chart_state.dart';

class PriceChartBloc extends Bloc<PriceChartEvent, PriceChartState> {
  PriceChartBloc(this._sdk) : super(const PriceChartState()) {
    on<PriceChartStarted>(_onStarted);
    on<PriceChartPeriodChanged>(_onIntervalChanged);
    on<PriceChartCoinsSelected>(_onSymbolChanged);
  }

  final KomodoDefiSdk _sdk;

  void _onStarted(
    PriceChartStarted event,
    Emitter<PriceChartState> emit,
  ) async {
    emit(state.copyWith(status: PriceChartStatus.loading));
    try {
      // Populate available coins for the selector from SDK assets if empty
      Map<AssetId, CoinPriceInfo> fetchedCexCoins = state.availableCoins;
      if (fetchedCexCoins.isEmpty) {
        final Map<AssetId, Asset> allAssets = _sdk.assets.available;
        final entries = allAssets.values
            .where((asset) => !excludedAssetList.contains(asset.id.id))
            .where((asset) => !asset.protocol.isTestnet)
            .map(
              (asset) => MapEntry(
                asset.id,
                CoinPriceInfo(
                  ticker: asset.id.symbol.assetConfigId,
                  selectedPeriodIncreasePercentage: 0.0,
                  id: asset.id.id,
                  name: asset.id.name,
                ),
              ),
            );
        fetchedCexCoins = Map<AssetId, CoinPriceInfo>.fromEntries(entries);
      }

      final List<Future<PriceChartDataSeries?>> futures = event.symbols
          .map((symbol) => _sdk.getSdkAsset(symbol).id)
          .map((symbol) async {
            try {
              final startAt = DateTime.now().subtract(event.period);
              final endAt = DateTime.now();
              final interval = _dividePeriodToInterval(event.period);

              final dates = List.generate(
                (endAt.difference(startAt).inSeconds / interval.toSeconds())
                    .toInt(),
                (index) => startAt.add(
                  Duration(seconds: index * interval.toSeconds()),
                ),
              );
              final ohlcData = await _sdk.marketData.fiatPriceHistory(
                symbol,
                dates,
              );

              final rangeChangePercent = _calculatePercentageChange(
                ohlcData.values.firstOrNull,
                ohlcData.values.lastOrNull,
              )?.toDouble();

              return PriceChartDataSeries(
                info: CoinPriceInfo(
                  ticker: symbol.symbol.assetConfigId,
                  id: fetchedCexCoins[symbol]?.id ?? symbol.id,
                  name: fetchedCexCoins[symbol]?.name ?? symbol.name,
                  selectedPeriodIncreasePercentage: rangeChangePercent ?? 0.0,
                ),
                data: ohlcData.entries.map((e) {
                  return PriceChartSeriesPoint(
                    usdValue: e.value.toDouble(),
                    unixTimestamp: e.key.millisecondsSinceEpoch.toDouble(),
                  );
                }).toList(),
              );
            } catch (e) {
              log("Error fetching OHLC data for $symbol: $e");
              return null;
            }
          })
          .toList();

      final data = await Future.wait(futures);

      emit(
        state.copyWith(
          status: PriceChartStatus.success,
          data: data
              .where((series) => series != null)
              .cast<PriceChartDataSeries>()
              .toList(),
          selectedPeriod: event.period,
          availableCoins: fetchedCexCoins,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: PriceChartStatus.failure, error: e.toString()),
      );
    }
  }

  Rational? _calculatePercentageChange(Decimal? first, Decimal? last) {
    if (first == null || last == null) {
      return null;
    }

    if (first == Decimal.zero) {
      return Rational.zero;
    }

    return ((last - first) / first) * Rational.fromInt(100);
  }

  void _onIntervalChanged(
    PriceChartPeriodChanged event,
    Emitter<PriceChartState> emit,
  ) {
    final currentState = state;
    if (currentState.status != PriceChartStatus.success) {
      return;
    }
    emit(state.copyWith(selectedPeriod: event.period));
    add(
      PriceChartStarted(
        symbols: currentState.data.map((e) => e.info.id).toList(),
        period: event.period,
      ),
    );
  }

  void _onSymbolChanged(
    PriceChartCoinsSelected event,
    Emitter<PriceChartState> emit,
  ) {
    add(
      PriceChartStarted(symbols: event.symbols, period: state.selectedPeriod),
    );
  }

  GraphInterval _dividePeriodToInterval(Duration period) {
    if (period.inDays >= 365) {
      return GraphInterval.oneWeek;
    }
    if (period.inDays >= 30) {
      return GraphInterval.oneDay;
    }
    if (period.inDays >= 7) {
      return GraphInterval.sixHours;
    }
    if (period.inDays >= 1) {
      return GraphInterval.oneHour;
    }
    if (period.inHours >= 1) {
      return GraphInterval.oneMinute;
    }

    throw Exception('Unknown interval');
  }
}
