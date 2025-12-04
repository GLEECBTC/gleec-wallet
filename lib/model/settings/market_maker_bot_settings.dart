import 'package:equatable/equatable.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/message_service_config/message_service_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';

/// Settings for the KDF Simple Market Maker Bot.
class MarketMakerBotSettings extends Equatable {
  static final Logger _log = Logger('MarketMakerBotSettings');

  const MarketMakerBotSettings({
    required this.isMMBotEnabled,
    required this.botRefreshRate,
    required this.tradeCoinPairConfigs,
    this.messageServiceConfig,
  });

  /// Initial (default) settings for the Market Maker Bot.
  ///
  /// The Market Maker Bot is disabled by default and all other settings are
  /// empty or zero.
  factory MarketMakerBotSettings.initial() {
    return MarketMakerBotSettings(
      isMMBotEnabled: false,
      botRefreshRate: 60,
      tradeCoinPairConfigs: const [],
      messageServiceConfig: null,
    );
  }

  /// Creates a Market Maker Bot settings object from a JSON map.
  /// Returns the initial settings if the JSON map is null or does not contain
  /// the required `is_market_maker_bot_enabled` key.
  factory MarketMakerBotSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return MarketMakerBotSettings.initial();

    final bool? enabled = json['is_market_maker_bot_enabled'] as bool?;
    final int refresh = (json['bot_refresh_rate'] is int)
        ? json['bot_refresh_rate'] as int
        : int.tryParse('${json['bot_refresh_rate']}') ?? 60;

    final dynamic configsRaw = json['trade_coin_pair_configs'];
    final List<TradeCoinPairConfig> configs = (configsRaw is List)
        ? configsRaw
              .map((dynamic e) {
                // Log before skipping, rather than silently filtering invalid entries
                if (e is! Map<String, dynamic>) {
                  _log.warning('Invalid trade coin pair config: $e');
                  return null;
                }

                try {
                  // Skip invalid entries rather than crashing on startup
                  if (!e.containsKey('name') ||
                      !e.containsKey('base') ||
                      !e.containsKey('rel') ||
                      !e.containsKey('spread') ||
                      !e.containsKey('enable')) {
                    _log.warning('Invalid trade coin pair config: $e');
                    return null;
                  }
                  return TradeCoinPairConfig.fromJson(e);
                } catch (error, stackTrace) {
                  _log.warning(
                    'Invalid trade coin pair config',
                    error,
                    stackTrace,
                  );
                  return null;
                }
              })
              .whereType<TradeCoinPairConfig>()
              .toList()
        : const <TradeCoinPairConfig>[];

    final MessageServiceConfig? messageCfg =
        (json['message_service_config'] is Map<String, dynamic>)
        ? MessageServiceConfig.fromJson(json['message_service_config'])
        : null;

    return MarketMakerBotSettings(
      isMMBotEnabled: enabled ?? false,
      botRefreshRate: refresh,
      tradeCoinPairConfigs: configs,
      messageServiceConfig: messageCfg,
    );
  }

  /// Whether the Market Maker Bot is enabled (menu item is shown or not).
  final bool isMMBotEnabled;

  /// The refresh rate of the bot in seconds.
  final int botRefreshRate;

  /// The list of trade coin pair configurations.
  final List<TradeCoinPairConfig> tradeCoinPairConfigs;

  /// The message service configuration.
  ///
  /// This is used to enable Telegram notifications for the bot.
  final MessageServiceConfig? messageServiceConfig;

  Map<String, dynamic> toJson() {
    return {
      'is_market_maker_bot_enabled': isMMBotEnabled,
      'bot_refresh_rate': botRefreshRate,
      'trade_coin_pair_configs': tradeCoinPairConfigs
          .map((e) => e.toJson())
          .toList(),
      if (messageServiceConfig != null)
        'message_service_config': messageServiceConfig?.toJson(),
    };
  }

  // Legacy representation kept for backward-compatible writes
  Map<String, dynamic> toLegacyJson() {
    return {
      'is_market_maker_bot_enabled': isMMBotEnabled,
      // Old builds included a price_url; provide the previous default
      'price_url':
          'https://defistats.gleec.com/api/v3/prices/tickers_v2?expire_at=60',
      'bot_refresh_rate': botRefreshRate,
      'trade_coin_pair_configs': tradeCoinPairConfigs
          .map((e) => e.toJson())
          .toList(),
      if (messageServiceConfig != null)
        'message_service_config': messageServiceConfig?.toJson(),
    };
  }

  MarketMakerBotSettings copyWith({
    bool? isMMBotEnabled,
    int? botRefreshRate,
    List<TradeCoinPairConfig>? tradeCoinPairConfigs,
    MessageServiceConfig? messageServiceConfig,
  }) {
    return MarketMakerBotSettings(
      isMMBotEnabled: isMMBotEnabled ?? this.isMMBotEnabled,
      botRefreshRate: botRefreshRate ?? this.botRefreshRate,
      tradeCoinPairConfigs: tradeCoinPairConfigs ?? this.tradeCoinPairConfigs,
      messageServiceConfig: messageServiceConfig ?? this.messageServiceConfig,
    );
  }

  @override
  List<Object?> get props => [
    isMMBotEnabled,
    botRefreshRate,
    tradeCoinPairConfigs,
    messageServiceConfig,
  ];
}
