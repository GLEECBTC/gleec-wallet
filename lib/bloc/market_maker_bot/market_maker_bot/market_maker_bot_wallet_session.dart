import 'package:equatable/equatable.dart';

/// A bot mutation was authorised against a wallet that is no longer live.
final class MarketMakerBotWalletChanged implements Exception {
  const MarketMakerBotWalletChanged();
}

/// Immutable identity for one authenticated wallet session.
///
/// The generation distinguishes a re-authenticated session even when it uses
/// the same wallet ID. Bot operations capture this value up front and carry it
/// through to every mutation instead of using whichever wallet happens to be
/// current when a long-running cancellation loop eventually reaches an order.
final class MarketMakerBotWalletSession extends Equatable {
  const MarketMakerBotWalletSession({
    required this.walletId,
    required this.generation,
  });

  final String walletId;
  final int generation;

  @override
  List<Object> get props => [walletId, generation];
}
