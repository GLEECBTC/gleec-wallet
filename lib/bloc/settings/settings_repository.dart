import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/services/storage/get_storage.dart';
import 'package:web_dex/shared/constants.dart';

class SettingsRepository {
  SettingsRepository({BaseStorage? storage})
    : _storage = storage ?? getStorage();

  final BaseStorage _storage;
  final StreamController<StoredSettings> _settingsChanges =
      StreamController<StoredSettings>.broadcast(sync: true);
  static final _log = Logger('SettingsRepository');
  static Future<void> _mutationTail = Future<void>.value();

  Future<StoredSettings> loadSettings() async {
    return loadStoredSettings(settingsStorage: _storage);
  }

  /// Loads settings without substituting defaults for corrupt or unreadable
  /// storage. Authoritative trading/configuration paths must use this variant.
  Future<StoredSettings> loadSettingsStrict() async {
    final dynamic v2 = await _storage.read(storedSettingsKeyV2);
    if (v2 != null) {
      if (v2 is! Map<String, dynamic>) {
        throw const FormatException('Invalid stored settings');
      }
      return StoredSettings.fromJsonStrict(v2);
    }

    final dynamic legacy = await _storage.read(storedSettingsKey);
    if (legacy == null) return StoredSettings.initial();
    if (legacy is! Map<String, dynamic>) {
      throw const FormatException('Invalid legacy settings');
    }
    return StoredSettings.fromJsonStrict(legacy);
  }

  Stream<StoredSettings> watchSettings() => _settingsChanges.stream;

  Future<void> updateSettings(StoredSettings settings) {
    return _serializeMutation(() => _writeSettings(settings));
  }

  /// Atomically reloads, transforms, and persists the latest settings snapshot.
  ///
  /// Every repository instance shares the same mutation queue because the app
  /// creates several adapters over the same storage. This prevents one feature
  /// from writing an old full snapshot over a newer Market Maker configuration.
  Future<StoredSettings> updateSettingsWith(
    StoredSettings Function(StoredSettings current) transform, {
    Future<void> Function()? beforeWrite,
  }) {
    return _serializeMutation(() async {
      final current = await loadSettingsStrict();
      final updated = transform(current);
      await beforeWrite?.call();
      await _writeSettings(updated);
      return updated;
    });
  }

  Future<void> _writeSettings(StoredSettings settings) async {
    // The legacy mirror is written first. The canonical V2 key is the commit
    // point for this app version and is never changed if the mirror fails.
    final previousLegacy = await _storage.read(storedSettingsKey);
    final String legacyData = jsonEncode(settings.toLegacyJson());
    if (!await _storage.write(storedSettingsKey, legacyData)) {
      throw StateError('Unable to persist legacy settings mirror');
    }

    final String v2Data = jsonEncode(settings.toJson());
    if (!await _storage.write(storedSettingsKeyV2, v2Data)) {
      final restored = previousLegacy == null
          ? await _storage.delete(storedSettingsKey)
          : await _storage.write(storedSettingsKey, jsonEncode(previousLegacy));
      if (!restored) {
        throw StateError(
          'Unable to persist canonical settings or restore legacy mirror',
        );
      }
      throw StateError('Unable to persist canonical settings');
    }
    if (!_settingsChanges.isClosed) _settingsChanges.add(settings);
  }

  Future<T> _serializeMutation<T>(Future<T> Function() mutation) {
    final scheduled = _mutationTail.then((_) => mutation());
    _mutationTail = scheduled.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return scheduled;
  }

  Future<void> dispose() => _settingsChanges.close();

  static Future<StoredSettings> loadStoredSettings({
    BaseStorage? settingsStorage,
  }) async {
    final storage = settingsStorage ?? getStorage();
    try {
      // Prefer V2 settings if present
      final dynamic v2 = await storage.read(storedSettingsKeyV2);
      if (v2 is Map<String, dynamic>) {
        return StoredSettings.fromJson(v2);
      }

      // Fallback to legacy key
      final dynamic legacy = await storage.read(storedSettingsKey);
      return StoredSettings.fromJson(
        legacy is Map<String, dynamic> ? legacy : null,
      );
    } catch (e, stackTrace) {
      _log.warning(
        'Failed to load stored settings, returning initial settings',
        e,
        stackTrace,
      );
      return StoredSettings.initial();
    }
  }
}
