import 'package:equatable/equatable.dart';
import 'package:web_dex/views/market_maker_bot/trade_bot_update_interval.dart';

import 'trade_volume.dart';

/// Represents the settings for a trading pair.
class TradeCoinPairConfig extends Equatable {
  factory TradeCoinPairConfig({
    required String name,
    required String baseCoinId,
    required String relCoinId,
    bool? maxBalancePerTrade,
    TradeVolume? minVolume,
    TradeVolume? maxVolume,
    double? minBasePriceUsd,
    double? minRelPriceUsd,
    double? minPairPrice,
    required String spread,
    int? baseConfs,
    bool? baseNota,
    int? relConfs,
    bool? relNota,
    bool enable = true,
    int? priceElapsedValidity,
    bool? checkLastBidirectionalTradeThreshHold,
  }) {
    final canonicalName = getSimpleName(baseCoinId, relCoinId);
    _validateCoinIdentifier(baseCoinId);
    _validateCoinIdentifier(relCoinId);

    if (baseCoinId.toUpperCase() == relCoinId.toUpperCase()) {
      throw const FormatException('Trading pair assets must be different');
    }
    if (name.length > maximumPairNameLength ||
        name.toUpperCase() != canonicalName) {
      throw const FormatException('Invalid trading pair name');
    }

    _validateSpread(spread);
    _validateOptionalUsdValue(minBasePriceUsd);
    _validateOptionalUsdValue(minRelPriceUsd);
    _validateOptionalUsdValue(minPairPrice);
    _validateConfirmations(baseConfs);
    _validateConfirmations(relConfs);
    _validatePriceElapsedValidity(priceElapsedValidity);

    if (maxBalancePerTrade == true && maxVolume != null) {
      throw const FormatException('Conflicting maximum volume settings');
    }
    if (minVolume != null &&
        maxVolume != null &&
        minVolume.type == maxVolume.type &&
        minVolume.value > maxVolume.value) {
      throw const FormatException('Minimum volume exceeds maximum volume');
    }

    return TradeCoinPairConfig._(
      name: canonicalName,
      baseCoinId: baseCoinId,
      relCoinId: relCoinId,
      maxBalancePerTrade: maxBalancePerTrade,
      minVolume: minVolume,
      maxVolume: maxVolume,
      minBasePriceUsd: minBasePriceUsd,
      minRelPriceUsd: minRelPriceUsd,
      minPairPrice: minPairPrice,
      spread: spread,
      baseConfs: baseConfs,
      baseNota: baseNota,
      relConfs: relConfs,
      relNota: relNota,
      enable: enable,
      priceElapsedValidity: priceElapsedValidity,
      checkLastBidirectionalTradeThreshHold:
          checkLastBidirectionalTradeThreshHold,
    );
  }

  const TradeCoinPairConfig._({
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

  static const int maximumCoinIdentifierLength = 128;
  static const int maximumPairNameLength = maximumCoinIdentifierLength * 2 + 1;
  static const int maximumEncodedNumberLength = 128;
  static const int maximumConfirmations = 10000;
  // KDF supports a 30-second validity window; keep imported/legacy configs
  // compatible even though the current UI starts at one minute.
  static const int minimumPriceElapsedValiditySeconds = 30;
  static const int maximumPriceElapsedValiditySeconds = 86400;
  static const double maximumSpread = 11;

  static final RegExp _coinIdentifierPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._:-]*$',
  );

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

  /// Whether to enable the trading pair. Defaults to true.
  /// The trading pair will be ignored if false.
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
    final baseCoinId = _requiredString(json['base']);
    final relCoinId = _requiredString(json['rel']);
    // The name is app metadata and was absent from valid legacy KDF cfg maps.
    // Derive it when absent, but reject a supplied name that does not identify
    // this exact pair.
    final name = json['name'] == null
        ? getSimpleName(baseCoinId, relCoinId)
        : _requiredString(json['name']);

