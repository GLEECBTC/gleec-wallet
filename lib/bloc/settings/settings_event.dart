import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/model/settings/market_maker_bot_settings.dart';
import 'package:web_dex/model/stored_settings.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object> get props => [];
}

class SettingsSnapshotChanged extends SettingsEvent {
  const SettingsSnapshotChanged(this.settings);

  final StoredSettings settings;

  @override
  List<Object> get props => [settings];
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
  const MarketMakerBotSettingsChanged(
    this.transform, {
    this.completion,
    this.beforeWrite,
  });

  /// Applied only when this event reaches the globally sequential settings
  /// queue, so an older UI snapshot cannot overwrite a newer MM-bot field.
  final MarketMakerBotSettings Function(MarketMakerBotSettings current)
  transform;
  final Completer<void>? completion;
  final Future<void> Function()? beforeWrite;

  @override
  List<Object> get props => [
    transform,
    if (completion != null) completion!,
    if (beforeWrite != null) beforeWrite!,
  ];
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
