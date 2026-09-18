part of 'coins_bloc.dart';

sealed class CoinsEvent extends Equatable {
  const CoinsEvent();

  @override
  List<Object> get props => [];
}

/// Event emitted when the coins feature is started
final class CoinsStarted extends CoinsEvent {}

/// Event emitted when user requests to refresh their coin balances manually
final class CoinsBalancesRefreshed extends CoinsEvent {}

/// Event emitted when the bloc should start monitoring balances
final class CoinsBalanceMonitoringStarted extends CoinsEvent {}

/// Event emitted when the bloc should stop monitoring balances
final class CoinsBalanceMonitoringStopped extends CoinsEvent {}

/// Event emitted when user activates a coin for tracking
final class CoinsActivated extends CoinsEvent {
  const CoinsActivated(this.coinIds);

  final Iterable<String> coinIds;

  @override
  List<Object> get props => [coinIds];
}

/// Event emitted when user deactivates a coin from tracking
final class CoinsDeactivated extends CoinsEvent {
  const CoinsDeactivated(this.coinIds);

  final Iterable<String> coinIds;

  @override
  List<Object> get props => [coinIds];
}

final class CoinsPricesUpdated extends CoinsEvent {}

/// Emitted when a coin's balance has changed (real-time from SDK)
final class CoinsBalanceChanged extends CoinsEvent {
  const CoinsBalanceChanged(this.coin);

  final Coin coin;

  @override
  List<Object> get props => [coin];
}

/// Successful user login (session)
/// NOTE: has to be called from the UI layer for now, to ensure that wallet
/// metadata is saved to the current user. Auth state changes from the SDK
/// do not include updates to user metadata currently required for the GUI to
/// function properly.
final class CoinsSessionStarted extends CoinsEvent {
  const CoinsSessionStarted(this.signedInUser);

  final KdfUser signedInUser;

  @override
  List<Object> get props => [signedInUser];
}

/// User session ended (logout)
final class CoinsSessionEnded extends CoinsEvent {}

/// Suspended coins should be reactivated
final class CoinsSuspendedReactivated extends CoinsEvent {}

/// Re-drive the app-owned work that follows a coin becoming active.
///
/// Activation state is published by the SDK on a replayable stream, so it no
/// longer needs reconciling here. What still has no other retrigger is
/// everything downstream of activation: addresses whose fetch exhausted its
/// retry budget, and balance watchers that died. Both render as a row that
/// spins forever, so they share one repair path.
final class CoinsWalletRepairRequested extends CoinsEvent {}

/// Wallet coin is updated from the repository stream
/// Links [CoinsBloc] with [CoinsManagerBloc]
final class CoinsWalletCoinUpdated extends CoinsEvent {
  const CoinsWalletCoinUpdated(this.coin);

  final Coin coin;

  @override
  List<Object> get props => [coin];
}

// TODO! Refactor to remove this so that the pubkeys are loaded with the coins
class CoinsPubkeysRequested extends CoinsEvent {
  const CoinsPubkeysRequested(this.coinId);

  final String coinId;

  @override
  List<Object> get props => [coinId];
}

/// Internal completion of an activation whose wallet could not be verified.
final class _CoinsActivationCancelled extends CoinsEvent {
  const _CoinsActivationCancelled({
    required this.coinIds,
    required this.generation,
  });

  final Set<String> coinIds;
  final int generation;

  @override
  List<Object> get props => [coinIds, generation];
}
