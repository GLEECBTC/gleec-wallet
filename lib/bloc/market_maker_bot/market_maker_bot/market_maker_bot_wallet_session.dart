import 'package:equatable/equatable.dart';

/// Immutable identity for one authenticated wallet session.
///
/// The generation distinguishes a re-authenticated session even when it uses
/// the same wallet ID. UI snapshots must carry this value through to every
/// bot mutation instead of capturing whichever wallet happens to be current
/// when the user eventually confirms an action.
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
