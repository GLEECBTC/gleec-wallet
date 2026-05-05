import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/services/initializer/legacy_app_settings_migration_service.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/constants.dart';

void main() {
  group('LegacyAppSettingsMigrationService', () {
    test('imports supported globals and preserves legacy extras', () async {
      final storage = _JsonAwareFakeStorage(
        initialData: <String, dynamic>{
          'isLightTheme': true,
          'showBalance': false,
          'switch_test_coins': false,
          'wallet_only_agreed': true,
          'selectedFiat': 'USD',
          'activeCurrency': 'usd',
          'showSoundsExplanationDialog': false,
          'showCancelOrderDialog1': true,
          'showOrderDetailsByTap': false,
          'current_languages': <String>['en', 'fr'],
          'rebrandingDialogClosedPermanently': true,
          'addressBook': <String, dynamic>{'Alice': 'R123'},
          'cachedNews': <String>['ignore'],
          'camera_denied_by_user': true,
        },
      );
      final service = LegacyAppSettingsMigrationService(
        storage: storage,
        nowProvider: () => DateTime.utc(2026, 4, 10, 9, 30),
      );

      await service.migrateIfNeeded();

      final settings = await SettingsRepository.loadStoredSettings(
        settingsStorage: storage,
      );
      expect(settings.mode, ThemeMode.light);
      expect(settings.hideBalances, isTrue);
      expect(settings.testCoinsEnabled, isFalse);
      expect(await storage.read('wallet_only_agreed'), 1775813400000);
      expect(await storage.read(legacyAppSettingsImportMarkerKey), isTrue);
      expect(await storage.read(legacyAppSettingsBackfillMarkerKey), isTrue);
      expect(await storage.read(defaultFiatPreferenceKey), 'USD');
      expect(await storage.read(legacyAppSettingsExtrasKey), <String, dynamic>{
        'selectedFiat': 'USD',
        'activeCurrency': 'usd',
        'showSoundsExplanationDialog': false,
        'showCancelOrderDialog1': true,
        'showOrderDetailsByTap': false,
        'current_languages': <String>['en', 'fr'],
        'rebrandingDialogClosedPermanently': true,
        'addressBook': <String, dynamic>{'Alice': 'R123'},
      });
      expect(
        (await storage.read(legacyAppSettingsExtrasKey))['cachedNews'],
        isNull,
      );
    });

    test('does not overwrite existing current settings blob', () async {
      final existingSettings = StoredSettings.initial().copyWith(
        mode: ThemeMode.dark,
        hideBalances: false,
        testCoinsEnabled: true,
      );
      final storage = _JsonAwareFakeStorage(
        initialData: <String, dynamic>{
          storedSettingsKeyV2: jsonEncode(existingSettings.toJson()),
          'isLightTheme': true,
          'showBalance': false,
          'switch_test_coins': false,
          'wallet_only_agreed': true,
          'selectedFiat': 'EUR',
        },
      );
      final service = LegacyAppSettingsMigrationService(
        storage: storage,
        nowProvider: () => DateTime.utc(2026, 4, 10),
      );

      await service.migrateIfNeeded();

      final settings = await SettingsRepository.loadStoredSettings(
        settingsStorage: storage,
      );
      expect(settings.mode, ThemeMode.dark);
      expect(settings.hideBalances, isFalse);
      expect(settings.testCoinsEnabled, isTrue);
      expect(await storage.read(legacyAppSettingsExtrasKey), <String, dynamic>{
        'selectedFiat': 'EUR',
      });
      expect(await storage.read(legacyAppSettingsImportMarkerKey), isTrue);
      expect(await storage.read(legacyAppSettingsBackfillMarkerKey), isTrue);
      expect(await storage.read(defaultFiatPreferenceKey), 'EUR');
    });

    test('is idempotent after the import marker is set', () async {
      final storage = _JsonAwareFakeStorage(
        initialData: <String, dynamic>{
          'isLightTheme': true,
          'showBalance': false,
          'selectedFiat': 'USD',
        },
      );
      final service = LegacyAppSettingsMigrationService(storage: storage);

      await service.migrateIfNeeded();
      await storage.write('isLightTheme', false);
      await storage.write('showBalance', true);
      await storage.write('selectedFiat', 'EUR');

      await service.migrateIfNeeded();

      final settings = await SettingsRepository.loadStoredSettings(
        settingsStorage: storage,
      );
      expect(settings.mode, ThemeMode.light);
      expect(settings.hideBalances, isTrue);
      expect(await storage.read(legacyAppSettingsExtrasKey), <String, dynamic>{
        'selectedFiat': 'USD',
      });
      expect(await storage.read(defaultFiatPreferenceKey), 'USD');
      expect(await storage.read(legacyAppSettingsBackfillMarkerKey), isTrue);
    });

    test(
      'backfills supported features from preserved extras when the base import marker is already set',
      () async {
        final storage = _JsonAwareFakeStorage(
          initialData: <String, dynamic>{
            legacyAppSettingsImportMarkerKey: true,
            legacyAppSettingsExtrasKey: <String, dynamic>{
              'selectedFiat': 'EUR',
              'activeCurrency': 'usd',
              'current_languages': <String>['en', 'fr'],
            },
          },
        );
        final service = LegacyAppSettingsMigrationService(storage: storage);

        await service.migrateIfNeeded();

        expect(await storage.read(defaultFiatPreferenceKey), 'EUR');
        expect(await storage.read(legacyAppSettingsBackfillMarkerKey), isTrue);
        expect(
          await storage.read(legacyAppSettingsExtrasKey),
          <String, dynamic>{
            'selectedFiat': 'EUR',
            'activeCurrency': 'usd',
            'current_languages': <String>['en', 'fr'],
          },
        );
      },
    );

    test(
      'skips the default fiat backfill when the preserved legacy fiat is unsupported',
      () async {
        final storage = _JsonAwareFakeStorage(
          initialData: <String, dynamic>{
            legacyAppSettingsImportMarkerKey: true,
            legacyAppSettingsExtrasKey: <String, dynamic>{
              'selectedFiat': 'XYZ',
              'activeCurrency': 'usd',
            },
          },
        );
        final service = LegacyAppSettingsMigrationService(storage: storage);

        await service.migrateIfNeeded();

        expect(await storage.read(defaultFiatPreferenceKey), isNull);
        expect(await storage.read(legacyAppSettingsBackfillMarkerKey), isTrue);
        expect(
          await storage.read(legacyAppSettingsExtrasKey),
          <String, dynamic>{'selectedFiat': 'XYZ', 'activeCurrency': 'usd'},
        );
      },
    );
  });
}

class _JsonAwareFakeStorage implements BaseStorage {
  _JsonAwareFakeStorage({Map<String, dynamic>? initialData})
    : _values = initialData ?? <String, dynamic>{};

  final Map<String, dynamic> _values;

  @override
  Future<bool> delete(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<dynamic> read(String key) async {
    final value = _values[key];
    if (value is String) {
      try {
        return jsonDecode(value);
      } on FormatException {
        return value;
      }
    }
    return value;
  }

  @override
  Future<bool> write(String key, dynamic data) async {
    _values[key] = data;
    return true;
  }
}
