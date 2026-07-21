import 'package:flutter/material.dart';
import 'package:web_dex/model/settings/analytics_settings.dart';
import 'package:web_dex/model/settings/market_maker_bot_settings.dart';
import 'package:web_dex/shared/constants.dart';

class StoredSettings {
  StoredSettings({
    required this.mode,
    required this.analytics,
    required this.marketMakerBotSettings,
    required this.testCoinsEnabled,
    required this.weakPasswordsAllowed,
    required this.hideZeroBalanceAssets,
    required this.diagnosticLoggingEnabled,
    required this.hideBalances,
  });

  final ThemeMode mode;
  final AnalyticsSettings analytics;
  final MarketMakerBotSettings marketMakerBotSettings;
  final bool testCoinsEnabled;
  final bool weakPasswordsAllowed;
  final bool hideZeroBalanceAssets;
  final bool diagnosticLoggingEnabled;
  final bool hideBalances;

  static StoredSettings initial() {
    return StoredSettings(
      mode: ThemeMode.dark,
      analytics: AnalyticsSettings.initial(),
      marketMakerBotSettings: MarketMakerBotSettings.initial(),
      testCoinsEnabled: true,
      weakPasswordsAllowed: false,
      hideZeroBalanceAssets: false,
      diagnosticLoggingEnabled: false,
      hideBalances: false,
    );
  }

  factory StoredSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return StoredSettings.initial();

    return StoredSettings(
      mode: ThemeMode.values[json['themeModeIndex']],
      analytics: AnalyticsSettings.fromJson(json[storedAnalyticsSettingsKey]),
      marketMakerBotSettings: MarketMakerBotSettings.fromJson(
        json[storedMarketMakerSettingsKey],
      ),
      testCoinsEnabled: json['testCoinsEnabled'] ?? true,
      weakPasswordsAllowed: json['weakPasswordsAllowed'] ?? false,
      hideZeroBalanceAssets: json['hideZeroBalanceAssets'] ?? false,
      diagnosticLoggingEnabled: json['diagnosticLoggingEnabled'] ?? false,
      hideBalances: json['hideBalances'] ?? false,
    );
  }

  /// Strict parser for settings that will participate in an authoritative
  /// read-modify-write transaction. Present malformed values are rejected
  /// instead of being defaulted, skipped, or silently repaired.
  factory StoredSettings.fromJsonStrict(Map<String, dynamic>? json) {
    if (json == null) return StoredSettings.initial();

    final rawThemeMode = json['themeModeIndex'];
    final themeModeIndex = rawThemeMode ?? ThemeMode.dark.index;
    if (themeModeIndex is! int ||
        themeModeIndex < 0 ||
        themeModeIndex >= ThemeMode.values.length) {
      throw const FormatException('Invalid stored theme mode');
    }

    final rawAnalytics = json[storedAnalyticsSettingsKey];
    AnalyticsSettings analytics;
    if (rawAnalytics == null) {
      analytics = AnalyticsSettings.initial();
    } else {
      if (rawAnalytics is! Map) {
        throw const FormatException('Invalid analytics settings');
      }
      final analyticsJson = Map<String, dynamic>.from(rawAnalytics);
      final sendAllowed = analyticsJson['send_allowed'];
      if (sendAllowed != null && sendAllowed is! bool) {
        throw const FormatException('Invalid analytics setting');
      }
      analytics = AnalyticsSettings(
        isSendAllowed: sendAllowed is bool ? sendAllowed : true,
      );
    }

    final rawMarketMaker = json[storedMarketMakerSettingsKey];
    if (rawMarketMaker != null && rawMarketMaker is! Map) {
      throw const FormatException('Invalid market maker settings');
    }
    final marketMaker = MarketMakerBotSettings.fromJsonStrict(
      rawMarketMaker == null
          ? null
          : Map<String, dynamic>.from(rawMarketMaker as Map),
    );

    bool strictBool(String key, bool defaultValue) {
      final value = json[key];
      if (value == null && !json.containsKey(key)) return defaultValue;
      if (value is! bool) {
        throw const FormatException('Invalid stored boolean setting');
      }
      return value;
    }

    return StoredSettings(
      mode: ThemeMode.values[themeModeIndex],
      analytics: analytics,
      marketMakerBotSettings: marketMaker,
      testCoinsEnabled: strictBool('testCoinsEnabled', true),
      weakPasswordsAllowed: strictBool('weakPasswordsAllowed', false),
      hideZeroBalanceAssets: strictBool('hideZeroBalanceAssets', false),
      diagnosticLoggingEnabled: strictBool('diagnosticLoggingEnabled', false),
      hideBalances: strictBool('hideBalances', false),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'themeModeIndex': mode.index,
      storedAnalyticsSettingsKey: analytics.toJson(),
      storedMarketMakerSettingsKey: marketMakerBotSettings.toJson(),
      'testCoinsEnabled': testCoinsEnabled,
      'weakPasswordsAllowed': weakPasswordsAllowed,
      'hideZeroBalanceAssets': hideZeroBalanceAssets,
      'diagnosticLoggingEnabled': diagnosticLoggingEnabled,
      'hideBalances': hideBalances,
    };
  }

  // Legacy representation kept for backward-compatible writes to
  // shared_preferences.json so older app versions can still parse it.
  Map<String, dynamic> toLegacyJson() {
    return <String, dynamic>{
      'themeModeIndex': mode.index,
      storedAnalyticsSettingsKey: analytics.toJson(),
      storedMarketMakerSettingsKey: marketMakerBotSettings.toLegacyJson(),
      'testCoinsEnabled': testCoinsEnabled,
      'weakPasswordsAllowed': weakPasswordsAllowed,
      'hideZeroBalanceAssets': hideZeroBalanceAssets,
      'hideBalances': hideBalances,
    };
  }

  StoredSettings copyWith({
    ThemeMode? mode,
    AnalyticsSettings? analytics,
    MarketMakerBotSettings? marketMakerBotSettings,
    bool? testCoinsEnabled,
    bool? weakPasswordsAllowed,
    bool? hideZeroBalanceAssets,
    bool? diagnosticLoggingEnabled,
    bool? hideBalances,
  }) {
    return StoredSettings(
      mode: mode ?? this.mode,
      analytics: analytics ?? this.analytics,
      marketMakerBotSettings:
          marketMakerBotSettings ?? this.marketMakerBotSettings,
      testCoinsEnabled: testCoinsEnabled ?? this.testCoinsEnabled,
      weakPasswordsAllowed: weakPasswordsAllowed ?? this.weakPasswordsAllowed,
      hideZeroBalanceAssets:
          hideZeroBalanceAssets ?? this.hideZeroBalanceAssets,
      diagnosticLoggingEnabled:
          diagnosticLoggingEnabled ?? this.diagnosticLoggingEnabled,
      hideBalances: hideBalances ?? this.hideBalances,
    );
  }
}
