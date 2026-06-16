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
    this.customKdfCoinsFileName,
    this.customCoinsConfigFileName,
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
      customKdfCoinsFileName: stored.customKdfCoinsFileName,
      customCoinsConfigFileName: stored.customCoinsConfigFileName,
    );
  }

  final ThemeMode themeMode;
  final MarketMakerBotSettings mmBotSettings;
  final bool testCoinsEnabled;
  final bool weakPasswordsAllowed;
  final bool hideZeroBalanceAssets;
  final bool diagnosticLoggingEnabled;
  final bool hideBalances;
  final String? customKdfCoinsFileName;
  final String? customCoinsConfigFileName;

  @override
  List<Object?> get props => [
    themeMode,
    mmBotSettings,
    testCoinsEnabled,
    weakPasswordsAllowed,
    hideZeroBalanceAssets,
    diagnosticLoggingEnabled,
    hideBalances,
    customKdfCoinsFileName,
    customCoinsConfigFileName,
  ];

  SettingsState copyWith({
    ThemeMode? mode,
    MarketMakerBotSettings? marketMakerBotSettings,
    bool? testCoinsEnabled,
    bool? weakPasswordsAllowed,
    bool? hideZeroBalanceAssets,
    bool? diagnosticLoggingEnabled,
    bool? hideBalances,
    String? customKdfCoinsFileName,
    String? customCoinsConfigFileName,
    bool clearCustomCoinsFileNames = false,
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
      customKdfCoinsFileName: clearCustomCoinsFileNames
          ? null
          : (customKdfCoinsFileName ?? this.customKdfCoinsFileName),
      customCoinsConfigFileName: clearCustomCoinsFileNames
          ? null
          : (customCoinsConfigFileName ?? this.customCoinsConfigFileName),
    );
  }
}