    return TradeCoinPairConfig(
      name: name,
      baseCoinId: baseCoinId,
      relCoinId: relCoinId,
      maxBalancePerTrade: _optionalBool(json['max']),
      minVolume: json['min_volume'] != null
          ? TradeVolume.fromJson(_requiredMap(json['min_volume']))
          : null,
      maxVolume: json['max_volume'] != null
          ? TradeVolume.fromJson(_requiredMap(json['max_volume']))
          : null,
      minBasePriceUsd: _optionalNumber(json['min_base_price']),
      minRelPriceUsd: _optionalNumber(json['min_rel_price']),
      minPairPrice: _optionalNumber(json['min_pair_price']),
      spread: _requiredNumberString(json['spread']),
      baseConfs: _optionalInteger(json['base_confs']),
      baseNota: _optionalBool(json['base_nota']),
      relConfs: _optionalInteger(json['rel_confs']),
      relNota: _optionalBool(json['rel_nota']),
      enable: _requiredBool(json['enable']),
      priceElapsedValidity: _optionalInteger(json['price_elapsed_validity']),
      checkLastBidirectionalTradeThreshHold: _optionalBool(
        json['check_last_bidirectional_trade_thresh_hold'],
      ),
    );
  }

  static String _requiredString(Object? rawValue) {
    if (rawValue is! String || rawValue.isEmpty) {
      throw const FormatException('Missing trading pair field');
    }
    return rawValue;
  }

  static Map<String, dynamic> _requiredMap(Object? rawValue) {
    if (rawValue is! Map) {
      throw const FormatException('Invalid trading pair field');
    }
    try {
      return Map<String, dynamic>.from(rawValue);
    } on TypeError {
      throw const FormatException('Invalid trading pair field');
    }
  }

  static bool _requiredBool(Object? rawValue) {
    if (rawValue is! bool) {
      throw const FormatException('Invalid trading pair flag');
    }
    return rawValue;
  }

  static bool? _optionalBool(Object? rawValue) {
    if (rawValue == null) return null;
    return _requiredBool(rawValue);
  }

  static String _requiredNumberString(Object? rawValue) {
    if (rawValue is String &&
        rawValue.isNotEmpty &&
        rawValue.length <= maximumEncodedNumberLength &&
        rawValue == rawValue.trim()) {
      return rawValue;
    }
    if (rawValue is num && rawValue.toDouble().isFinite) {
      return rawValue.toString();
    }
    throw const FormatException('Invalid trading pair number');
  }

  static double? _optionalNumber(Object? rawValue) {
    if (rawValue == null) return null;
    final encoded = _requiredNumberString(rawValue);
    final value = double.tryParse(encoded);
    if (value == null || !value.isFinite) {
      throw const FormatException('Invalid trading pair number');
    }
    return value;
  }

  static int? _optionalInteger(Object? rawValue) {
    if (rawValue == null) return null;

    if (rawValue is int) return rawValue;
    if (rawValue is num) {
      final value = rawValue.toDouble();
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
      throw const FormatException('Invalid trading pair integer');
    }
    if (rawValue is String &&
        rawValue.isNotEmpty &&
        rawValue.length <= maximumEncodedNumberLength &&
        rawValue == rawValue.trim()) {
      final value = int.tryParse(rawValue);
      if (value != null) return value;
    }

    throw const FormatException('Invalid trading pair integer');
  }

  static void _validateCoinIdentifier(String value) {
    if (value.length > maximumCoinIdentifierLength ||
        !_coinIdentifierPattern.hasMatch(value)) {
      throw const FormatException('Invalid coin identifier');
    }
  }

  static void _validateSpread(String encodedValue) {
    if (encodedValue.isEmpty ||
        encodedValue.length > maximumEncodedNumberLength ||
        encodedValue != encodedValue.trim()) {
      throw const FormatException('Invalid trading spread');
    }
    final value = double.tryParse(encodedValue);
    if (value == null ||
        !value.isFinite ||
        value <= 1 ||
        value > maximumSpread) {
      throw const FormatException('Invalid trading spread');
    }
  }

  static void _validateOptionalUsdValue(double? value) {
    if (value == null) return;
    if (!value.isFinite || value < 0 || value > TradeVolume.maximumUsdValue) {
      throw const FormatException('Invalid USD threshold');
    }
  }

  static void _validateConfirmations(int? value) {
    if (value == null) return;
    if (value < 0 || value > maximumConfirmations) {
      throw const FormatException('Invalid confirmation count');
    }
  }

  static void _validatePriceElapsedValidity(int? value) {
    if (value == null) return;
    if (value < minimumPriceElapsedValiditySeconds ||
        value > maximumPriceElapsedValiditySeconds) {
      throw const FormatException('Invalid price update interval');
    }
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
