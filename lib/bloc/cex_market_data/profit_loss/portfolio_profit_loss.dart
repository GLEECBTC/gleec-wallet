import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';

/// The profit/loss of a set of coins, from one load.
///
/// Each coin is either valued, with an empty list when it has no
/// transactions, or unavailable. An unavailable coin is never counted as
/// zero: totals cover the valued coins and say how many were left out.
class PortfolioProfitLoss extends Equatable {
  const PortfolioProfitLoss({required this.valued, required this.unavailable});

  final Map<AssetId, List<ProfitLoss>> valued;

  /// Coins without a price, a readable history or a consistent one.
  final List<AssetId> unavailable;

  /// Whether none of the requested coins could be valued, which leaves
  /// nothing to total.
  bool get isUnavailable => valued.isEmpty && unavailable.isNotEmpty;

  List<String> get unavailableIds => [for (final id in unavailable) id.id];

  @override
  List<Object?> get props => [valued, unavailable];
}

final _log = Logger('PortfolioProfitLoss');

extension PortfolioProfitLossLoader on ProfitLossRepository {
  /// Loads every coin on its own, so that one coin that cannot be valued
  /// neither fails the others nor passes as zero.
  ///
  /// A [WalletChangedDisconnectException] still fails the load: the session
  /// ending, or its identity being unavailable, is about the wallet and not
  /// about any one coin.
  Future<PortfolioProfitLoss> getPortfolioProfitLoss(
    Iterable<AssetId> coinIds,
    String fiatCoinId,
    String walletId, {
    bool useCache = true,
  }) async {
    final ids = coinIds.toList();
    final results = await Future.wait(
      ids.map<Future<List<ProfitLoss>?>>((coinId) async {
        try {
          return await getProfitLoss(
            coinId,
            fiatCoinId,
            walletId,
            useCache: useCache,
          );
        } on WalletChangedDisconnectException {
          rethrow;
        } catch (error, stackTrace) {
          _log.warning(
            'Profit/loss unavailable for ${coinId.id}',
            error,
            stackTrace,
          );
          return null;
        }
      }),
    );

    final valued = <AssetId, List<ProfitLoss>>{};
    final unavailable = <AssetId>[];
    for (var i = 0; i < ids.length; i++) {
      final profitLosses = results[i];
      if (profitLosses == null) {
        unavailable.add(ids[i]);
      } else {
        valued[ids[i]] = profitLosses;
      }
    }
    return PortfolioProfitLoss(valued: valued, unavailable: unavailable);
  }
}
