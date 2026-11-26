import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../passkey_backup_types.dart';
import 'backup_store_limits.dart';

/// Synchronizable Keychain items, which reach every Apple device on the same
/// account once iCloud Keychain syncs. The items hold sealed records only.
final class ICloudKeychainBackupStore implements BackupRecordStore {
  ICloudKeychainBackupStore({
    MethodChannel? channel,
    bool Function()? isApplePlatform,
  }) : _channel = channel ?? const MethodChannel('gleec.wallet/backup_store'),
       _isApple = isApplePlatform ?? _applePlatform;

  final MethodChannel _channel;
  final bool Function() _isApple;

  static bool _applePlatform() =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  BackupStoreKind get kind => BackupStoreKind.iCloudKeychain;

  /// Whether this build can write the items. It cannot tell whether iCloud
  /// Keychain sync is on: an item written while it is off stays here.
  @override
  Future<bool> isAvailable() async {
    if (!_isApple()) return false;
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on Object {
      return false;
    }
  }

  /// The Keychain needs no sign-in.
  @override
  Future<void> prepare() async {}

  @override
  Future<List<StoredBackup>> list() async {
    final items = await _invoke<Object?>('list');
    if (items is! List) {
      throw const PasskeyBackupException(PasskeyBackupFailure.storageFailed);
    }
    final found = <String, StoredBackup>{};
    for (final item in items) {
      final backup = _parse(item);
      if (backup != null) found.putIfAbsent(backup.id, () => backup);
    }
    return found.values.toList();
  }

  /// An item another build wrote, or one damaged in sync, is skipped: it
  /// must not hide the records that are readable.
  StoredBackup? _parse(Object? item) {
    if (item is! Map) return null;
    final id = item['id'];
    final data = item['data'];
    if (!isBackupId(id) ||
        data is! Uint8List ||
        data.isEmpty ||
        data.length > maxBackupRecordBytes) {
      return null;
    }
    final String raw;
    try {
      raw = utf8.decode(data);
    } on FormatException {
      return null;
    }
    return StoredBackup(
      id: id as String,
      store: kind,
      created: backupCreatedHint(raw),
      raw: raw,
    );
  }

  @override
  Future<void> write(String id, String raw) async {
    final data = backupRecordBytes(id, raw);
    await _invoke<void>('write', {'id': id, 'data': data});
  }

  @override
  Future<void> delete(String id) async {
    if (!isBackupId(id)) {
      throw const PasskeyBackupException(PasskeyBackupFailure.storageFailed);
    }
    await _invoke<void>('delete', {'id': id});
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!_isApple()) {
      throw const PasskeyBackupException(PasskeyBackupFailure.storeUnavailable);
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const PasskeyBackupException(PasskeyBackupFailure.storeUnavailable);
    } on PlatformException catch (error) {
      throw PasskeyBackupException(
        error.code == 'unavailable'
            ? PasskeyBackupFailure.storeUnavailable
            : PasskeyBackupFailure.storageFailed,
      );
    }
  }
}
