import 'dart:async';
import 'dart:math' show Point;

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/cex_market_data/charts.dart';
import 'package:web_dex/bloc/cex_market_data/common/update_frequency_backoff_strategy.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/bloc/cex_market_data/sdk_auth_activation_extension.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';

part 'profit_loss_event.dart';
part 'profit_loss_state.dart';

class ProfitLossBloc extends Bloc<ProfitLossEvent, ProfitLossState> {
  ProfitLossBloc(
    this._profitLossRepository,
    this._sdk, {
    UpdateFrequencyBackoffStrategy? backoffStrategy,
  }) : _backoffStrategy = backoffStrategy ?? UpdateFrequencyBackoffStrategy(),
       super(const ProfitLossInitial()) {
    // Use the restartable transformer for load events to avoid overlapping
    // events if the user rapidly changes the period (i.e. faster than the
    // previous event can complete).
    on<ProfitLossPortfolioChartLoadRequested>(
      _onLoadPortfolioProfitLoss,
      transformer: restartable(),
    );
    on<ProfitLossPortfolioPeriodChanged>(
      _onPortfolioPeriodChanged,
      transformer: restartable(),
    );
    on<ProfitLossPortfolioChartClearRequested>(_onClearPortfolioProfitLoss);
  }

  final ProfitLossRepository _profitLossRepository;
  final KomodoDefiSdk _sdk;

  final _log = Logger('ProfitLossBloc');
  final UpdateFrequencyBackoffStrategy _backoffStrategy;

  void _onClearPortfolioProfitLoss(
    ProfitLossPortfolioChartClearRequested event,
    Emitter<ProfitLossState> emit,
  ) {
    emit(const ProfitLossInitial());
  }

  Future<void> _onLoadPortfolioProfitLoss(
    ProfitLossPortfolioChartLoadRequested event,
    Emitter<ProfitLossState> emit,
  ) async {
    try {
      final supportedCoins = await event.coins.filterSupportedCoins();
      final filteredEventCoins = event.coins.withoutTestCoins();
      final initialActiveCoins = await supportedCoins.removeInactiveCoins(_sdk);
      if (supportedCoins.isEmpty && filteredEventCoins.length <= 1) {
        return emit(
          PortfolioProfitLossChartUnsupported(
            selectedPeriod: event.selectedPeriod,
          ),
        );
      }

      await _getProfitLossChart(
        event,
        initialActiveCoins,
        useCache: true,
      ).then(emit.call).catchError((Object error, StackTrace stackTrace) {
        const errorMessage = 'Failed to load CACHED portfolio profit/loss';
        _log.warning(errorMessage, error, stackTrace);
      });

      // Fetch the un-cached version of the chart to update the cache.
      if (supportedCoins.isNotEmpty) {
        await _sdk.waitForEnabledCoinsToPassThreshold(
          supportedCoins,
          delay: kActivationPollingInterval,
        );
      }
      final activeCoins = await supportedCoins.removeInactiveCoins(_sdk);
      if (activeCoins.isNotEmpty) {
        await _getProfitLossChart(
          event,
          activeCoins,
          useCache: false,
        ).then(emit.call).catchError((Object e, StackTrace s) {
          _log.severe('Failed to load uncached profit/loss chart', e, s);
        });
      }
    } catch (error, stackTrace) {
      _log.shout('Failed to load portfolio profit/loss', error, stackTrace);
      // Don't emit an error state here, as the periodic refresh attempts should
      // recover at the cost of a longer first loading time.
    }

    // Reset backoff strategy for new load request
    _backoffStrategy.reset();

    // Create periodic update stream with dynamic intervals
    await _runPeriodicUpdates(event, emit);
  }

  Future<ProfitLossState> _getProfitLossChart(
    ProfitLossPortfolioChartLoadRequested event,
    List<Coin> coins, {
    required bool useCache,
  }) async {
    // Do not let exceptions stop the periodic updates. Let the periodic stream
    // retry on the next failure instead of exiting.
    try {
      final filteredChart = await _getSortedProfitLossChartForCoins(
        event,
        coins,
        useCache: useCache,
      );
      final unCachedProfitIncrease = filteredChart.increase;
      final unCachedPercentageIncrease = filteredChart.percentageIncrease;
      return PortfolioProfitLossChartLoadSuccess(
        profitLossChart: filteredChart,
        totalValue: unCachedProfitIncrease,
        percentageIncrease: unCachedPercentageIncrease,
        coins: coins,
        fiatCurrency: event.fiatCoinId,
        selectedPeriod: event.selectedPeriod,
        walletId: event.walletId,
        isUpdating: false,
      );
    } catch (error, stackTrace) {
      _log.shout('Failed periodic profit/loss chart update', error, stackTrace);
      return state;
    }
  }

