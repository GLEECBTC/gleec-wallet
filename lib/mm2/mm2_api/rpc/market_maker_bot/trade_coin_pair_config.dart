import 'package:equatable/equatable.dart';
import 'package:web_dex/views/market_maker_bot/trade_bot_update_interval.dart';

import 'trade_volume.dart';

/// Represents the settings for a trading pair.
class TradeCoinPairConfig extends Equatable {
  const TradeCoinPairConfig({
    required this.name,
    required this.baseCoinId,
    required this.relCoinId,
    this.maxBalancePerTrade,
    this.minVolume,
    this.maxVolume,
    this.minBasePriceUsd,
    this.minRelPriceUsd,
    this.minPairPrice,
    required this.spread,
    this.baseConfs,
    this.baseNota,
    this.relConfs,
    this.relNota,
    this.enable = true,
    this.priceElapsedValidity,
    this.checkLastBidirectionalTradeThreshHold,
  });

  /// The name of the trading pair
  final String name;

  /// The id of the coin to sell in the trade. Usually the ticker symbol.
  /// E.g. 'BTC-segwit' or 'ETH'
  final String baseCoinId;

  /// The id of the coin to buy in the trade. Usually the ticker symbol.
  final String relCoinId;

  /// Whether to trade the entire balance
  final bool? maxBalancePerTrade;

  /// The maximum volume to trade expressed in terms of percentage of the total
  /// balance of the [baseCoinId]. For  example, a value of 0.5 represents 50%
  /// of the total balance of [baseCoinId].
  final TradeVolume? maxVolume;

  /// The minimum volume to trade expressed in terms of percentage of the total
  /// balance of the [baseCoinId]. For  example, a value of 0.5 represents 50%
  /// of the total balance of [baseCoinId].
  final TradeVolume? minVolume;

  /// The minimum USD price of the base coin to accept in trade
  final double? minBasePriceUsd;

  /// The minimum USD price of the rel coin to accept in trade
  final double? minRelPriceUsd;

  /// The minimum USD price of the pair to accept in trade
  final double? minPairPrice;

  /// The spread to use in trade as a decimal value representing the percentage.
  /// For example, a spread of 1.04 represents a 4% spread.
  final String spread;

  /// The number of confirmations required for the base coin
  final int? baseConfs;

  /// Whether the base coin requires a notarization
  final bool? baseNota;

  /// The number of confirmations required for the rel coin
  final int? relConfs;

  /// Whether the rel coin requires a notarization
  final bool? relNota;

  /// Whether to enable the trading pair. Defaults to false.
  /// The trading pair will be ignored if true
  final bool enable;

  /// Will cancel current orders for this pair and not submit a new order if
  /// last price update time has been longer than this value in seconds.
  /// Defaults to 5 minutes.
  final int? priceElapsedValidity;

  /// Will readjust the calculated cex price if a precedent trade exists for
  /// the pair (or reversed pair), applied via a VWAP logic. This is a trading
  /// strategy to adjust the price of one pair to the VWAP price, encouraging
  /// trades in the opposite direction to address temporary liquidity imbalances
  ///
  /// NOTE: This requires two trades to be made in the pair (or reversed pair).
  ///
  /// Defaults to false.
  ///
  /// ## Trade Analysis:
  /// - The bot evaluates the last 1000 trades for both base/rel and rel/base
  /// pairs (up to 2000 total).
  ///
  /// ## VWAP Calculation:
  /// - For each pair, the VWAP is computed by taking the sum of the product of
  /// each trade's price and volume (sum(price * volume)) and dividing it by the
  /// total volume (sum(volume)).
  /// - When calculating the VWAP for the reverse pair (rel/base), the bot
  /// considers its own base asset as the reference, and it gets the price for
  /// the base asset.
  /// - Combines/sums the separate VWAPs for base/rel and rel/base trades into
  /// a total VWAP.
  ///
  /// ## Price Comparison:
  /// - Compares total VWAP to the bot's calculated price
  /// (price from price service * spread).
  /// - If VWAP > calculated price, uses VWAP for order price.
  ///
  /// ## Liquidity Adjustment:
  /// - By setting the price of one pair to the VWAP price, the bot adjusts
  /// market maker orders above the market rate for one direction to encourage
  /// trades in the opposite direction, addressing temporary liquidity
  /// imbalances until equilibrium is restored.
  final bool? checkLastBidirectionalTradeThreshHold;

  /// Returns [baseCoinId] and [relCoinId] in the format 'BASE/REL'.
  /// E.g. 'BTC/ETH'
  String get simpleName => getSimpleName(baseCoinId, relCoinId);

  /// Returns the margin as a percentage value
  double get margin => (double.parse(spread) - 1) * 100;

  /// Converts the update interval for the trade bot to [TradeBotUpdateInterval]
  TradeBotUpdateInterval get updateInterval =>
      TradeBotUpdateInterval.fromString(
        priceElapsedValidity?.toString() ?? '300',
      );

