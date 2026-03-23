import 'package:equatable/equatable.dart';

import 'trade_coin_pair_config.dart';

/// The parameters for the market maker bot. These are sent as part of the
/// market_maker_bot_start RPC call to the KDF API.
class MarketMakerBotParameters extends Equatable {
  const MarketMakerBotParameters({
    this.priceUrl,
    this.botRefreshRate,
    this.tradeCoinPairs,
  });

  /// The full URL to the price API endpoint.
  final String? priceUrl;

  /// The rate at which the bot should refresh its data in seconds.
  final int? botRefreshRate;

  /// The configuration for each trading pair. The key is the trading pair name.
  /// The value is the configuration for that trading pair.
  ///
  /// For example, the key could be 'BTC-ETH' and the value could be the
  /// configuration for the BTC-ETH trading pair.
  final Map<String, TradeCoinPairConfig>? tradeCoinPairs;

  factory MarketMakerBotParameters.fromJson(Map<String, dynamic> json) =>
      MarketMakerBotParameters(
        priceUrl: json['price_url'] as String?,
        botRefreshRate: (json['bot_refresh_rate'] as num?)?.toInt(),
        tradeCoinPairs: json['cfg'] == null
            ? null
            : (json['cfg'] as Map<String, dynamic>).map(
                (k, e) => MapEntry(k, TradeCoinPairConfig.fromJson(e)),
              ),
      );

  Map<String, dynamic> toJson() => {
    'price_url': priceUrl,
    'bot_refresh_rate': botRefreshRate,
    'cfg': tradeCoinPairs?.map((k, e) => MapEntry(k, e.toJson())) ?? {},
  }..removeWhere((_, value) => value == null);

  MarketMakerBotParameters copyWith({
    String? priceUrl,
    int? botRefreshRate,
    Map<String, TradeCoinPairConfig>? cfg,
  }) {
    return MarketMakerBotParameters(
      priceUrl: priceUrl ?? this.priceUrl,
      botRefreshRate: botRefreshRate ?? this.botRefreshRate,
      tradeCoinPairs: cfg ?? tradeCoinPairs,
    );
  }

  @override
  List<Object?> get props => [priceUrl, botRefreshRate, tradeCoinPairs];
}
