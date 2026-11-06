import 'package:collection/collection.dart' show lowerBound;
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/extensions/profit_loss_transaction_extension.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/price_stamped_transaction.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/models/profit_loss.dart';

class ProfitLossCalculator {
  ProfitLossCalculator(this._sdk);

  final KomodoDefiSdk _sdk;
  final Logger _log = Logger('ProfitLossCalculator');

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

    transactions.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final todayAtMidnight = _getDateAtMidnight(DateTime.now());
    final transactionDates = _getTransactionDates(transactions);
    final coinUsdPrices = await _sdk.marketData.fiatPriceHistory(
      coinId,
      transactionDates,
    );
    if (coinUsdPrices.isEmpty) {
      throw Exception('No USD price history for ${coinId.id}');
    }
    final prices = _NearestPrices(coinUsdPrices);
    final currentPrice = coinUsdPrices[todayAtMidnight] ?? prices.latest;
    final priceStampedTransactions = _priceStampTransactions(
      transactions,
      prices,
      coinId,
    );

    return _calculateProfitLosses(priceStampedTransactions, currentPrice);
  }

  /// A date without a price, such as one older than the price source's
  /// history, takes the nearest known price. Skipping its transaction instead
  /// would leave later sales selling coins that were never bought.
  List<UsdPriceStampedTransaction> _priceStampTransactions(
    List<Transaction> transactions,
    _NearestPrices prices,
    AssetId coinId,
  ) {
    var approximated = 0;
    final stamped = <UsdPriceStampedTransaction>[];
    for (final transaction in transactions) {
      final date = _getDateAtMidnight(transaction.timestamp);
      var usdPrice = prices.exact(date);
      if (usdPrice == null) {
        approximated++;
        usdPrice = prices.nearest(date);
      }
      stamped.add(UsdPriceStampedTransaction(transaction, usdPrice.toDouble()));
    }
    if (approximated > 0) {
      _log.warning(
        'Priced $approximated of ${transactions.length} ${coinId.id} '
        'transactions at the nearest date with a USD price',
      );
    }
    return stamped;
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

      if (transaction.amount.toDouble() > 0) {
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
      holdings: transaction.amount.toDouble(),
      price: transaction.priceUsd,
    );
    return _ProfitLossState(
      holdings: [...state.holdings, newHolding],
      realizedProfitLoss: state.realizedProfitLoss,
      totalInvestment: state.totalInvestment + transaction.balanceChangeUsd,
      currentHoldings: state.currentHoldings + transaction.amount.toDouble(),
    );
  }

  _ProfitLossState _processSellTransaction(
    _ProfitLossState state,
    UsdPriceStampedTransaction transaction,
  ) {
    if (state.currentHoldings < transaction.amount.toDouble()) {
      throw Exception('Attempting to sell more than currently held');
    }

    // Balance change is negative for sales, so we use the abs value to
    // calculate the cost basis (formula assumes positive "total" value).
    var remainingToSell = transaction.amount.toDouble().abs();
    var costBasis = 0.0;
    final newHoldings = List<({double holdings, double price})>.from(
      state.holdings,
    );

    while (remainingToSell > 0) {
      final oldestBuy = newHoldings.first.holdings;
      if (oldestBuy <= remainingToSell) {
        newHoldings.removeAt(0);
        costBasis += oldestBuy * state.holdings.first.price;
        remainingToSell -= oldestBuy;
      } else {
        newHoldings[0] = (
          holdings: newHoldings[0].holdings - remainingToSell,
          price: newHoldings[0].price,
        );
        costBasis += remainingToSell * state.holdings.first.price;
        remainingToSell = 0;
      }
    }

    final double saleProceeds = transaction.balanceChangeUsd.abs();
    final double newRealizedProfitLoss =
        state.realizedProfitLoss + (saleProceeds - costBasis);

    // Balance change is negative for a sale, so subtract the abs value (
    // or add the positive value) to get the new holdings.
    final double newCurrentHoldings =
        state.currentHoldings - transaction.amount.toDouble().abs();
    final double newTotalInvestment = state.totalInvestment - costBasis;

    return _ProfitLossState(
      holdings: newHoldings,
      realizedProfitLoss: newRealizedProfitLoss,
      totalInvestment: newTotalInvestment,
      currentHoldings: newCurrentHoldings,
    );
  }

  double _calculateProfitLoss(_ProfitLossState state, Decimal currentPrice) {
    final currentValue = state.currentHoldings * currentPrice.toDouble();
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
    final currentValue = state.currentHoldings * currentPrice.toDouble();
    final unrealizedProfitLoss = currentValue - state.totalInvestment;
    return unrealizedProfitLoss;
  }
}

class _ProfitLossState {
  _ProfitLossState({
    List<({double holdings, double price})>? holdings,
    this.realizedProfitLoss = 0.0,
    this.totalInvestment = 0.0,
    this.currentHoldings = 0.0,
  }) : holdings = holdings ?? [];
  final List<({double holdings, double price})> holdings;
  final double realizedProfitLoss;
  final double totalInvestment;
  final double currentHoldings;
}

/// USD prices by UTC midnight, answering a date without a price with the
/// closest date that has one.
class _NearestPrices {
  _NearestPrices(this._prices) : _dates = _prices.keys.toList()..sort();

  final Map<DateTime, Decimal> _prices;
  final List<DateTime> _dates;

  Decimal? exact(DateTime date) => _prices[date];

  Decimal get latest => _prices[_dates.last]!;

  Decimal nearest(DateTime date) {
    final index = lowerBound(_dates, date);
    if (index == 0) return _prices[_dates.first]!;
    if (index == _dates.length) return latest;

    final before = _dates[index - 1];
    final after = _dates[index];
    final closer = date.difference(before) <= after.difference(date)
        ? before
        : after;
    return _prices[closer]!;
  }
}
