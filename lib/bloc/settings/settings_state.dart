import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/model/settings/market_maker_bot_settings.dart';
import 'package:web_dex/model/stored_settings.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.themeMode,
    required this.mmBotSettings,
    required this.testCoinsEnabled,
    required this.weakPasswordsAllowed,
    required this.hideZeroBalanceAssets,
    required this.diagnosticLoggingEnabled,
    required this.hideBalances,
    this.customKdfCoinsLabel,
    this.customCoinsConfigLabel,
  });

  factory SettingsState.fromStored(StoredSettings stored) {
    return SettingsState(
      themeMode: stored.mode,
      mmBotSettings: stored.marketMakerBotSettings,
      testCoinsEnabled: stored.testCoinsEnabled,
      weakPasswordsAllowed: stored.weakPasswordsAllowed,
      hideZeroBalanceAssets: stored.hideZeroBalanceAssets,
      diagnosticLoggingEnabled: stored.diagnosticLoggingEnabled,
      hideBalances: stored.hideBalances,
      customKdfCoinsLabel: stored.customKdfCoinsLabel,
      customCoinsConfigLabel: stored.customCoinsConfigLabel,
    );
  }

  final ThemeMode themeMode;
  final MarketMakerBotSettings mmBotSettings;
  final bool testCoinsEnabled;
  final bool weakPasswordsAllowed;
  final bool hideZeroBalanceAssets;
  final bool diagnosticLoggingEnabled;
  final bool hideBalances;
  final String? customKdfCoinsLabel;
  final String? customCoinsConfigLabel;

  @override
  List<Object?> get props => [
    themeMode,
    mmBotSettings,
    testCoinsEnabled,
    weakPasswordsAllowed,
    hideZeroBalanceAssets,
    diagnosticLoggingEnabled,
    hideBalances,
    customKdfCoinsLabel,
    customCoinsConfigLabel,
  ];

  SettingsState copyWith({
    ThemeMode? mode,
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
    return SettingsState(
      themeMode: mode ?? themeMode,
      mmBotSettings: marketMakerBotSettings ?? mmBotSettings,
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
