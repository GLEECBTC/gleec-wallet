import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/settings/market_maker_bot_settings.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/platform/platform.dart';
import 'package:web_dex/shared/utils/utils.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc(StoredSettings stored, SettingsRepository repository)
    : _settingsRepo = repository,
      super(SettingsState.fromStored(stored)) {
    theme.mode = state.themeMode;

    // Initialize diagnostic logging with the stored setting
    KdfLoggingConfig.verboseLogging = stored.diagnosticLoggingEnabled;
    KdfApiClient.enableDebugLogging = stored.diagnosticLoggingEnabled;
    KomodoDefiFramework.enableDebugLogging = stored.diagnosticLoggingEnabled;

    on<SettingsEvent>(_onEvent, transformer: sequential());
    _settingsSubscription = _settingsRepo.watchSettings().listen((settings) {
      if (!isClosed) add(SettingsSnapshotChanged(settings));
    });
  }

  final SettingsRepository _settingsRepo;
  StreamSubscription<StoredSettings>? _settingsSubscription;

  Future<void> updateMarketMakerBotSettingsAndWait(
    MarketMakerBotSettings Function(MarketMakerBotSettings current) transform, {
    Future<void> Function()? beforeWrite,
  }) {
    final completion = Completer<void>();
    add(
      MarketMakerBotSettingsChanged(
        transform,
        completion: completion,
        beforeWrite: beforeWrite,
      ),
    );
    return completion.future;
  }

  Future<void> _onEvent(
    SettingsEvent event,
    Emitter<SettingsState> emitter,
  ) async {
    switch (event) {
      case SettingsSnapshotChanged():
        emitter(SettingsState.fromStored(event.settings));
      case ThemeModeChanged():
        await _onThemeModeChanged(event, emitter);
      case MarketMakerBotSettingsChanged():
        await _onMarketMakerBotSettingsChanged(event, emitter);
      case TestCoinsEnabledChanged():
        await _onTestCoinsEnabledChanged(event, emitter);
      case WeakPasswordsAllowedChanged():
        await _onWeakPasswordsAllowedChanged(event, emitter);
      case HideZeroBalanceAssetsChanged():
        await _onHideZeroBalanceAssetsChanged(event, emitter);
      case DiagnosticLoggingChanged():
        await _onDiagnosticLoggingChanged(event, emitter);
      case HideBalancesChanged():
        await _onHideBalancesChanged(event, emitter);
    }
  }

  @override
  Future<void> close() async {
    await _settingsSubscription?.cancel();
    return super.close();
  }

  Future<void> _onThemeModeChanged(
    ThemeModeChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    if (materialPageContext == null) return;
    final newMode = event.mode;
    theme.mode = newMode;
    await _settingsRepo.updateSettingsWith(
      (current) => current.copyWith(mode: newMode),
    );
    changeHtmlTheme(newMode.index);
    emitter(state.copyWith(mode: newMode));

    rebuildAll(null);
  }

  Future<void> _onMarketMakerBotSettingsChanged(
    MarketMakerBotSettingsChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    try {
      final updated = await _settingsRepo.updateSettingsWith(
        (current) => current.copyWith(
          marketMakerBotSettings: event.transform(
            current.marketMakerBotSettings,
          ),
        ),
        beforeWrite: event.beforeWrite,
      );
      final nextSettings = updated.marketMakerBotSettings;
      emitter(state.copyWith(marketMakerBotSettings: nextSettings));
      if (event.completion case final completion?
          when !completion.isCompleted) {
        completion.complete();
      }
    } catch (error, stackTrace) {
      final completion = event.completion;
      if (completion != null && !completion.isCompleted) {
        completion.completeError(error, stackTrace);
        return;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _onTestCoinsEnabledChanged(
    TestCoinsEnabledChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    await _settingsRepo.updateSettingsWith(
      (current) => current.copyWith(testCoinsEnabled: event.testCoinsEnabled),
    );
    emitter(state.copyWith(testCoinsEnabled: event.testCoinsEnabled));
  }

  Future<void> _onWeakPasswordsAllowedChanged(
    WeakPasswordsAllowedChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    await _settingsRepo.updateSettingsWith(
      (current) =>
          current.copyWith(weakPasswordsAllowed: event.weakPasswordsAllowed),
    );
    emitter(state.copyWith(weakPasswordsAllowed: event.weakPasswordsAllowed));
  }

  Future<void> _onHideZeroBalanceAssetsChanged(
    HideZeroBalanceAssetsChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    await _settingsRepo.updateSettingsWith(
      (current) =>
          current.copyWith(hideZeroBalanceAssets: event.hideZeroBalanceAssets),
    );
    emitter(state.copyWith(hideZeroBalanceAssets: event.hideZeroBalanceAssets));
  }

  Future<void> _onDiagnosticLoggingChanged(
    DiagnosticLoggingChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    // Update all diagnostic logging flags immediately
    KdfLoggingConfig.verboseLogging = event.diagnosticLoggingEnabled;
    KdfApiClient.enableDebugLogging = event.diagnosticLoggingEnabled;
    KomodoDefiFramework.enableDebugLogging = event.diagnosticLoggingEnabled;

    await _settingsRepo.updateSettingsWith(
      (current) => current.copyWith(
        diagnosticLoggingEnabled: event.diagnosticLoggingEnabled,
      ),
    );
    emitter(
      state.copyWith(diagnosticLoggingEnabled: event.diagnosticLoggingEnabled),
    );
  }

  Future<void> _onHideBalancesChanged(
    HideBalancesChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    await _settingsRepo.updateSettingsWith(
      (current) => current.copyWith(hideBalances: event.hideBalances),
    );
    emitter(state.copyWith(hideBalances: event.hideBalances));
  }
}
