import 'dart:async';
import 'dart:math' show Point;

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:collection/collection.dart' show ListEquality;
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AssetId, WalletChangedDisconnectException;
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/cex_market_data/charts.dart';
import 'package:web_dex/bloc/cex_market_data/common/update_frequency_backoff_strategy.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/portfolio_profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/model/coin.dart';

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
  int _loadGeneration = 0;
  ProfitLossPortfolioChartLoadRequested? _lastRequest;

  /// The request whose chart the current success state shows.
  ProfitLossPortfolioChartLoadRequested? _shownRequest;

  bool _ownsLoad(int generation, Emitter<ProfitLossState> emit) =>
      !isClosed && !emit.isDone && generation == _loadGeneration;

  void _onClearPortfolioProfitLoss(
    ProfitLossPortfolioChartClearRequested event,
    Emitter<ProfitLossState> emit,
  ) {
    _loadGeneration++;
    _lastRequest = null;
    _shownRequest = null;
    emit(const ProfitLossInitial());
  }

  Future<void> _onLoadPortfolioProfitLoss(
    ProfitLossPortfolioChartLoadRequested event,
    Emitter<ProfitLossState> emit,
  ) async {
    final generation = ++_loadGeneration;
    _lastRequest = event;
    try {
      final supportedCoins = await event.coins.filterSupportedCoins();
      final filteredEventCoins = event.coins.withoutTestCoins();
      final initialActiveCoins = await supportedCoins.removeInactiveCoins(_sdk);
      if (!_ownsLoad(generation, emit)) return;
      if (supportedCoins.isEmpty && filteredEventCoins.length <= 1) {
        _shownRequest = null;
        return emit(
          PortfolioProfitLossChartUnsupported(
            selectedPeriod: event.selectedPeriod,
          ),
        );
      }

      // Nothing is known about coins that are not active yet, so there is no
      // chart to show for them: not even an empty one.
      if (initialActiveCoins.isNotEmpty) {
        final cached = await _loadChart(
          event,
          initialActiveCoins,
          useCache: true,
        );
        if (!_ownsLoad(generation, emit)) return;
        _emitLoaded(cached, event, emit);
      }

      // Fetch the un-cached version of the chart to update the cache.
      if (supportedCoins.isNotEmpty) {
        await supportedCoins.waitForActivationThreshold(_sdk);
      }
      final activeCoins = await supportedCoins.removeInactiveCoins(_sdk);
      if (!_ownsLoad(generation, emit)) return;
      final refreshed = await _loadChart(event, activeCoins, useCache: false);
      if (!_ownsLoad(generation, emit)) return;
      _emitLoaded(refreshed, event, emit);
    } catch (error, stackTrace) {
      _log.shout('Failed to load portfolio profit/loss', error, stackTrace);
      // Don't emit an error state here, as the periodic refresh attempts should
      // recover at the cost of a longer first loading time.
    }

    if (!_ownsLoad(generation, emit)) return;

    // Reset backoff strategy for new load request
    _backoffStrategy.reset();

    // Create periodic update stream with dynamic intervals
    await _runPeriodicUpdates(event, emit, generation);
  }

  /// The state one load of [coins] leads to, or null when the session it was
  /// for has ended and its result belongs to nobody.
  ///
  /// Never throws, so that a failed load cannot stop the periodic updates.
  Future<ProfitLossState?> _loadChart(
    ProfitLossPortfolioChartLoadRequested event,
    List<Coin> coins, {
    required bool useCache,
  }) async {
    ProfitLossLoadFailure unavailable(ProfitLossUnavailableReason reason) =>
        ProfitLossLoadFailure(
          reason: reason,
          selectedPeriod: event.selectedPeriod,
        );

    if (coins.isEmpty) {
      _log.warning('No active coins to load profit/loss chart for');
      return unavailable(ProfitLossUnavailableReason.noActiveAssets);
    }

    try {
      final session = await _sdk.auth.captureSessionContext();
      final portfolio = await _profitLossRepository.getPortfolioProfitLoss(
        coins.map((coin) => coin.id),
        event.fiatCoinId,
        event.walletId,
        useCache: useCache,
      );
      _sdk.auth.ensureSessionContextCurrent(session);
      if (portfolio.isUnavailable) {
        return unavailable(ProfitLossUnavailableReason.noAssetValued);
      }

      final chart = _mergeCharts(portfolio);
      return PortfolioProfitLossChartLoadSuccess(
        profitLossChart: chart,
        totalValue: chart.increase,
        percentageIncrease: chart.percentageIncrease,
        coins: coins,
        excludedAssetIds: portfolio.unavailableIds,
        fiatCurrency: event.fiatCoinId,
        selectedPeriod: event.selectedPeriod,
        walletId: event.walletId,
      );
    } on AuthIdentityUnavailableException {
      _log.warning('Wallet identity unavailable for the profit/loss chart');
      return unavailable(ProfitLossUnavailableReason.walletIdentity);
    } on WalletChangedDisconnectException {
      _log.fine('Dropping the profit/loss chart of an ended session');
      return null;
    } catch (error, stackTrace) {
      _log.shout('Failed to load the profit/loss chart', error, stackTrace);
      return unavailable(ProfitLossUnavailableReason.loadFailed);
    }
  }

  /// Emits what a load of [request] found.
  ///
  /// A load that found nothing does not take a chart for the same portfolio
  /// off the screen: it was right when loaded, and the next refresh is what
  /// should replace it.
  void _emitLoaded(
    ProfitLossState? loaded,
    ProfitLossPortfolioChartLoadRequested request,
    Emitter<ProfitLossState> emit,
  ) {
    if (loaded == null) return;
    if (loaded is PortfolioProfitLossChartLoadSuccess) {
      _shownRequest = request;
      return emit(loaded);
    }

    final current = state;
    if (current is PortfolioProfitLossChartLoadSuccess &&
        _isSamePortfolio(_shownRequest, request)) {
      // The period change that started this load marked the chart as
      // updating; nothing else would clear that.
      if (current.isUpdating) emit(current.copyWith(isUpdating: false));
      return;
    }
    _shownRequest = null;
    emit(loaded);
  }

  static const _sameAssets = ListEquality<AssetId>();

  static bool _isSamePortfolio(
    ProfitLossPortfolioChartLoadRequested? shown,
    ProfitLossPortfolioChartLoadRequested request,
  ) =>
      shown != null &&
      shown.walletId == request.walletId &&
      shown.fiatCoinId == request.fiatCoinId &&
      _sameAssets.equals(
        [for (final coin in shown.coins) coin.id],
        [for (final coin in request.coins) coin.id],
      );

  Future<void> _onPortfolioPeriodChanged(
    ProfitLossPortfolioPeriodChanged event,
    Emitter<ProfitLossState> emit,
  ) async {
    _loadGeneration++;
    final eventState = state;
    emit(
      eventState is PortfolioProfitLossChartLoadSuccess
          ? eventState.copyWith(
              selectedPeriod: event.selectedPeriod,
              isUpdating: true,
            )
          : PortfolioProfitLossChartLoadInProgress(
              selectedPeriod: event.selectedPeriod,
            ),
    );

    // The request rather than the state's coins: the state only lists the
    // coins that were active when it loaded.
    final request = _lastRequest;
    if (request == null) return;
    add(
      ProfitLossPortfolioChartLoadRequested(
        coins: request.coins,
        fiatCoinId: request.fiatCoinId,
        selectedPeriod: event.selectedPeriod,
        walletId: request.walletId,
      ),
    );
  }

  /// One chart for the valued coins, each from its first non-zero entry on.
  ChartData _mergeCharts(PortfolioProfitLoss portfolio) {
    final charts = <ChartData>[];
    for (final MapEntry(key: coinId, value: profitLosses)
        in portfolio.valued.entries) {
      final firstNonZeroProfitLossIndex = profitLosses.indexWhere(
        (element) => element.profitLoss != 0,
      );
      if (firstNonZeroProfitLossIndex == -1) {
        _log.info('No non-zero profit/loss data found for ${coinId.id}');
        continue;
      }
      charts.add(
        profitLosses.sublist(firstNonZeroProfitLossIndex).toChartData(),
      );
    }
    return Charts.merge(charts)..sort((a, b) => a.x.compareTo(b.x));
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
    int generation,
  ) async {
    while (true) {
      if (!_ownsLoad(generation, emit)) {
        _log.fine('Stopping profit/loss periodic updates: bloc closed.');
        break;
      }
      if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'loop-start')) {
        break;
      }
      try {
        await Future.delayed(_backoffStrategy.getNextInterval());

        if (!_ownsLoad(generation, emit)) {
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
        if (!_ownsLoad(generation, emit)) break;
        if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'pre-fetch')) {
          break;
        }
        final updatedChartState = await _loadChart(
          event,
          activeCoins,
          useCache: false,
        );
        if (!_ownsLoad(generation, emit)) break;
        if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'pre-emit')) {
          break;
        }
        _emitLoaded(updatedChartState, event, emit);
      } catch (error, stackTrace) {
        if (!_ownsLoad(generation, emit)) break;
        if (_isStalePeriodicUpdate(event.selectedPeriod, stage: 'error')) {
          break;
        }
        _log.shout('Failed to load portfolio profit/loss', error, stackTrace);
        _emitLoaded(
          ProfitLossLoadFailure(
            reason: ProfitLossUnavailableReason.loadFailed,
            selectedPeriod: event.selectedPeriod,
          ),
          event,
          emit,
        );
      }
    }
  }
}
