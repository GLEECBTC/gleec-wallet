part of 'market_maker_bot_bloc.dart';

/// Represents the state of the market maker bot.
final class MarketMakerBotState extends Equatable {
  /// Whether the bot is starting, stopping, running or stopped.
  final MarketMakerBotStatus status;

  /// The error message if the bot failed to start or stop.
  /// TODO: change to enum error type.
  final String? errorMessage;

  /// Whether this app session has authoritatively confirmed that the bot is
  /// stopped and all of its tracked orders are absent.
  ///
  /// A visually stopped initial state is not proof that no external or prior
  /// bot instance is running, so config mutations must gate on this value.
  final bool lifecycleProvenStopped;

  const MarketMakerBotState({
    required this.status,
    this.errorMessage,
    this.lifecycleProvenStopped = false,
  });

  /// The initial state of the bot. Defaults [status] to stopped
  /// and [errorMessage] to null.
  const MarketMakerBotState.initial()
    : this(status: MarketMakerBotStatus.stopped);

  /// The bot is starting. Defaults [status] to starting
  /// and [errorMessage] to null.
  const MarketMakerBotState.starting()
    : this(status: MarketMakerBotStatus.starting);

  /// The bot is stopping. Defaults [status] to stopping
  /// and [errorMessage] to null.
  const MarketMakerBotState.stopping()
    : this(status: MarketMakerBotStatus.stopping);

  /// The bot is running. Defaults [status] to running
  /// and [errorMessage] to null.
  const MarketMakerBotState.running()
    : this(status: MarketMakerBotStatus.running);

  /// The bot is stopped. Defaults [status] to stopped
  /// and [errorMessage] to null.
  const MarketMakerBotState.stopped()
    : this(status: MarketMakerBotStatus.stopped, lifecycleProvenStopped: true);

  bool get isRunning => status == MarketMakerBotStatus.running;
  bool get isUpdating =>
      status == MarketMakerBotStatus.starting ||
      status == MarketMakerBotStatus.stopping;

  MarketMakerBotState copyWith({
    MarketMakerBotStatus? status,
    String? error,
    bool? lifecycleProvenStopped,
  }) {
    return MarketMakerBotState(
      status: status ?? this.status,
      errorMessage: error,
      lifecycleProvenStopped:
          lifecycleProvenStopped ?? this.lifecycleProvenStopped,
    );
  }

  @override
  List<Object?> get props => [status, errorMessage, lifecycleProvenStopped];
}
