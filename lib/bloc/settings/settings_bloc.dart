import 'package:app_theme/app_theme.dart';
import 'package:bloc/bloc.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/platform/platform.dart';
import 'package:web_dex/shared/utils/utils.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc(StoredSettings stored, SettingsRepository repository)
    : _settingsRepo = repository,
      super(SettingsState.fromStored(stored)) {
    _storedSettings = stored;
    theme.mode = state.themeMode;

    // Initialize diagnostic logging with the stored setting
    KdfLoggingConfig.verboseLogging = stored.diagnosticLoggingEnabled;
    KdfApiClient.enableDebugLogging = stored.diagnosticLoggingEnabled;
    KomodoDefiFramework.enableDebugLogging = stored.diagnosticLoggingEnabled;

    on<ThemeModeChanged>(_onThemeModeChanged);
    on<MarketMakerBotSettingsChanged>(_onMarketMakerBotSettingsChanged);
    on<TestCoinsEnabledChanged>(_onTestCoinsEnabledChanged);
    on<WeakPasswordsAllowedChanged>(_onWeakPasswordsAllowedChanged);
    on<HideZeroBalanceAssetsChanged>(_onHideZeroBalanceAssetsChanged);
    on<DiagnosticLoggingChanged>(_onDiagnosticLoggingChanged);
    on<HideBalancesChanged>(_onHideBalancesChanged);
  }

  late StoredSettings _storedSettings;
  final SettingsRepository _settingsRepo;

  Future<void> _onThemeModeChanged(
    ThemeModeChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    if (materialPageContext == null) return;
    final newMode = event.mode;
    theme.mode = newMode;
    _storedSettings = _storedSettings.copyWith(mode: newMode);
    await _settingsRepo.updateSettings(_storedSettings);
    changeHtmlTheme(newMode.index);
    emitter(state.copyWith(mode: newMode));

    rebuildAll(null);
  }

  Future<void> _onMarketMakerBotSettingsChanged(
    MarketMakerBotSettingsChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    _storedSettings = _storedSettings.copyWith(
      marketMakerBotSettings: event.settings,
    );
    await _settingsRepo.updateSettings(_storedSettings);
    emitter(state.copyWith(marketMakerBotSettings: event.settings));
  }

  Future<void> _onTestCoinsEnabledChanged(
    TestCoinsEnabledChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    _storedSettings = _storedSettings.copyWith(
      testCoinsEnabled: event.testCoinsEnabled,
    );
    await _settingsRepo.updateSettings(_storedSettings);
    emitter(state.copyWith(testCoinsEnabled: event.testCoinsEnabled));
  }

  Future<void> _onWeakPasswordsAllowedChanged(
    WeakPasswordsAllowedChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    _storedSettings = _storedSettings.copyWith(
      weakPasswordsAllowed: event.weakPasswordsAllowed,
    );
    await _settingsRepo.updateSettings(_storedSettings);
    emitter(state.copyWith(weakPasswordsAllowed: event.weakPasswordsAllowed));
  }

  Future<void> _onHideZeroBalanceAssetsChanged(
    HideZeroBalanceAssetsChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    _storedSettings = _storedSettings.copyWith(
      hideZeroBalanceAssets: event.hideZeroBalanceAssets,
    );
    await _settingsRepo.updateSettings(_storedSettings);
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

    _storedSettings = _storedSettings.copyWith(
      diagnosticLoggingEnabled: event.diagnosticLoggingEnabled,
    );
    await _settingsRepo.updateSettings(_storedSettings);
    emitter(
      state.copyWith(diagnosticLoggingEnabled: event.diagnosticLoggingEnabled),
    );
  }

  Future<void> _onHideBalancesChanged(
    HideBalancesChanged event,
    Emitter<SettingsState> emitter,
  ) async {
    _storedSettings = _storedSettings.copyWith(
      hideBalances: event.hideBalances,
    );
    await _settingsRepo.updateSettings(_storedSettings);
    emitter(state.copyWith(hideBalances: event.hideBalances));
  }
}