  Future<void> _onPortfolioPeriodChanged(
    ProfitLossPortfolioPeriodChanged event,
    Emitter<ProfitLossState> emit,
  ) async {
    final eventState = state;
    if (eventState is! PortfolioProfitLossChartLoadSuccess) {
      return emit(
        PortfolioProfitLossChartLoadInProgress(
          selectedPeriod: event.selectedPeriod,
        ),
      );
    }

    emit(
      PortfolioProfitLossChartLoadSuccess(
        profitLossChart: eventState.profitLossChart,
        totalValue: eventState.totalValue,
        percentageIncrease: eventState.percentageIncrease,
        coins: eventState.coins,
        fiatCurrency: eventState.fiatCurrency,
        walletId: eventState.walletId,
        selectedPeriod: event.selectedPeriod,
        isUpdating: true,
      ),
    );

    add(
      ProfitLossPortfolioChartLoadRequested(
        coins: eventState.coins,
        fiatCoinId: eventState.fiatCurrency,
        selectedPeriod: event.selectedPeriod,
        walletId: eventState.walletId,
      ),
    );
  }

  Future<ChartData> _getSortedProfitLossChartForCoins(
    ProfitLossPortfolioChartLoadRequested event,
    List<Coin> coins, {
    bool useCache = true,
  }) async {
    if (!await _sdk.auth.isSignedIn()) {
      _log.warning('Error loading profit/loss chart: User is not signed in');
      return ChartData.empty();
    }

    final supportedCoins = await coins.filterSupportedCoins();
    if (supportedCoins.isEmpty) {
      _log.warning('No supported coins to load profit/loss chart for');
      return ChartData.empty();
    }
    final activeCoins = await supportedCoins.removeInactiveCoins(_sdk);
    if (activeCoins.isEmpty) {
      _log.warning('No active coins to load profit/loss chart for');
      return ChartData.empty();
    }
    final chartsList = await Future.wait(
      activeCoins.map((coin) async {
        // Catch any errors and return an empty chart to prevent a single coin
        // from breaking the entire portfolio chart.
        try {
          final profitLosses = await _profitLossRepository.getProfitLoss(
            coin.id,
            event.fiatCoinId,
            event.walletId,
            useCache: useCache,
          );

          final firstNonZeroProfitLossIndex = profitLosses.indexWhere(
            (element) => element.profitLoss != 0,
          );
          if (firstNonZeroProfitLossIndex == -1) {
            _log.info('No non-zero profit/loss data found for ${coin.abbr}');
            return ChartData.empty();
          }

          final nonZeroProfitLosses = profitLosses.sublist(
            firstNonZeroProfitLossIndex,
          );
          return nonZeroProfitLosses.toChartData();
        } catch (e, s) {
          final cached = useCache ? 'cached' : 'uncached';
          _log.severe('Failed to load $cached profit/loss: ${coin.abbr}', e, s);
          return ChartData.empty();
        }
      }),
    );

    chartsList.removeWhere((element) => element.isEmpty);
    return Charts.merge(chartsList)..sort((a, b) => a.x.compareTo(b.x));
  }

  /// Run periodic updates with exponential backoff strategy
  bool _isStalePeriodicUpdate(Duration selectedPeriod, {String? stage}) {
    if (state.selectedPeriod == selectedPeriod) {
      return false;
    }

    final stageInfo = stage == null ? '' : ' ($stage)';
    _log.fine(
      'Skipping stale profit/loss periodic update$stageInfo: '
      '$selectedPeriod -> ${state.selectedPeriod}.',
    );
    return true;
  }

  Future<void> _runPeriodicUpdates(
    ProfitLossPortfolioChartLoadRequested event,
    Emitter<ProfitLossState> emit,
  ) async {
    while (true) {
      if (isClosed || emit.isDone) {
        _log.fine('Stopping profit/loss periodic updates: bloc closed.');
        break;
      }
      if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'loop-start')) {
        break;
      }
      try {
        await Future.delayed(_backoffStrategy.getNextInterval());

        if (isClosed || emit.isDone) {
          _log.fine(
            'Skipping profit/loss periodic update: bloc closed during delay.',
          );
          break;
        }
        if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'post-delay')) {
          break;
        }

        final supportedCoins = await event.coins.filterSupportedCoins();
        final activeCoins = await supportedCoins.removeInactiveCoins(_sdk);
        if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'pre-fetch')) {
          break;
        }
        final updatedChartState = await _getProfitLossChart(
          event,
          activeCoins,
          useCache: false,
        );
        if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'pre-emit')) {
          break;
        }
        emit(updatedChartState);
      } catch (error, stackTrace) {
        if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'error')) {
          break;
        }
        _log.shout('Failed to load portfolio profit/loss', error, stackTrace);
        emit(
          ProfitLossLoadFailure(
            error: TextError(
              error: formatKdfUserFacingError(error),
              technicalDetails: extractKdfTechnicalDetails(error),
            ),
            selectedPeriod: event.selectedPeriod,
          ),
        );
      }
    }
  }
}
