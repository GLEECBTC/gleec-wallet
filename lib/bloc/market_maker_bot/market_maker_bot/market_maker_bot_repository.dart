import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_method.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_status.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_parameters.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/rpc_error.dart';
import 'package:web_dex/mm2/mm2_api/rpc/rpc_error_type.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';
import 'package:web_dex/shared/utils/utils.dart';

class MarketMakerBotRepository {
  MarketMakerBotRepository(this._mm2Api, this._settingsRepository);

  /// The MM2 RPC API provider used to start/stop the market maker bot.
  final Mm2Api _mm2Api;

  /// The settings repository used to read/fetch the market maker bot settings.
  /// This BLoC does not write to the settings repository.
  final SettingsRepository _settingsRepository;

  /// Starts the market maker bot with the given parameters.
  /// Throws an [ArgumentError] if the request fails.
  Future<void> start({
    required int botId,
    int retries = 10,
    Duration delay = const Duration(milliseconds: 2000),
  }) async {
    final requestParams = await loadStoredConfig();
    final request = MarketMakerBotRequest(
      id: botId,
      method: MarketMakerBotMethod.start.value,
      params: requestParams,
    );

    if (requestParams.tradeCoinPairs?.isEmpty ?? true) {
      throw ArgumentError('No trade pairs configured');
    }
    _assertTradePairsAllowed(requestParams.tradeCoinPairs!.values);

    await _startStopBotWithExponentialBackoff(
      request,
      retries: retries,
      delay: delay,
    );
  }

  /// Stops the market maker bot with the given ID.
  /// Throws an [Exception] if the request fails.
  Future<void> stop({
    required int botId,
    int retries = 10,
    Duration delay = const Duration(milliseconds: 2000),
  }) async {
    try {
      final MarketMakerBotRequest request = MarketMakerBotRequest(
        id: botId,
        method: MarketMakerBotMethod.stop.value,
      );
      await _startStopBotWithExponentialBackoff(
        request,
        retries: retries,
        delay: delay,
      );
    } catch (e) {
      if (e is RpcException &&
          (e.error.errorType == RpcErrorType.alreadyStopped ||
              e.error.errorType == RpcErrorType.alreadyStopping)) {
        return;
      }
      rethrow;
    }
  }

  /// Updates the market maker bot with the given parameters.
  /// Throws an [Exception] if the request fails.
  Stream<MarketMakerBotStatus> updateOrder(
    TradeCoinPairConfig tradePair, {
    required int botId,
    int retries = 10,
    Duration delay = const Duration(milliseconds: 2000),
  }) async* {
    yield MarketMakerBotStatus.stopping;
    await stop(botId: botId, retries: retries, delay: delay);
    // This would be correct, if the bot stopped completely before responding
    // to the stop request
    // yield MarketMakerBotStatus.stopped;

    final requestParams = await loadStoredConfig();
    _assertTradePairAllowed(tradePair);
    if (requestParams.tradeCoinPairs?.containsKey(tradePair.name) == false) {
      requestParams.tradeCoinPairs?.addEntries([
        MapEntry(tradePair.name, tradePair),
      ]);
    }

    if (requestParams.tradeCoinPairs?.isEmpty ?? true) {
      yield MarketMakerBotStatus.stopped;
    } else {
      _assertTradePairsAllowed(requestParams.tradeCoinPairs!.values);
      yield MarketMakerBotStatus.starting;
      final request = MarketMakerBotRequest(
        id: botId,
        method: MarketMakerBotMethod.start.value,
        params: requestParams,
      );
      await _startStopBotWithExponentialBackoff(
        request,
        retries: retries,
        delay: delay,
      );
      yield MarketMakerBotStatus.running;
    }
  }

  /// Cancels the market maker bot order with the given parameters.
  /// Throws an [Exception] if the request fails.
  Stream<MarketMakerBotStatus> cancelOrders(
    Iterable<TradeCoinPairConfig> tradeCoinPairConfig, {
    required int botId,
    int retries = 10,
    Duration delay = const Duration(milliseconds: 2000),
  }) async* {
    yield MarketMakerBotStatus.stopping;
    await stop(botId: botId, retries: retries, delay: delay);
    // This would be correct, if the bot stopped completely before responding
    // to the stop request
    // yield MarketMakerBotStatus.stopped;

    final requestParams = await loadStoredConfig();
    for (final tradePair in tradeCoinPairConfig) {
      requestParams.tradeCoinPairs?.remove(tradePair.name);
    }

    if (requestParams.tradeCoinPairs?.isEmpty ?? true) {
      yield MarketMakerBotStatus.stopped;
    } else {
      _assertTradePairsAllowed(requestParams.tradeCoinPairs!.values);
      // yield MarketMakerBotStatus.starting;
      final request = MarketMakerBotRequest(
        id: botId,
        method: MarketMakerBotMethod.start.value,
        params: requestParams,
      );
      await _startStopBotWithExponentialBackoff(
        request,
        retries: retries,
        delay: delay,
      );
      yield MarketMakerBotStatus.running;
    }
  }

