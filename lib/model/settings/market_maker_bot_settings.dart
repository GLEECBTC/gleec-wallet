import 'package:equatable/equatable.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/message_service_config/message_service_config.dart';
import 'package:web_dex/mm2/mm2_api/rpc/market_maker_bot/trade_coin_pair_config.dart';

/// Settings for the KDF Simple Market Maker Bot.
class MarketMakerBotSettings extends Equatable {
  static final Logger _log = Logger('MarketMakerBotSettings');

  factory MarketMakerBotSettings({
    required bool isMMBotEnabled,
    required bool saveOrdersBetweenLaunches,
    required int botRefreshRate,
    required List<TradeCoinPairConfig> tradeCoinPairConfigs,
    MessageServiceConfig? messageServiceConfig,
  }) {
    if (botRefreshRate < minimumBotRefreshRateSeconds ||
        botRefreshRate > maximumBotRefreshRateSeconds) {
      throw const FormatException('Invalid market maker refresh interval');
    }
    if (tradeCoinPairConfigs.length > maximumTradePairConfigCount) {
      throw const FormatException('Too many market maker configurations');
    }

    final names = <String>{};
    for (final config in tradeCoinPairConfigs) {
      if (!names.add(config.name.toUpperCase())) {
        throw const FormatException('Duplicate market maker configuration');
      }
    }

    return MarketMakerBotSettings._(
      isMMBotEnabled: isMMBotEnabled,
      saveOrdersBetweenLaunches: saveOrdersBetweenLaunches,
      botRefreshRate: botRefreshRate,
      tradeCoinPairConfigs: List<TradeCoinPairConfig>.unmodifiable(
        tradeCoinPairConfigs,
      ),
      messageServiceConfig: messageServiceConfig,
    );
  }

  const MarketMakerBotSettings._({
    required this.isMMBotEnabled,
    required this.saveOrdersBetweenLaunches,
    required this.botRefreshRate,
    required this.tradeCoinPairConfigs,
    this.messageServiceConfig,
  });

  static const int minimumBotRefreshRateSeconds = 30;
  static const int maximumBotRefreshRateSeconds = 3600;
  static const int maximumTradePairConfigCount = 200;

