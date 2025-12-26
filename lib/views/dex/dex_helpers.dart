import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/dex_form_error.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/trade_preimage_extended_fee_info.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/balances_formatter.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class FiatAmount extends StatelessWidget {
  final Coin coin;
  final Rational amount;
  final TextStyle? style;

  const FiatAmount({
    super.key,
    required this.coin,
    required this.amount,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle? textStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.merge(style);

    return Text(
      getFormattedFiatAmount(context, coin.abbr, amount),
      style: textStyle,
    );
  }
}

String getFormattedFiatAmount(
  BuildContext context,
  String coinAbbr,
  Rational amount, [
  int digits = 8,
]) {
  final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
  final Coin? coin = coinsRepository.getCoin(coinAbbr);
  if (coin == null) return '';
  return '≈\$${formatAmt(getFiatAmount(coin, amount))}';
}

List<Swap> applyFiltersForSwap(
  List<Swap> swaps,
  TradingEntitiesFilter entitiesFilterData,
) {
  return swaps.where((swap) {
    final String? sellCoin = entitiesFilterData.sellCoin;
    final String? buyCoin = entitiesFilterData.buyCoin;
    final int? startDate = entitiesFilterData.startDate?.millisecondsSinceEpoch;
    final int? endDate = entitiesFilterData.endDate?.millisecondsSinceEpoch;
    final List<TradingStatus>? statuses = entitiesFilterData.statuses;
    final List<TradeSide>? shownSides = entitiesFilterData.shownSides;

    if (sellCoin != null && swap.sellCoin != sellCoin) return false;
    if (buyCoin != null && swap.buyCoin != buyCoin) return false;
    if (startDate != null && (swap.myInfo?.startedAt ?? 0) < startDate / 1000) {
      return false;
    }
    if (endDate != null &&
        (swap.myInfo?.startedAt ?? 0) > (endDate + millisecondsIn24H) / 1000) {
      return false;
    }
    if (statuses != null && statuses.isNotEmpty) {
      if (statuses.contains(TradingStatus.successful) &&
          statuses.contains(TradingStatus.failed)) {
        return true;
      }
      if (statuses.contains(TradingStatus.successful)) {
        return swap.isSuccessful;
      }
      if (statuses.contains(TradingStatus.failed)) return swap.isFailed;
    }

    if (shownSides != null &&
        shownSides.isNotEmpty &&
        !shownSides.contains(swap.type)) {
      return false;
    }

    return true;
  }).toList();
}

List<MyOrder> applyFiltersForOrders(
  List<MyOrder> orders,
  TradingEntitiesFilter entitiesFilterData,
) {
  return orders.where((order) {
    final String? sellCoin = entitiesFilterData.sellCoin;
    final String? buyCoin = entitiesFilterData.buyCoin;
    final int? startDate = entitiesFilterData.startDate?.millisecondsSinceEpoch;
    final int? endDate = entitiesFilterData.endDate?.millisecondsSinceEpoch;
    final List<TradeSide>? shownSides = entitiesFilterData.shownSides;

    if (sellCoin != null && order.base != sellCoin) return false;
    if (buyCoin != null && order.rel != buyCoin) return false;
    if (startDate != null && order.createdAt < startDate / 1000) return false;
    if (endDate != null &&
        order.createdAt > (endDate + millisecondsIn24H) / 1000) {
      return false;
    }
    if ((shownSides != null && shownSides.isNotEmpty) &&
        !shownSides.contains(order.orderType)) {
      return false;
    }

    return true;
  }).toList();
}

Map<String, List<String>> getCoinAbbrMapFromOrderList(
  List<MyOrder> list,
  bool isSellCoin,
) {
  final Map<String, List<String>> coinAbbrMap = isSellCoin
      ? list.fold<Map<String, List<String>>>({}, (previousValue, element) {
          final List<String> coinAbbrList = previousValue[element.base] ?? [];
          coinAbbrList.add(element.rel);
          previousValue[element.base] = coinAbbrList;
          return previousValue;
        })
      : list.fold<Map<String, List<String>>>({}, (previousValue, element) {
          final List<String> coinAbbrList = previousValue[element.rel] ?? [];
          coinAbbrList.add(element.base);
          previousValue[element.rel] = coinAbbrList;
          return previousValue;
        });
  return coinAbbrMap;
}

Map<String, List<String>> getCoinAbbrMapFromSwapList(
  List<Swap> list,
  bool isSellCoin,
) {
  final Map<String, List<String>> coinAbbrMap = isSellCoin
      ? list.fold<Map<String, List<String>>>({}, (previousValue, element) {
          final List<String> coinAbbrList =
              previousValue[element.sellCoin] ?? [];
          coinAbbrList.add(element.buyCoin);
          previousValue[element.sellCoin] = coinAbbrList;
          return previousValue;
        })
      : list.fold<Map<String, List<String>>>({}, (previousValue, element) {
          final List<String> coinAbbrList =
              previousValue[element.buyCoin] ?? [];
          coinAbbrList.add(element.sellCoin);
          previousValue[element.buyCoin] = coinAbbrList;
          return previousValue;
        });
  return coinAbbrMap;
}

int getCoinPairsCountFromCoinAbbrMap(
  Map<String, List<String>> coinAbbrMap,
  String coinAbbr,
  String? secondCoinAbbr,
) {
  return (coinAbbrMap[coinAbbr] ?? [])
      .where((abbr) => secondCoinAbbr == null || secondCoinAbbr == abbr)
      .toList()
      .length;
}

/// Compares the rate of a decentralized exchange (DEX) with a centralized exchange (CEX) in percentage.
///
/// The comparison is based on the provided exchange rates and a given [rate] of the DEX.
/// The DEX rate is converted to a double using `toDouble()` from the [rate], while the CEX rate
/// is calculated as the ratio of [baseUsdPrice] to [relUsdPrice].
/// The method then computes the percentage difference between the DEX rate and CEX rate.
/// If either [baseUsdPrice] or [relUsdPrice] is 0, or the [rate] is equal to zero (Rational.zero),
/// the comparison result will be 0 to avoid potential division by zero.
///
/// Parameters:
/// - [baseUsdPrice] (double): The USD price of the base currency on the centralized exchange (CEX).
/// - [relUsdPrice] (double): The USD price of the relative currency on the centralized exchange (CEX).
/// - [rate] (Rational): The rate of the base currency to the relative currency on the decentralized exchange (DEX).
///
/// Return Value:
/// - (double): The percentage difference between the DEX rate and CEX rate.
///
/// Example Usage:
/// ```dart
/// double cexBasePrice = 5000.0; // USD price of the base currency on CEX
/// double cexRelPrice = 100.0; // USD price of the relative currency on CEX
/// Rational dexRate = Rational.fromDouble(40); // DEX rate: 40 base currency units per relative currency unit
///
/// double comparisonResult = compareToCex(cexBasePrice, cexRelPrice, dexRate);
/// print(comparisonResult); // Output: 1000.0 (percentage difference: 1000%)
/// ```
/// ```dart
/// double cexBasePrice = 10.0; // USD price of the base currency on CEX
/// double cexRelPrice = 5.0; // USD price of the relative currency on CEX
/// Rational dexRate = Rational.fromInt(1); // DEX rate: 1 base currency unit per relative currency unit
///
/// double comparisonResult = compareToCex(cexBasePrice, cexRelPrice, dexRate);
/// print(comparisonResult); // Output: -50.0 (percentage difference: -50%)
/// ```
/// unit tests: [compare_dex_to_cex_tests]
double compareToCex(double baseUsdPrice, double relUsdPrice, Rational rate) {
  if (baseUsdPrice == 0 || relUsdPrice == 0) return 0;
  if (rate == Rational.zero) return 0;

  final double dexRate = rate.toDouble();
  final double cexRate = baseUsdPrice / relUsdPrice;

  return (dexRate - cexRate) * 100 / cexRate;
}

Future<List<DexFormError>> activateCoinIfNeeded(
  String? abbr,
  CoinsRepo coinsRepository,
) async {
  final List<DexFormError> errors = [];
  if (abbr == null) return errors;

  final Coin? coin = coinsRepository.getCoin(abbr);
  if (coin == null) return errors;

  try {
    // Gate auto-activation until CoinsBloc completes initial activation
    await coinsRepository.waitForInitialActivationToComplete(
      timeout: const Duration(seconds: 30),
    );
    // sdk handles parent activation logic, so simply call
    // activation here
    await coinsRepository.activateCoinsSync([coin]);
  } catch (e) {
    errors.add(
      DexFormError(
        error: '${LocaleKeys.unableToActiveCoin.tr(args: [coin.abbr])}: $e',
      ),
    );
  }

  return errors;
}

Future<void> reInitTradingForms(BuildContext context) async {
  // If some of the DEX or Bridge forms were modified by user during
  // interaction in 'no-login' mode, their blocs may link to special
  // instances of [Coin], initialized in that mode.
  // After login to iguana wallet,
  // we must replace them with regular [Coin] instances, and
  // auto-activate corresponding coins if needed
  final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
  await makerFormBloc.reInitForm();
}

/// unit tests: [testMaxMinRational]
Rational? maxRational(List<Rational> values) {
  if (values.isEmpty) return null;

  Rational maxValue = values.first;
  for (Rational value in values) {
    if (value > maxValue) maxValue = value;
  }

  return maxValue;
}

/// unit tests: [testMaxMinRational]
Rational? minRational(List<Rational> values) {
  if (values.isEmpty) return null;

  Rational minValue = values.first;
  for (Rational value in values) {
    if (value < minValue) minValue = value;
  }

  return minValue;
}

/// Returns the amount of the buy currency that can be bought for the given sell amount and selected order.
/// Parameters:
/// - [sellAmount] (Rational): The amount of the sell currency to be sold.
/// - [selectedOrder] (BestOrder): The selected order.
/// Return Value:
/// - (Rational): The amount of the buy currency that can be bought for the given sell amount and selected order.
/// Example Usage:
/// ```dart
/// Rational sellAmount = Rational.fromInt(100);
/// BestOrder selectedOrder = BestOrder(price: Rational.fromInt(10), ...);
/// Rational buyAmount = calculateBuyAmount(sellAmount: sellAmount, selectedOrder: selectedOrder);
/// print(buyAmount); // Output: 1000
/// ```
/// unit tests: [testCalculateBuyAmount]
Rational? calculateBuyAmount({
  required Rational? sellAmount,
  required BestOrder? selectedOrder,
}) {
  if (sellAmount == null) return null;
  if (selectedOrder == null) return null;

  return selectedOrder.price * sellAmount;
}

/// Calculates and formats the total fee amount based on a list of [TradePreimageExtendedFeeInfo].
///
/// The method calculates the total fee amount in USD equivalent for each fee in the [totalFeesInitial] list.
/// The provided [getCoin] function is used to retrieve the Coin object based on its abbreviation.
/// The method then formats the total fee amount and returns it as a string.
///
/// Parameters:
/// - [totalFeesInitial] (List<TradePreimageExtendedFeeInfo>?): List of fee information objects.
/// - [getCoin] (Coin Function(String abbr)): Function to retrieve Coin objects based on abbreviation.
///
/// Return Value:
/// - (String): The formatted total fee amount string.
///
/// Example Usage:
/// ```dart
/// List<TradePreimageExtendedFeeInfo> fees = [
///   TradePreimageExtendedFeeInfo('BTC', '0.001'),
///   TradePreimageExtendedFeeInfo('ETH', '0.01'),
///   TradePreimageExtendedFeeInfo('USD', '5.0'),
/// ];
/// String result = getTotalFee(fees, (abbr) => Coin(abbr));
/// print(result); // Output: "\$6.01 +0.001 BTC +0.01 ETH"
/// ```
/// unit tests: [testGetTotalFee]
String getTotalFee(
  List<TradePreimageExtendedFeeInfo>? totalFeesInitial,
  Coin? Function(String abbr) getCoin,
) {
  if (totalFeesInitial == null) return '\$0.00';

  final Map<String, Rational> normalizedTotals = totalFeesInitial
      .fold<Map<String, Rational>>(
        {'USD': Rational.zero},
        (previousValue, fee) =>
            _combineFees(getCoin(fee.coin), fee, previousValue),
      );

  final String totalFees = normalizedTotals.entries.fold<String>(
    '',
    _combineTotalFee,
  );

  return totalFees;
}

final String _nbsp = String.fromCharCode(0x00A0);
String _combineTotalFee(
  String previousValue,
  MapEntry<String, Rational> element,
) {
  final Rational amount = element.value;
  final String coin = element.key;
  if (amount == Rational.zero) return previousValue;

  if (previousValue.isNotEmpty) previousValue += ' +$_nbsp';
  if (coin == 'USD') {
    previousValue += '\$${cutTrailingZeros(formatAmt(amount.toDouble()))}';
  } else {
    previousValue +=
        '${cutTrailingZeros(formatAmt(amount.toDouble()))}$_nbsp${Coin.normalizeAbbr(coin)}';
  }
  return previousValue;
}

Map<String, Rational> _combineFees(
  Coin? coin,
  TradePreimageExtendedFeeInfo fee,
  Map<String, Rational> previousValue,
) {
  final feeAmount = Rational.tryParse(fee.amount) ?? Rational.zero;
  final feeUsdAmount =
      feeAmount * (coin?.usdPrice?.price ?? Decimal.zero).toRational();

  if (feeUsdAmount > Rational.zero) {
    previousValue['USD'] = previousValue['USD']! + feeUsdAmount;
  } else if (feeAmount > Rational.zero) {
    previousValue[fee.coin] = feeAmount;
  }
  return previousValue;
}

/// Calculates the sell amount based on the maximum sell amount and a fraction.
////// Parameters:
/// - [amount] (Rational): The maximum sell amount for a trade.
/// - [fraction] (double): The fraction of the [amount] to be calculated.
///
/// Return Value:
/// - (Rational): The calculated sell amount based on the provided [amount] and [fraction].
///
/// Example Usage:
/// ```dart
/// Rational maxSellAmount = Rational.fromInt(100);
/// double fraction = 0.75;
/// Rational result = getSellAmount(maxSellAmount, fraction);
/// print(result); // Output: 75
/// ```
/// unit tests: [testGetSellAmount]
Rational getFractionOfAmount(Rational amount, double fraction) {
  final Rational fractionedAmount = amount * Rational.parse('$fraction');
  return fractionedAmount;
}

/// Return the price and buy amount based on provided values of sellAmount, price and buyAmount.
///
/// Parameters:
/// - [sellAmount] (Rational?): The sell amount value.
/// - [price] (Rational?): The price value.
/// - [buyAmount] (Rational?): The buy amount value.
///
/// Return Value:
/// - ((Rational?, Rational?)?): A tuple containing the updated [buyAmount] and [price].
///
/// Example Usage:
/// ```dart
/// Rational? sellAmount = Rational.fromInt(100);
/// Rational? price = Rational.fromInt(2);
/// Rational? buyAmount = null;
/// var result = updateSellAmount(sellAmount, price, buyAmount);
/// print(result); // Output: (200, 2)
/// ```
(Rational?, Rational?)? processBuyAmountAndPrice(
  Rational? sellAmount,
  Rational? price,
  Rational? buyAmount,
) {
  if (sellAmount == null) return null;
  if (price == null && buyAmount == null) return null;
  if (price != null) {
    buyAmount = sellAmount * price;
    return (buyAmount, price);
  } else if (buyAmount != null) {
    try {
      price = buyAmount / sellAmount;
      return (buyAmount, price);
    } catch (_) {
      return (buyAmount, null);
    }
  }
  return (buyAmount, price);
}
