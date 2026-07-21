import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_method.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_parameters.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/market_maker_bot_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/rpc_error.dart';
import 'package:web_dex/mm2/mm2_api/rpc/rpc_error_type.dart';
import 'package:web_dex/shared/utils/utils.dart';

enum MarketMakerBotStopRpcOutcome { accepted, alreadyStopped, alreadyStopping }

/// KDF rejected a start because a bot with this ID was already running.
///
/// Callers must not treat this as an accepted start: the existing bot may have
/// been started outside this app lifecycle and must never be auto-stopped as a
/// rollback side effect.
final class MarketMakerBotAlreadyStarted implements Exception {
  const MarketMakerBotAlreadyStarted();
}

/// KDF authoritatively rejected a start request before it could be accepted.
/// This is not a transport-uncertain outcome and must never trigger rollback.
final class MarketMakerBotStartRejected implements Exception {
  const MarketMakerBotStartRejected();
}

/// A start request may have reached KDF, but no authoritative response arrived.
/// It must not be retried or automatically rolled back without protocol-owned
/// idempotency/ownership evidence.
final class MarketMakerBotStartUncertain implements Exception {
  const MarketMakerBotStartUncertain();
}

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
    required MarketMakerBotParameters parameters,
    int retries = 6,
    Duration delay = const Duration(seconds: 1),
    bool allowAlreadyStarted = true,
    Future<void> Function()? beforeMutation,
    Duration rpcAttemptTimeout = const Duration(seconds: 15),
  }) async {
    final request = MarketMakerBotRequest(
      id: botId,
      method: MarketMakerBotMethod.start.value,
      params: parameters,
    );

    if (parameters.tradeCoinPairs?.isEmpty ?? true) {
      throw ArgumentError('No trade pairs configured');
    }

    await _startStopBotWithExponentialBackoff(
      request,
      retries: retries,
      delay: delay,
      allowAlreadyStarted: allowAlreadyStarted,
      beforeMutation: beforeMutation,
      rpcAttemptTimeout: rpcAttemptTimeout,
    );
  }

  /// Stops the market maker bot with the given ID.
  /// Throws an [Exception] if the request fails.
  Future<MarketMakerBotStopRpcOutcome> stop({
    required int botId,
    int retries = 3,
    Duration delay = const Duration(seconds: 1),
    Future<void> Function()? beforeMutation,
    Duration rpcAttemptTimeout = const Duration(seconds: 15),
  }) async {
    final MarketMakerBotRequest request = MarketMakerBotRequest(
      id: botId,
      method: MarketMakerBotMethod.stop.value,
    );
    final knownOutcome = await _startStopBotWithExponentialBackoff(
      request,
      retries: retries,
      delay: delay,
      allowAlreadyStarted: true,
      beforeMutation: beforeMutation,
      rpcAttemptTimeout: rpcAttemptTimeout,
    );
    return switch (knownOutcome) {
      RpcErrorType.alreadyStopped =>
        MarketMakerBotStopRpcOutcome.alreadyStopped,
      RpcErrorType.alreadyStopping =>
        MarketMakerBotStopRpcOutcome.alreadyStopping,
      _ => MarketMakerBotStopRpcOutcome.accepted,
    };
  }

  /// Loads the market maker bot parameters from the settings repository.
  /// The parameters are used to start the market maker bot.
  Future<MarketMakerBotParameters> loadStoredConfig() async {
    final settings = await _settingsRepository.loadSettingsStrict();
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
  Future<RpcErrorType?> _startStopBotWithExponentialBackoff(
    MarketMakerBotRequest request, {
    required int retries,
    required Duration delay,
    required bool allowAlreadyStarted,
    required Future<void> Function()? beforeMutation,
    required Duration rpcAttemptTimeout,
  }) async {
    final isStartRequest = request.method == MarketMakerBotMethod.start.value;
    final isTradePairsEmpty = request.params?.tradeCoinPairs?.isEmpty ?? true;
    if (isStartRequest && isTradePairsEmpty) {
      throw ArgumentError('No trade pairs configured');
    }
    if (retries <= 0) {
      throw ArgumentError.value(retries, 'retries', 'Must be positive');
    }
    if (rpcAttemptTimeout <= Duration.zero ||
        rpcAttemptTimeout > const Duration(minutes: 1)) {
      throw ArgumentError.value(
        rpcAttemptTimeout,
        'rpcAttemptTimeout',
        'Must be between zero and one minute',
      );
    }

    for (var attempt = 1; attempt <= retries; attempt++) {
      try {
        await (() async {
          await beforeMutation?.call();
          await _mm2Api.startStopMarketMakerBot(request);
        })().timeout(rpcAttemptTimeout);
        return null;
      } catch (e, s) {
        if (e is RpcException) {
          if (request.method == MarketMakerBotMethod.start.value &&
              e.error.errorType == RpcErrorType.alreadyStarted) {
            if (!allowAlreadyStarted) {
              throw const MarketMakerBotAlreadyStarted();
            }
            log('Market maker bot already started', isError: true).ignore();
            return RpcErrorType.alreadyStarted;
          } else if (request.method == MarketMakerBotMethod.start.value) {
            // A structured RPC error is an authoritative rejection, not a
            // lost response. Retrying could adopt a bot started by another
            // actor between attempts and must therefore fail immediately.
            throw const MarketMakerBotStartRejected();
          } else if (request.method == MarketMakerBotMethod.stop.value &&
              (e.error.errorType == RpcErrorType.alreadyStopped ||
                  e.error.errorType == RpcErrorType.alreadyStopping)) {
            log(
              'Market maker bot stop is already settled or settling',
            ).ignore();
            return e.error.errorType;
          }
        }

        if (isStartRequest) {
          // Retrying an ambiguous start can adopt a bot created by another
          // controller between attempts. Leave reconciliation to an explicit
          // user-confirmed Stop until KDF returns owner/idempotency metadata.
          throw const MarketMakerBotStartUncertain();
        }

        if (attempt == retries) rethrow;

        log(
          'Market maker bot request failed; retrying',
          isError: true,
          trace: s,
          path: 'MarketMakerBotBloc',
        ).ignore();
        await Future<void>.delayed(delay);
        delay *= 2;
        if (delay > const Duration(seconds: 8)) {
          delay = const Duration(seconds: 8);
        }
      }
    }
    throw StateError('Unreachable market maker bot retry state');
  }

  /// Adds the given trade pair to the stored market maker bot settings.
  /// The settings are updated in the settings repository.
  /// Throws an [Exception] if the settings cannot be updated.
  ///
  /// The [tradePair] to added to the existing settings.
  Future<void> addTradePairToStoredSettings(
    TradeCoinPairConfig tradePair, {
    Future<void> Function()? beforeMutation,
  }) async {
    await _settingsRepository.updateSettingsWith((allSettings) {
      final settings = allSettings.marketMakerBotSettings;
      final tradePairs =
          List<TradeCoinPairConfig>.from(settings.tradeCoinPairConfigs)
            ..removeWhere(
              (element) =>
                  element.baseCoinId == tradePair.baseCoinId &&
                  element.relCoinId == tradePair.relCoinId,
            );
      tradePairs.add(tradePair);
      return allSettings.copyWith(
        marketMakerBotSettings: settings.copyWith(
          tradeCoinPairConfigs: tradePairs,
        ),
      );
    }, beforeWrite: beforeMutation);
  }

  /// Removes the given trade pair from the stored market maker bot settings.
  /// The settings are updated in the settings repository.
  /// Throws an [Exception] if the settings cannot be updated.
  ///
  /// The [tradePairsToRemove] to remove from the existing settings.
  Future<void> removeTradePairsFromStoredSettings(
    List<TradeCoinPairConfig> tradePairsToRemove, {
    Future<void> Function()? beforeMutation,
  }) async {
    final namesToRemove = tradePairsToRemove.map((pair) => pair.name).toSet();
    await _settingsRepository.updateSettingsWith((allSettings) {
      final settings = allSettings.marketMakerBotSettings;
      final tradePairs = List<TradeCoinPairConfig>.from(
        settings.tradeCoinPairConfigs,
      )..removeWhere((pair) => namesToRemove.contains(pair.name));
      return allSettings.copyWith(
        marketMakerBotSettings: settings.copyWith(
          tradeCoinPairConfigs: tradePairs,
        ),
      );
    }, beforeWrite: beforeMutation);
  }
}
