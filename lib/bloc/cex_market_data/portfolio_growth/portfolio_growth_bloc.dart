import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/cex_market_data/charts.dart';
import 'package:web_dex/bloc/cex_market_data/common/update_frequency_backoff_strategy.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_repository.dart';
import 'package:web_dex/bloc/cex_market_data/sdk_auth_activation_extension.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/constants.dart';

part 'portfolio_growth_event.dart';
part 'portfolio_growth_state.dart';

class PortfolioGrowthBloc
    extends Bloc<PortfolioGrowthEvent, PortfolioGrowthState> {
  PortfolioGrowthBloc({
    required PortfolioGrowthRepository portfolioGrowthRepository,
    required KomodoDefiSdk sdk,
    UpdateFrequencyBackoffStrategy? backoffStrategy,
  }) : _sdk = sdk,
       _portfolioGrowthRepository = portfolioGrowthRepository,
       _backoffStrategy = backoffStrategy ?? UpdateFrequencyBackoffStrategy(),
       super(const PortfolioGrowthInitial()) {
    // Use the restartable transformer for period change events to avoid
    // overlapping events if the user rapidly changes the period (i.e. faster
    // than the previous event can complete).
    on<PortfolioGrowthLoadRequested>(
      _onLoadPortfolioGrowth,
      transformer: restartable(),
    );
    on<PortfolioGrowthPeriodChanged>(
      _onPortfolioGrowthPeriodChanged,
      transformer: restartable(),
    );
    on<PortfolioGrowthClearRequested>(_onClearPortfolioGrowth);
  }

  final PortfolioGrowthRepository _portfolioGrowthRepository;
  final KomodoDefiSdk _sdk;
  final _log = Logger('PortfolioGrowthBloc');
  final UpdateFrequencyBackoffStrategy _backoffStrategy;

  void _onClearPortfolioGrowth(
    PortfolioGrowthClearRequested event,
    Emitter<PortfolioGrowthState> emit,
  ) {
    emit(const PortfolioGrowthInitial());
  }

  void _onPortfolioGrowthPeriodChanged(
    PortfolioGrowthPeriodChanged event,
    Emitter<PortfolioGrowthState> emit,
  ) {
    final coins = event.coins.withoutTestCoins();
    final (
      int totalCoins,
      int coinsWithKnownBalance,
      int coinsWithKnownBalanceAndFiat,
    ) = _calculateCoinProgressCounters(
      coins,
    );
    final currentState = state;
    if (currentState is PortfolioGrowthChartLoadSuccess) {
      emit(
        PortfolioGrowthChartLoadSuccess(
          portfolioGrowth: currentState.portfolioGrowth,
          percentageIncrease: currentState.percentageIncrease,
          selectedPeriod: event.selectedPeriod,
          totalBalance: currentState.totalBalance,
          totalChange24h: currentState.totalChange24h,
          percentageChange24h: currentState.percentageChange24h,
          totalCoins: totalCoins,
          coinsWithKnownBalance: coinsWithKnownBalance,
          coinsWithKnownBalanceAndFiat: coinsWithKnownBalanceAndFiat,
          isUpdating: true,
        ),
      );
    } else if (currentState is GrowthChartLoadFailure) {
      emit(
        GrowthChartLoadFailure(
          error: currentState.error,
          selectedPeriod: event.selectedPeriod,
          totalCoins: totalCoins,
          coinsWithKnownBalance: coinsWithKnownBalance,
          coinsWithKnownBalanceAndFiat: coinsWithKnownBalanceAndFiat,
        ),
      );
    } else if (currentState is PortfolioGrowthChartUnsupported) {
      emit(
        PortfolioGrowthChartUnsupported(
          selectedPeriod: event.selectedPeriod,
          totalCoins: totalCoins,
          coinsWithKnownBalance: coinsWithKnownBalance,
          coinsWithKnownBalanceAndFiat: coinsWithKnownBalanceAndFiat,
        ),
      );
    } else {
      emit(const PortfolioGrowthInitial());
    }

    add(
      PortfolioGrowthLoadRequested(
        coins: coins,
        selectedPeriod: event.selectedPeriod,
        fiatCoinId: 'USDT',
        walletId: event.walletId,
      ),
    );
  }

  Future<void> _onLoadPortfolioGrowth(
    PortfolioGrowthLoadRequested event,
    Emitter<PortfolioGrowthState> emit,
  ) async {
    try {
      final List<Coin> coins = await event.coins.filterSupportedCoins(
        (coin) => _portfolioGrowthRepository.isCoinChartSupported(
          coin.id,
          event.fiatCoinId,
        ),
      );
      // Charts for individual coins (coin details) are parsed here as well,
      // and should be hidden if not supported.
      final filteredEventCoins = event.coins.withoutTestCoins();
      if (coins.isEmpty && filteredEventCoins.length <= 1) {
        final (
          int totalCoins,
          int coinsWithKnownBalance,
          int coinsWithKnownBalanceAndFiat,
        ) = _calculateCoinProgressCounters(
          filteredEventCoins,
        );
        return emit(
          PortfolioGrowthChartUnsupported(
            selectedPeriod: event.selectedPeriod,
            totalCoins: totalCoins,
            coinsWithKnownBalance: coinsWithKnownBalance,
            coinsWithKnownBalanceAndFiat: coinsWithKnownBalanceAndFiat,
          ),
        );
      }

      await _loadChart(
        filteredEventCoins,
        event,
        useCache: true,
      ).then(emit.call).catchError((Object error, StackTrace stackTrace) {
        const errorMessage = 'Failed to load cached chart';
        _log.warning(errorMessage, error, stackTrace);
        // ignore cached errors, as the periodic refresh attempts should recover
        // at the cost of a longer first loading time.
      });

      // In case most coins are activating on wallet startup, wait for at least
      // 50% of the coins to be enabled before attempting to load the uncached
      // chart.
      await _sdk.waitForEnabledCoinsToPassThreshold(
        filteredEventCoins,
        delay: kActivationPollingInterval,
      );
      // Only remove inactivate/activating coins after an attempt to load the
      // cached chart, as the cached chart may contain inactive coins.
      await _loadChart(
        filteredEventCoins,
        event,
        useCache: false,
      ).then(emit.call).catchError((Object error, StackTrace stackTrace) {
        _log.shout('Failed to load chart', error, stackTrace);
        // Don't emit an error state here. If cached and uncached attempts
        // both fail, the periodic refresh attempts should recovery
        // at the cost of a longer first loading time.
      });
    } catch (error, stackTrace) {
      _log.shout('Failed to load portfolio growth', error, stackTrace);
      // Don't emit an error state here, as the periodic refresh attempts should
      // recover at the cost of a longer first loading time.
    }

    // Reset backoff strategy for new load request
    _backoffStrategy.reset();

    // Create periodic update stream with dynamic intervals
    await _runPeriodicUpdates(event, emit);
  }

  Future<PortfolioGrowthState> _loadChart(
    List<Coin> coins,
    PortfolioGrowthLoadRequested event, {
    required bool useCache,
  }) async {
    final chartCoins = useCache ? coins : await coins.removeInactiveCoins(_sdk);
    final chart = await _portfolioGrowthRepository.getPortfolioGrowthChart(
      chartCoins,
      fiatCoinId: event.fiatCoinId,
      walletId: event.walletId,
      useCache: useCache,
    );

    if (useCache && chart.isEmpty) {
      return state;
    }

    final totalBalance = coins.totalLastKnownUsdBalance(_sdk);
    final totalChange24h = await coins.totalChange24h(_sdk);
    final percentageChange24h = await coins.percentageChange24h(_sdk);

    final (
      int totalCoins,
      int coinsWithKnownBalance,
      int coinsWithKnownBalanceAndFiat,
    ) = _calculateCoinProgressCounters(
      coins,
    );

    return PortfolioGrowthChartLoadSuccess(
      portfolioGrowth: chart,
      percentageIncrease: chart.percentageIncrease,
      selectedPeriod: event.selectedPeriod,
      totalBalance: totalBalance,
      totalChange24h: totalChange24h.toDouble(),
      percentageChange24h: percentageChange24h.toDouble(),
      totalCoins: totalCoins,
      coinsWithKnownBalance: coinsWithKnownBalance,
      coinsWithKnownBalanceAndFiat: coinsWithKnownBalanceAndFiat,
      isUpdating: false,
    );
  }

  Future<(ChartData, List<Coin>)> _fetchPortfolioGrowthChart(
    PortfolioGrowthLoadRequested event,
  ) async {
    // Do not let transaction loading exceptions stop the periodic updates
    try {
      final supportedCoins = await event.coins.filterSupportedCoins(
        (coin) => _portfolioGrowthRepository.isCoinChartSupported(
          coin.id,
          event.fiatCoinId,
        ),
      );
      final coins = await supportedCoins.removeInactiveCoins(_sdk);
      final chart = await _portfolioGrowthRepository.getPortfolioGrowthChart(
        coins,
        fiatCoinId: event.fiatCoinId,
        walletId: event.walletId,
        useCache: false,
      );
      return (chart, coins);
    } catch (error, stackTrace) {
      _log.shout('Empty growth chart on periodic update', error, stackTrace);
      return (ChartData.empty(), <Coin>[]);
    }
  }

  Future<PortfolioGrowthState> _handlePortfolioGrowthUpdate(
    ChartData growthChart,
    Duration selectedPeriod,
    List<Coin> coins,
  ) async {
    if (growthChart.isEmpty && state is PortfolioGrowthChartLoadSuccess) {
      return state;
    }

    final percentageIncrease = growthChart.percentageIncrease;
    final totalBalance = coins.totalLastKnownUsdBalance(_sdk);
    final totalChange24h = await coins.totalChange24h(_sdk);
    final percentageChange24h = await coins.percentageChange24h(_sdk);

    final (
      int totalCoins,
      int coinsWithKnownBalance,
      int coinsWithKnownBalanceAndFiat,
    ) = _calculateCoinProgressCounters(
      coins,
    );

    return PortfolioGrowthChartLoadSuccess(
      portfolioGrowth: growthChart,
      percentageIncrease: percentageIncrease,
      selectedPeriod: selectedPeriod,
      totalBalance: totalBalance,
      totalChange24h: totalChange24h.toDouble(),
      percentageChange24h: percentageChange24h.toDouble(),
      totalCoins: totalCoins,
      coinsWithKnownBalance: coinsWithKnownBalance,
      coinsWithKnownBalanceAndFiat: coinsWithKnownBalanceAndFiat,
      isUpdating: false,
    );
  }

  /// Calculate progress counters for balances and fiat prices
  /// - totalCoins: total coins being considered (input list length)
  /// - coinsWithKnownBalance: number of coins with a known last balance
  /// - coinsWithKnownBalanceAndFiat: number of coins with a known last balance and known fiat price
  (int, int, int) _calculateCoinProgressCounters(List<Coin> coins) {
    int totalCoins = coins.length;
    int withBalance = 0;
    int withBalanceAndFiat = 0;
    for (final coin in coins) {
      final balanceKnown = _sdk.balances.lastKnown(coin.id) != null;
      if (balanceKnown) {
        withBalance++;
        final priceKnown = _sdk.marketData.priceIfKnown(coin.id) != null;
        if (priceKnown) {
          withBalanceAndFiat++;
        }
      }
    }
    return (totalCoins, withBalance, withBalanceAndFiat);
  }

  /// Run periodic updates with exponential backoff strategy
  Future<void> _runPeriodicUpdates(
    PortfolioGrowthLoadRequested event,
    Emitter<PortfolioGrowthState> emit,
  ) async {
    while (true) {
      if (isClosed || emit.isDone) {
        _log.fine('Stopping portfolio growth periodic updates: bloc closed.');
        break;
      }
      try {
        await Future.delayed(_backoffStrategy.getNextInterval());

        if (isClosed || emit.isDone) {
          _log.fine(
            'Skipping portfolio growth periodic update: bloc closed during delay.',
          );
          break;
        }

        final (chart, coins) = await _fetchPortfolioGrowthChart(event);
        emit(
          await _handlePortfolioGrowthUpdate(
            chart,
            event.selectedPeriod,
            coins,
          ),
        );
      } catch (error, stackTrace) {
        _log.shout('Failed to load portfolio growth', error, stackTrace);
        final (
          int totalCoins,
          int coinsWithKnownBalance,
          int coinsWithKnownBalanceAndFiat,
        ) = _calculateCoinProgressCounters(
          event.coins.withoutTestCoins(),
        );
        emit(
          GrowthChartLoadFailure(
            error: TextError(error: 'Failed to load portfolio growth'),
            selectedPeriod: event.selectedPeriod,
            totalCoins: totalCoins,
            coinsWithKnownBalance: coinsWithKnownBalance,
            coinsWithKnownBalanceAndFiat: coinsWithKnownBalanceAndFiat,
          ),
        );
      }
    }
  }
}
