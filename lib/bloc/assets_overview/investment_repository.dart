import 'package:equatable/equatable.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/portfolio_profit_loss.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/model/coin.dart';

/// What a set of coins cost, with the profit/loss it was derived from.
///
/// Both come from one load, so the investment and the profit compared with it
/// describe the same coins: [PortfolioProfitLoss.unavailable] is in neither.
class PortfolioInvestment extends Equatable {
  const PortfolioInvestment({required this.profitLoss, required this.total});

  final PortfolioProfitLoss profitLoss;

  /// The cost of the valued coins' purchases.
  final FiatValue total;

  @override
  List<Object?> get props => [profitLoss, total];
}

class InvestmentRepository {
  InvestmentRepository({required ProfitLossRepository profitLossRepository})
    : _profitLossRepository = profitLossRepository;

  final ProfitLossRepository _profitLossRepository;

  // TODO: Create a balance repository to fetch the current balance for a coin
  // and also calculate its fiat value

  /// Calculates the total investment for all coins.
  /// [walletId] is the wallet ID associated with the profit/loss data.
  /// [coins] is the list of coins to calculate the investment for.
  ///
  /// A coin whose profit/loss cannot be computed is left out of the total
  /// and listed as unavailable; it is not counted as an investment of zero.
  Future<PortfolioInvestment> calculateTotalInvestment(
    String walletId,
    List<Coin> coins,
  ) async {
    final profitLoss = await _profitLossRepository.getPortfolioProfitLoss(
      coins.map((coin) => coin.id),
      'USDT',
      walletId,
    );
    return PortfolioInvestment(
      profitLoss: profitLoss,
      total: investmentOf(profitLoss.valued.values),
    );
  }

  /// The fiat cost of every purchase in [coinProfitLosses].
  FiatValue investmentOf(Iterable<List<ProfitLoss>> coinProfitLosses) {
    var total = 0.0;
    for (final profitLosses in coinProfitLosses) {
      for (final item in profitLosses) {
        if (item.myBalanceChange > 0) {
          total += item.myBalanceChange * item.fiatPrice.value;
        }
      }
    }
    return FiatValue.usd(total);
  }
}
