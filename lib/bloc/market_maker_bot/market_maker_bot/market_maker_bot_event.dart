part of 'market_maker_bot_bloc.dart';

sealed class MarketMakerBotEvent extends Equatable {
  const MarketMakerBotEvent({this.botId = 0, this.walletSession});

  /// The ID of the current bot configuration.
  final int botId;
  final MarketMakerBotWalletSession? walletSession;

  @override
  List<Object?> get props => [botId, walletSession];
}

/// Event to start the market maker bot with the current settings obtained from
/// [SettingsRepository]. If the bot is already running, the event is ignored.
class MarketMakerBotStartRequested extends MarketMakerBotEvent {
  const MarketMakerBotStartRequested({
    required super.walletSession,
    required this.expectedTradePairs,
  });

  final List<TradeCoinPairConfig> expectedTradePairs;

  @override
  List<Object?> get props => [...super.props, expectedTradePairs];
}

/// Event to stop the market maker bot.
class MarketMakerBotStopRequested extends MarketMakerBotEvent {
  const MarketMakerBotStopRequested({
    required super.walletSession,
    this.allowSignedOut = false,
    this.allowObserverRecovery = false,
    this.signedOutOrigin,
    this.observerLossOrigin,
    this.pendingStartToken,
    this.expectedTradePairs,
    this.completion,
  });

  final bool allowSignedOut;
  final bool allowObserverRecovery;
  final MarketMakerBotWalletSession? signedOutOrigin;
  final MarketMakerBotWalletSession? observerLossOrigin;

  /// Limits an auth-rotation recovery stop to the still-pending start attempt
  /// that caused it. A rejected `AlreadyStarted` attempt clears this token, so
  /// a queued recovery can never stop the pre-existing bot.
  final Object? pendingStartToken;
  final List<TradeCoinPairConfig>? expectedTradePairs;
  final Completer<MarketMakerBotStopResult>? completion;

  void complete(MarketMakerBotStopResult result) {
    final completer = completion;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  @override
  List<Object?> get props => [
    ...super.props,
    allowSignedOut,
    allowObserverRecovery,
    signedOutOrigin,
    observerLossOrigin,
    pendingStartToken,
    expectedTradePairs,
    completion,
  ];
}

/// Event to update the market maker bot orders. All active orders are cancelled
/// and new orders are created based on the current market maker bot settings
/// obtained from [SettingsRepository].
class MarketMakerBotOrderUpdateRequested extends MarketMakerBotEvent {
  const MarketMakerBotOrderUpdateRequested(
    this.tradePair, {
    required super.walletSession,
    this.originalConfig,
  });

  final TradeCoinPairConfig tradePair;
  final TradeCoinPairConfig? originalConfig;

  @override
  List<Object?> get props => [...super.props, tradePair, originalConfig];
}

/// Event to cancel a market maker bot order. All active orders are cancelled
/// and new orders are created based on the current market maker bot settings
/// obtained from [SettingsRepository].
class MarketMakerBotOrderCancelRequested extends MarketMakerBotEvent {
  const MarketMakerBotOrderCancelRequested(
    this.tradePairs, {
    required super.walletSession,
    this.completion,
  });

  final Iterable<TradePair> tradePairs;
  final Completer<MarketMakerBotCancellationResult>? completion;

  void complete(MarketMakerBotCancellationResult result) {
    final completer = completion;
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  @override
  List<Object?> get props => [...super.props, tradePairs];
}

final class MarketMakerBotSessionChanged extends MarketMakerBotEvent {
  const MarketMakerBotSessionChanged();
}