  /// Returns [baseCoinId] and [relCoinId] in the format 'BASE/REL'.
  /// E.g. 'BTC/ETH'
  static String getSimpleName(String baseCoinId, String relCoinId) =>
      '$baseCoinId/$relCoinId'.toUpperCase();

  factory TradeCoinPairConfig.fromJson(Map<String, dynamic> json) {
    return TradeCoinPairConfig(
      name: json['name'] as String,
      baseCoinId: json['base'] as String,
      relCoinId: json['rel'] as String,
      maxBalancePerTrade: json['max'] as bool?,
      minVolume: json['min_volume'] != null
          ? TradeVolume.fromJson(json['min_volume'] as Map<String, dynamic>)
          : null,
      maxVolume: json['max_volume'] != null
          ? TradeVolume.fromJson(json['max_volume'] as Map<String, dynamic>)
          : null,
      minBasePriceUsd: (json['min_base_price'] as num?)?.toDouble(),
      minRelPriceUsd: (json['min_rel_price'] as num?)?.toDouble(),
      minPairPrice: (json['min_pair_price'] as num?)?.toDouble(),
      spread: json['spread'] as String,
      baseConfs: (json['base_confs'] as num?)?.toInt(),
      baseNota: json['base_nota'] as bool?,
      relConfs: (json['rel_confs'] as num?)?.toInt(),
      relNota: json['rel_nota'] as bool?,
      enable: json['enable'] as bool,
      priceElapsedValidity: (json['price_elapsed_validity'] as num?)?.toInt(),
      checkLastBidirectionalTradeThreshHold:
          json['check_last_bidirectional_trade_thresh_hold'] as bool?,
    );
  }

  /// Converts the object to a JSON serializable map. NOTE: removes null values
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'base': baseCoinId,
      'rel': relCoinId,
      'max': maxBalancePerTrade,
      'min_volume': minVolume?.toJson(),
      'max_volume': maxVolume?.toJson(),
      'min_base_price': minBasePriceUsd,
      'min_rel_price': minRelPriceUsd,
      'min_pair_price': minPairPrice,
      'spread': spread,
      'base_confs': baseConfs,
      'base_nota': baseNota,
      'rel_confs': relConfs,
      'rel_nota': relNota,
      'enable': enable,
      'price_elapsed_validity': priceElapsedValidity,
      'check_last_bidirectional_trade_thresh_hold':
          checkLastBidirectionalTradeThreshHold,
    }..removeWhere((key, value) => value == null || value == {});
  }

  TradeCoinPairConfig copyWith({
    String? name,
    String? baseCoinId,
    String? relCoinId,
    bool? maxBalancePerTrade,
    TradeVolume? minVolume,
    TradeVolume? maxVolume,
    double? minBasePriceUsd,
    double? minRelPriceUsd,
    double? minPairPriceUsd,
    String? spread,
    int? baseConfs,
    bool? baseNota,
    int? relConfs,
    bool? relNota,
    bool? enable,
    int? priceElapsedValidity,
    bool? checkLastBidirectionalTradeThreshHold,
  }) {
    return TradeCoinPairConfig(
      name: name ?? this.name,
      baseCoinId: baseCoinId ?? this.baseCoinId,
      relCoinId: relCoinId ?? this.relCoinId,
      maxBalancePerTrade: maxBalancePerTrade ?? this.maxBalancePerTrade,
      minVolume: minVolume ?? this.minVolume,
      maxVolume: maxVolume ?? this.maxVolume,
      minBasePriceUsd: minBasePriceUsd ?? this.minBasePriceUsd,
      minRelPriceUsd: minRelPriceUsd ?? this.minRelPriceUsd,
      minPairPrice: minPairPriceUsd ?? minPairPrice,
      spread: spread ?? this.spread,
      baseConfs: baseConfs ?? this.baseConfs,
      baseNota: baseNota ?? this.baseNota,
      relConfs: relConfs ?? this.relConfs,
      relNota: relNota ?? this.relNota,
      enable: enable ?? this.enable,
      priceElapsedValidity: priceElapsedValidity ?? this.priceElapsedValidity,
      checkLastBidirectionalTradeThreshHold:
          checkLastBidirectionalTradeThreshHold ??
          this.checkLastBidirectionalTradeThreshHold,
    );
  }

  @override
  List<Object?> get props => [
    name,
    baseCoinId,
    relCoinId,
    maxBalancePerTrade,
    minVolume,
    maxVolume,
    minBasePriceUsd,
    minRelPriceUsd,
    minPairPrice,
    spread,
    baseConfs,
    baseNota,
    relConfs,
    relNota,
    enable,
    priceElapsedValidity,
    checkLastBidirectionalTradeThreshHold,
  ];
}
