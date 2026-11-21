import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_calculator.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/fiat_value.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/model/coin.dart';

class InvestmentRepository {
  InvestmentRepository({required ProfitLossRepository profitLossRepository})
    : _profitLossRepository = profitLossRepository;

  final ProfitLossRepository _profitLossRepository;
  final Logger _log = Logger('InvestmentRepository');

  // TODO: Create a balance repository to fetch the current balance for a coin
  // and also calculate its fiat value

  /// Calculates the total investment for all coins.
  /// [walletId] is the wallet ID associated with the profit/loss data.
  /// [coins] is the list of coins to calculate the investment for.
  ///
  /// Returns the [FiatValue] of the total investment.
  Future<FiatValue> calculateTotalInvestment(
    String walletId,
    List<Coin> coins,
  ) async {
    final fetchCoinProfitFutures = coins.map<Future<FiatValue>>((coin) async {
      // Catch errors that occur for single coins and exclude them from the
      // total so that transaction fetching errors for a single coin do not
      // affect the total investment calculation.
      try {
        final profitLoss = await _profitLossRepository.getProfitLoss(
          coin.id,
          'USDT',
          walletId,
        );

        if (profitLoss.isEmpty) {
          return FiatValue.usd(0);
        }

        final purchases = profitLoss.where((item) => item.myBalanceChange > 0);
        final totalPurchased = FiatValue.usd(
          purchases.fold(
            0.0,
            (sum, item) => sum + (item.myBalanceChange * item.fiatPrice.value),
          ),
        );

        return totalPurchased;
      } catch (e, s) {
        if (e is ProfitLossPriceUnavailable ||
            e is AuthSessionChangedException) {
          rethrow;
        }
        _log.shout('Failed to calculate total investment', e, s);
        return FiatValue.usd(0);
      }
    });

    final coinInvestments = await Future.wait(fetchCoinProfitFutures);

    final totalInvestment = coinInvestments.fold(
      0.0,
      (sum, item) => sum + item.value,
    );

    return FiatValue.usd(totalInvestment);
  }
}
