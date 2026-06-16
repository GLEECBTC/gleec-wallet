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
    this.customKdfCoinsLabel,
    this.customCoinsConfigLabel,
  });

  final ThemeMode mode;
  final AnalyticsSettings analytics;
  final MarketMakerBotSettings marketMakerBotSettings;
  final bool testCoinsEnabled;
  final bool weakPasswordsAllowed;
  final bool hideZeroBalanceAssets;
  final bool diagnosticLoggingEnabled;
  final bool hideBalances;

  /// Display label (file path on native, file name on web) for the custom KDF
  /// coins file override, or `null` when the bundled config is used. The
  /// authoritative override is persisted by the SDK; this is for UI display and
  /// to pre-populate the file picker's starting directory.
  final String? customKdfCoinsLabel;

  /// Display label for the custom coins-config file override, or `null` when
  /// the bundled config is used. See [customKdfCoinsLabel].
  final String? customCoinsConfigLabel;

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
      customKdfCoinsLabel: json['customKdfCoinsLabel'] as String?,
      customCoinsConfigLabel: json['customCoinsConfigLabel'] as String?,
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
      if (customKdfCoinsLabel != null)
        'customKdfCoinsLabel': customKdfCoinsLabel,
      if (customCoinsConfigLabel != null)
        'customCoinsConfigLabel': customCoinsConfigLabel,
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
    String? customKdfCoinsLabel,
    String? customCoinsConfigLabel,
    bool clearCustomCoinsLabels = false,
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
      customKdfCoinsLabel: clearCustomCoinsLabels
          ? null
          : (customKdfCoinsLabel ?? this.customKdfCoinsLabel),
      customCoinsConfigLabel: clearCustomCoinsLabels
          ? null
          : (customCoinsConfigLabel ?? this.customCoinsConfigLabel),
    );
  }
}