  /// Initial (default) settings for the Market Maker Bot.
  ///
  /// The Market Maker Bot is disabled by default and uses conservative refresh
  /// and persistence defaults with no configured pairs.
  factory MarketMakerBotSettings.initial() {
    return MarketMakerBotSettings(
      isMMBotEnabled: false,
      saveOrdersBetweenLaunches: true,
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

    final enabled = _safeBool(json['is_market_maker_bot_enabled']) ?? false;
    final savedBetweenLaunches =
        _safeBool(json['save_orders_between_launches']) ?? true;
    final parsedRefresh = _safeInteger(json['bot_refresh_rate']);
    // Thirty seconds was supported by legacy KDF configurations. Preserve it
    // while rejecting hostile tight loops and impractically long intervals.
    final refresh =
        parsedRefresh != null &&
            parsedRefresh >= minimumBotRefreshRateSeconds &&
            parsedRefresh <= maximumBotRefreshRateSeconds
        ? parsedRefresh
        : 60;

    final dynamic configsRaw = json['trade_coin_pair_configs'];
    final configs = _parsePersistedConfigs(configsRaw);

    MessageServiceConfig? messageCfg;
    final messageRaw = json['message_service_config'];
    if (messageRaw is Map) {
      try {
        messageCfg = MessageServiceConfig.fromJson(
          Map<String, dynamic>.from(messageRaw),
        );
      } catch (_) {
        // Notification credentials are sensitive. Report only the category.
        _log.warning('Invalid market maker message service configuration');
      }
    }

    return MarketMakerBotSettings(
      isMMBotEnabled: enabled,
      saveOrdersBetweenLaunches: savedBetweenLaunches,
      botRefreshRate: refresh,
      tradeCoinPairConfigs: configs,
      messageServiceConfig: messageCfg,
    );
  }

  /// Parses persisted settings without repairing or dropping malformed data.
  ///
  /// This parser is used by authoritative read-modify-write paths. The
  /// tolerant [fromJson] parser remains appropriate for best-effort display
  /// and migration, but must never be used before writing the value back.
  factory MarketMakerBotSettings.fromJsonStrict(Map<String, dynamic>? json) {
    if (json == null) return MarketMakerBotSettings.initial();

    final enabled = _strictOptionalBool(
      json,
      'is_market_maker_bot_enabled',
      defaultValue: false,
    );
    final savedBetweenLaunches = _strictOptionalBool(
      json,
      'save_orders_between_launches',
      defaultValue: true,
    );
    final rawRefresh = json['bot_refresh_rate'];
    final refresh = rawRefresh == null ? 60 : _safeInteger(rawRefresh);
    if (refresh == null ||
        refresh < minimumBotRefreshRateSeconds ||
        refresh > maximumBotRefreshRateSeconds) {
      throw const FormatException('Invalid market maker refresh interval');
    }

    final rawConfigs = json['trade_coin_pair_configs'];
    final configs = <TradeCoinPairConfig>[];
    if (rawConfigs != null) {
      if (rawConfigs is! List ||
          rawConfigs.length > maximumTradePairConfigCount) {
        throw const FormatException(
          'Invalid market maker configuration collection',
        );
      }
      final names = <String>{};
      for (final rawConfig in rawConfigs) {
        if (rawConfig is! Map) {
          throw const FormatException('Invalid trade coin pair config');
        }
        late final TradeCoinPairConfig config;
        try {
          config = TradeCoinPairConfig.fromJson(
            Map<String, dynamic>.from(rawConfig),
          );
        } on Object {
          throw const FormatException('Invalid trade coin pair config');
        }
        if (!names.add(config.name.toUpperCase())) {
          throw const FormatException('Duplicate market maker configuration');
        }
        configs.add(config);
      }
    }

    MessageServiceConfig? messageCfg;
    final messageRaw = json['message_service_config'];
    if (messageRaw != null) {
      if (messageRaw is! Map) {
        throw const FormatException(
          'Invalid market maker message service configuration',
        );
      }
      try {
        messageCfg = MessageServiceConfig.fromJson(
          Map<String, dynamic>.from(messageRaw),
        );
      } on Object {
        throw const FormatException(
          'Invalid market maker message service configuration',
        );
      }
    }

    return MarketMakerBotSettings(
      isMMBotEnabled: enabled,
      saveOrdersBetweenLaunches: savedBetweenLaunches,
      botRefreshRate: refresh,
      tradeCoinPairConfigs: configs,
      messageServiceConfig: messageCfg,
    );
  }

  static bool _strictOptionalBool(
    Map<String, dynamic> json,
    String key, {
    required bool defaultValue,
  }) {
    final value = json[key];
    if (value == null && !json.containsKey(key)) return defaultValue;
    if (value is! bool) {
      throw const FormatException('Invalid market maker flag');
    }
    return value;
  }

  static List<TradeCoinPairConfig> _parsePersistedConfigs(Object? rawValue) {
    if (rawValue == null) return const <TradeCoinPairConfig>[];
    if (rawValue is! List || rawValue.length > maximumTradePairConfigCount) {
      _log.warning('Invalid market maker configuration collection');
      return const <TradeCoinPairConfig>[];
    }

    final byName = <String, TradeCoinPairConfig>{};
    final duplicateNames = <String>{};
    for (final rawConfig in rawValue) {
      if (rawConfig is! Map) {
        _log.warning('Invalid trade coin pair config');
        continue;
      }

      try {
        final config = TradeCoinPairConfig.fromJson(
          Map<String, dynamic>.from(rawConfig),
        );
        final canonicalName = config.name.toUpperCase();
        if (byName.containsKey(canonicalName) ||
            duplicateNames.contains(canonicalName)) {
          byName.remove(canonicalName);
          duplicateNames.add(canonicalName);
          _log.warning('Duplicate trade coin pair config');
          continue;
        }
        byName[canonicalName] = config;
      } catch (_, stackTrace) {
        // Pair IDs, strategy, volumes and spreads are commercially sensitive.
        // Do not attach the rejected map or parser error to diagnostics.
        _log.warning('Invalid trade coin pair config', null, stackTrace);
      }
    }

    return List<TradeCoinPairConfig>.unmodifiable(byName.values);
  }

  static bool? _safeBool(Object? rawValue) =>
      rawValue is bool ? rawValue : null;

  static int? _safeInteger(Object? rawValue) {
    if (rawValue is int) return rawValue;
    if (rawValue is num) {
      final value = rawValue.toDouble();
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
      return null;
    }
    if (rawValue is String &&
        rawValue.isNotEmpty &&
        rawValue.length <= 32 &&
        rawValue == rawValue.trim()) {
      return int.tryParse(rawValue);
    }
    return null;
  }

  /// Whether the Market Maker Bot is enabled (menu item is shown or not).
  final bool isMMBotEnabled;

  /// Whether maker order configs should be retained between app launches.
  final bool saveOrdersBetweenLaunches;

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
      'save_orders_between_launches': saveOrdersBetweenLaunches,
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
      'save_orders_between_launches': saveOrdersBetweenLaunches,
      // Old builds included a price_url; provide the previous default
      'price_url':
          'https://defistats.gleec.com/api/v3/prices/tickers_v2?expire_at=600',
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
    bool? saveOrdersBetweenLaunches,
    int? botRefreshRate,
    List<TradeCoinPairConfig>? tradeCoinPairConfigs,
    MessageServiceConfig? messageServiceConfig,
  }) {
    return MarketMakerBotSettings(
      isMMBotEnabled: isMMBotEnabled ?? this.isMMBotEnabled,
      saveOrdersBetweenLaunches:
          saveOrdersBetweenLaunches ?? this.saveOrdersBetweenLaunches,
      botRefreshRate: botRefreshRate ?? this.botRefreshRate,
      tradeCoinPairConfigs: tradeCoinPairConfigs ?? this.tradeCoinPairConfigs,
      messageServiceConfig: messageServiceConfig ?? this.messageServiceConfig,
    );
  }

  @override
  List<Object?> get props => [
    isMMBotEnabled,
    saveOrdersBetweenLaunches,
    botRefreshRate,
    tradeCoinPairConfigs,
    messageServiceConfig,
  ];
}
