import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/extensions/profit_loss_transaction_extension.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/price_stamped_transaction.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';

class ProfitLossCalculator {
  ProfitLossCalculator(this._sdk);

  final KomodoDefiSdk _sdk;

  /// Get the running profit/loss for a coin based on the transactions.
  /// ProfitLoss = Proceeds - CostBasis
  /// CostBasis = Sum of the fiat price of the coin amount received (bought)
  /// Proceeds = Sum of the fiat price of the coin amount spent (sold)
  ///
  /// [transactions] is the list of transactions.
  /// [coinId] is the id of the coin, generally the coin ticker. Eg: 'BTC'.
  /// [fiatCoinId] is id of the fiat currency tether to convert the [coinId] to.
  /// E.g. 'USDT'. This can be any supported coin id, but the idea is to convert
  /// the coin to a fiat currency to calculate the profit/loss in fiat.
  ///
  /// Returns the list of [ProfitLoss] for the coin.
  Future<List<ProfitLoss>> getProfitFromTransactions(
    List<Transaction> transactions, {
    required AssetId coinId,
    required String fiatCoinId,
  }) async {
    if (transactions.isEmpty) {
      return <ProfitLoss>[];
    }

    final orderedTransactions = List<Transaction>.of(transactions)
      ..sort(_compareChronologically);

    final todayAtMidnight = _getDateAtMidnight(DateTime.now());
    final transactionDates = _getTransactionDates(orderedTransactions);
    final coinUsdPrices = await _sdk.marketData.fiatPriceHistory(
      coinId,
      transactionDates,
    );
    if (coinUsdPrices.isEmpty) {
      throw ProfitLossPriceUnavailable(
        coinId.id,
        _getDateAtMidnight(orderedTransactions.first.timestamp),
      );
    }
    final latestDate = coinUsdPrices.keys.reduce(
      (a, b) => a.isAfter(b) ? a : b,
    );
    final currentPrice =
        coinUsdPrices[todayAtMidnight] ?? coinUsdPrices[latestDate]!;
    final priceStampedTransactions = _priceStampTransactions(
      orderedTransactions,
      coinUsdPrices,
      coinId,
    );

    return _calculateProfitLosses(priceStampedTransactions, currentPrice);
  }

  /// Transactions in one block share its timestamp, and `List.sort` is not
  /// stable. Counting what came in first keeps a receive ahead of the spend
  /// that consumes it; block height and id then make the order reproducible.
  static int _compareChronologically(Transaction a, Transaction b) {
    final byTime = a.timestamp.compareTo(b.timestamp);
    if (byTime != 0) return byTime;
    final byDirection = b.amount.sign.compareTo(a.amount.sign);
    if (byDirection != 0) return byDirection;
    final byBlock = a.blockHeight.compareTo(b.blockHeight);
    if (byBlock != 0) return byBlock;
    return a.internalId.compareTo(b.internalId);
  }

  /// Missing acquisition or sale prices make the entire result unavailable.
  /// Keep the transaction inventory intact; substituting another day's price
  /// would publish an invented cost basis as ordinary realized profit/loss.
  List<UsdPriceStampedTransaction> _priceStampTransactions(
    List<Transaction> transactions,
    Map<DateTime, Decimal> prices,
    AssetId coinId,
  ) {
    return transactions.map((transaction) {
      final date = _getDateAtMidnight(transaction.timestamp);
      final price = prices[date];
      if (price == null) {
        throw ProfitLossPriceUnavailable(coinId.id, date);
      }
      return UsdPriceStampedTransaction(transaction, price.toDouble());
    }).toList();
  }

  /// UTC, so each date reaches the price history as the day
  /// [_getDateAtMidnight] looks up.
  List<DateTime> _getTransactionDates(List<Transaction> transactions) {
    return [
      for (final tx in transactions) tx.timestamp.toUtc(),
      DateTime.now().toUtc(),
    ];
  }

  DateTime _getDateAtMidnight(DateTime date) {
    final utcDate = date.toUtc();
    return DateTime.utc(utcDate.year, utcDate.month, utcDate.day);
  }

  List<ProfitLoss> _calculateProfitLosses(
    List<UsdPriceStampedTransaction> transactions,
    Decimal currentPrice,
  ) {
    var state = _ProfitLossState();
    final profitLosses = <ProfitLoss>[];

    for (final transaction in transactions) {
      if (transaction.totalAmountAsDouble == 0) continue;

      if (transaction.amount > Decimal.zero) {
        state = _processBuyTransaction(state, transaction);
      } else {
        state = _processSellTransaction(state, transaction);
      }

      final runningProfitLoss = _calculateProfitLoss(state, currentPrice);
      profitLosses.add(
        ProfitLoss.fromTransaction(
          transaction,
          transaction.fiatValue,
          runningProfitLoss,
        ),
      );
    }

    return profitLosses;
  }