  /// Loads the market maker bot parameters from the settings repository.
  /// The parameters are used to start the market maker bot.
  Future<MarketMakerBotParameters> loadStoredConfig() async {
    final settings = await _settingsRepository.loadSettings();
    final mmSettings = settings.marketMakerBotSettings;
    final tradePairs = {
      for (final tradePair in mmSettings.tradeCoinPairConfigs)
        tradePair.name: tradePair,
    };
    return MarketMakerBotParameters(
      botRefreshRate: mmSettings.botRefreshRate,
      tradeCoinPairs: tradePairs,
    );
  }

  /// Starts the market maker bot with the given parameters. Retries the request
  /// if it fails. The number of retries and the initial delay between retries
  /// can be configured. The delay between retries is doubled after each retry.
  /// Throws an [Exception] if the request fails after all retries.
  Future<void> _startStopBotWithExponentialBackoff(
    MarketMakerBotRequest request, {
    required int retries,
    required Duration delay,
  }) async {
    final isStartRequest = request.method == MarketMakerBotMethod.start.value;
    final isTradePairsEmpty = request.params?.tradeCoinPairs?.isEmpty ?? true;
    if (isStartRequest && isTradePairsEmpty) {
      throw ArgumentError('No trade pairs configured');
    }

    while (retries > 0) {
      try {
        await _mm2Api.startStopMarketMakerBot(request);
        break;
      } catch (e, s) {
        if (retries <= 0) {
          rethrow;
        }

        if (e is RpcException) {
          if (request.method == MarketMakerBotMethod.start.value &&
              e.error.errorType == RpcErrorType.alreadyStarted) {
            log('Market maker bot already started', isError: true).ignore();
            return;
          } else if (request.method == MarketMakerBotMethod.stop.value &&
                  e.error.errorType == RpcErrorType.alreadyStopped ||
              e.error.errorType == RpcErrorType.alreadyStopping) {
            log('Market maker bot already stopped', isError: true).ignore();
            return;
          }
        }

        log(
          'Failed to start market maker bot. Retrying in $delay ms',
          isError: true,
          trace: s,
          path: 'MarketMakerBotBloc',
        ).ignore();
        await Future<void>.delayed(delay);
        retries--;
        delay *= 2;
      }
    }
  }

  /// Adds the given trade pair to the stored market maker bot settings.
  /// The settings are updated in the settings repository.
  /// Throws an [Exception] if the settings cannot be updated.
  ///
  /// The [tradePair] to added to the existing settings.
  Future<void> addTradePairToStoredSettings(
    TradeCoinPairConfig tradePair,
  ) async {
    _assertTradePairAllowed(tradePair);
    final allSettings = await _settingsRepository.loadSettings();
    final settings = allSettings.marketMakerBotSettings;
    final tradePairs = List<TradeCoinPairConfig>.from(
      settings.tradeCoinPairConfigs,
    );

    // remove any existing pairs
    tradePairs.removeWhere(
      (element) =>
          element.baseCoinId == tradePair.baseCoinId &&
          element.relCoinId == tradePair.relCoinId,
    );

    tradePairs.add(tradePair);
    final newSettings = settings.copyWith(tradeCoinPairConfigs: tradePairs);
    await _settingsRepository.updateSettings(
      allSettings.copyWith(marketMakerBotSettings: newSettings),
    );
  }

  void _assertTradePairsAllowed(Iterable<TradeCoinPairConfig> tradePairs) {
    for (final tradePair in tradePairs.where((pair) => pair.enable)) {
      _assertTradePairAllowed(tradePair);
    }
  }

  void _assertTradePairAllowed(TradeCoinPairConfig tradePair) {
    if (!canTradeAssetPair(tradePair.baseCoinId, tradePair.relCoinId)) {
      throw ArgumentError(
        'Wallet-only assets cannot be used by the market maker bot.',
      );
    }
  }

  /// Removes the given trade pair from the stored market maker bot settings.
  /// The settings are updated in the settings repository.
  /// Throws an [Exception] if the settings cannot be updated.
  ///
  /// The [tradePairsToRemove] to remove from the existing settings.
  Future<void> removeTradePairsFromStoredSettings(
    List<TradeCoinPairConfig> tradePairsToRemove,
  ) async {
    final allSettings = await _settingsRepository.loadSettings();
    final settings = allSettings.marketMakerBotSettings;
    final tradePairs = List<TradeCoinPairConfig>.from(
      settings.tradeCoinPairConfigs,
    );

    for (final pair in tradePairsToRemove) {
      tradePairs.removeWhere((e) => e.name == pair.name);
    }
    final newSettings = settings.copyWith(tradeCoinPairConfigs: tradePairs);
    await _settingsRepository.updateSettings(
      allSettings.copyWith(marketMakerBotSettings: newSettings),
    );
  }
}
