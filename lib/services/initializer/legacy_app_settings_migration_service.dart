import 'package:flutter/material.dart';
import 'package:web_dex/bloc/fiat/fiat_default_preference.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/constants.dart';

const String legacyAppSettingsImportMarkerKey = 'legacy_app_settings_import_v1';
const String legacyAppSettingsExtrasKey = 'legacy_app_import_extras_v1';
const String legacyAppSettingsBackfillMarkerKey =
    'legacy_app_supported_feature_backfill_v1';

class LegacyAppSettingsMigrationService {
  LegacyAppSettingsMigrationService({
    required BaseStorage storage,
    SettingsRepository? settingsRepository,
    DateTime Function()? nowProvider,
  }) : _storage = storage,
       _settingsRepository =
           settingsRepository ?? SettingsRepository(storage: storage),
       _nowProvider = nowProvider ?? DateTime.now;

  final BaseStorage _storage;
  final SettingsRepository _settingsRepository;
  final DateTime Function() _nowProvider;

  static const Map<String, String> _preservedLegacyExtras = <String, String>{
    'selectedFiat': 'selectedFiat',
    'activeCurrency': 'activeCurrency',
    'showSoundsExplanationDialog': 'showSoundsExplanationDialog',
    'showCancelOrderDialog1': 'showCancelOrderDialog1',
    'showOrderDetailsByTap': 'showOrderDetailsByTap',
    'current_languages': 'current_languages',
    'rebrandingDialogClosedPermanently': 'rebrandingDialogClosedPermanently',
    'addressBook': 'addressBook',
  };

  Future<void> migrateIfNeeded() async {
    final markerValue = await _storage.read(legacyAppSettingsImportMarkerKey);
    if (markerValue != true) {
      await _preserveLegacyExtras();

      final hasCurrentSettingsBlob =
          await _storage.read(storedSettingsKeyV2) != null;
      if (!hasCurrentSettingsBlob) {
        final storedSettings = await SettingsRepository.loadStoredSettings(
          settingsStorage: _storage,
        );
        await _settingsRepository.updateSettings(
          await _applyLegacySupportedSettings(storedSettings),
        );
      }

      await _migrateWalletOnlyAgreementIfNeeded();
      await _storage.write(legacyAppSettingsImportMarkerKey, true);
    }

    await _backfillSupportedFeaturesIfNeeded();
  }

  Future<StoredSettings> _applyLegacySupportedSettings(
    StoredSettings settings,
  ) async {
    final legacyIsLightTheme = await _readBool('isLightTheme');
    final legacyShowBalance = await _readBool('showBalance');
    final legacyTestCoinsEnabled = await _readBool('switch_test_coins');

    return settings.copyWith(
      mode: legacyIsLightTheme == true ? ThemeMode.light : settings.mode,
      hideBalances: legacyShowBalance == null
          ? settings.hideBalances
          : !legacyShowBalance,
      testCoinsEnabled: legacyTestCoinsEnabled ?? settings.testCoinsEnabled,
    );
  }

  Future<void> _migrateWalletOnlyAgreementIfNeeded() async {
    final existingValue = await _storage.read('wallet_only_agreed');
    if (existingValue is int) {
      return;
    }

    if (existingValue == true) {
      await _storage.write(
        'wallet_only_agreed',
        _nowProvider().millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _preserveLegacyExtras() async {
    final extras = <String, dynamic>{};
    for (final entry in _preservedLegacyExtras.entries) {
      final value = await _storage.read(entry.key);
      if (value != null) {
        extras[entry.value] = value;
      }
    }

    if (extras.isEmpty) {
      await _storage.delete(legacyAppSettingsExtrasKey);
      return;
    }

    await _storage.write(legacyAppSettingsExtrasKey, extras);
  }

  Future<void> _backfillSupportedFeaturesIfNeeded() async {
    final markerValue = await _storage.read(legacyAppSettingsBackfillMarkerKey);
    if (markerValue == true) {
      return;
    }

    var extras = await _readPreservedLegacyExtras();
    if (extras.isEmpty) {
      await _preserveLegacyExtras();
      extras = await _readPreservedLegacyExtras();
    }

    await _backfillDefaultFiatPreferenceIfNeeded(extras);
    await _storage.write(legacyAppSettingsBackfillMarkerKey, true);
  }

  Future<void> _backfillDefaultFiatPreferenceIfNeeded(
    Map<String, dynamic> extras,
  ) async {
    final existingValue = await _storage.read(defaultFiatPreferenceKey);
    if (existingValue is String && existingValue.trim().isNotEmpty) {
      return;
    }

    final selectedFiat = extras['selectedFiat'];
    if (selectedFiat is! String) {
      return;
    }

    final normalized = normalizeDefaultFiatPreferenceValue(selectedFiat);
    if (normalized == null) {
      return;
    }

    await _storage.write(defaultFiatPreferenceKey, normalized);
  }

  Future<Map<String, dynamic>> _readPreservedLegacyExtras() async {
    final storedValue = await _storage.read(legacyAppSettingsExtrasKey);
    if (storedValue is Map<String, dynamic>) {
      return Map<String, dynamic>.from(storedValue);
    }
    if (storedValue is Map) {
      return storedValue.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return <String, dynamic>{};
  }

  Future<bool?> _readBool(String key) async {
    final value = await _storage.read(key);
    return value is bool ? value : null;
  }
}
