import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/model/settings/market_maker_bot_settings.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object> get props => [];
}

class ThemeModeChanged extends SettingsEvent {
  const ThemeModeChanged({required this.mode});
  final ThemeMode mode;
}

class TestCoinsEnabledChanged extends SettingsEvent {
  const TestCoinsEnabledChanged({required this.testCoinsEnabled});
  final bool testCoinsEnabled;
}

class MarketMakerBotSettingsChanged extends SettingsEvent {
  const MarketMakerBotSettingsChanged(this.settings);

  final MarketMakerBotSettings settings;

  @override
  List<Object> get props => [settings];
}

class WeakPasswordsAllowedChanged extends SettingsEvent {
  const WeakPasswordsAllowedChanged({required this.weakPasswordsAllowed});
  final bool weakPasswordsAllowed;

  @override
  List<Object> get props => [weakPasswordsAllowed];
}

class HideZeroBalanceAssetsChanged extends SettingsEvent {
  const HideZeroBalanceAssetsChanged({required this.hideZeroBalanceAssets});
  final bool hideZeroBalanceAssets;
}

class DiagnosticLoggingChanged extends SettingsEvent {
  const DiagnosticLoggingChanged({required this.diagnosticLoggingEnabled});
  final bool diagnosticLoggingEnabled;

  @override
  List<Object> get props => [diagnosticLoggingEnabled];
}

class HideBalancesChanged extends SettingsEvent {
  const HideBalancesChanged({required this.hideBalances});
  final bool hideBalances;

  @override
  List<Object> get props => [hideBalances];
}