  _ProfitLossState _processBuyTransaction(
    _ProfitLossState state,
    UsdPriceStampedTransaction transaction,
  ) {
    final newHolding = (
      holdings: transaction.amount,
      price: transaction.priceUsd,
    );
    return _ProfitLossState(
      holdings: [...state.holdings, newHolding],
      realizedProfitLoss: state.realizedProfitLoss,
      totalInvestment: state.totalInvestment + transaction.balanceChangeUsd,
      currentHoldings: state.currentHoldings + transaction.amount,
    );
  }

  _ProfitLossState _processSellTransaction(
    _ProfitLossState state,
    UsdPriceStampedTransaction transaction,
  ) {
    if (state.currentHoldings < transaction.amount.abs()) {
      throw Exception('Attempting to sell more than currently held');
    }

    // Balance change is negative for sales, so we use the abs value to
    // calculate the cost basis (formula assumes positive "total" value).
    var remainingToSell = transaction.amount.abs();
    var costBasis = 0.0;
    final newHoldings = List<({Decimal holdings, double price})>.from(
      state.holdings,
    );

    while (remainingToSell > Decimal.zero) {
      final oldestBuy = newHoldings.first;
      if (oldestBuy.holdings <= remainingToSell) {
        newHoldings.removeAt(0);
        costBasis += oldestBuy.holdings.toDouble() * oldestBuy.price;
        remainingToSell -= oldestBuy.holdings;
      } else {
        newHoldings[0] = (
          holdings: newHoldings[0].holdings - remainingToSell,
          price: newHoldings[0].price,
        );
        costBasis += remainingToSell.toDouble() * oldestBuy.price;
        remainingToSell = Decimal.zero;
      }
    }

    final double saleProceeds = transaction.balanceChangeUsd.abs();
    final double newRealizedProfitLoss =
        state.realizedProfitLoss + (saleProceeds - costBasis);

    // Balance change is negative for a sale, so subtract the abs value (
    // or add the positive value) to get the new holdings.
    final newCurrentHoldings = state.currentHoldings - transaction.amount.abs();
    final double newTotalInvestment = state.totalInvestment - costBasis;

    return _ProfitLossState(
      holdings: newHoldings,
      realizedProfitLoss: newRealizedProfitLoss,
      totalInvestment: newTotalInvestment,
      currentHoldings: newCurrentHoldings,
    );
  }

  double _calculateProfitLoss(_ProfitLossState state, Decimal currentPrice) {
    final currentValue =
        state.currentHoldings.toDouble() * currentPrice.toDouble();
    final unrealizedProfitLoss = currentValue - state.totalInvestment;
    return state.realizedProfitLoss + unrealizedProfitLoss;
  }
}

class RealisedProfitLossCalculator extends ProfitLossCalculator {
  RealisedProfitLossCalculator(super._sdk);

  @override
  double _calculateProfitLoss(_ProfitLossState state, Decimal currentPrice) {
    return state.realizedProfitLoss;
  }
}

class UnRealisedProfitLossCalculator extends ProfitLossCalculator {
  UnRealisedProfitLossCalculator(super._sdk);

  @override
  double _calculateProfitLoss(_ProfitLossState state, Decimal currentPrice) {
    final currentValue =
        state.currentHoldings.toDouble() * currentPrice.toDouble();
    final unrealizedProfitLoss = currentValue - state.totalInvestment;
    return unrealizedProfitLoss;
  }
}

class _ProfitLossState {
  _ProfitLossState({
    List<({Decimal holdings, double price})>? holdings,
    this.realizedProfitLoss = 0.0,
    this.totalInvestment = 0.0,
    Decimal? currentHoldings,
  }) : holdings = holdings ?? [],
       currentHoldings = currentHoldings ?? Decimal.zero;
  final List<({Decimal holdings, double price})> holdings;
  final double realizedProfitLoss;
  final double totalInvestment;
  final Decimal currentHoldings;
}

/// No defensible realized result exists without the transaction day's price.
class ProfitLossPriceUnavailable implements Exception {
  const ProfitLossPriceUnavailable(this.coinId, this.date);

  final String coinId;
  final DateTime date;

  @override
  String toString() => 'USD price unavailable for $coinId on $date';
}
