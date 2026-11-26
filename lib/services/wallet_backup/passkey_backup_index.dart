import 'dart:convert';

import 'package:mutex/mutex.dart';
import 'package:web_dex/services/storage/base_storage.dart';

import 'passkey_backup_types.dart';
import 'stores/backup_store_limits.dart';

/// Every change rewrites the whole map, so changes take turns.
final _indexLock = Mutex();

/// The backups this device made, by wallet: metadata, and a copy of each
/// sealed record so a file can still be saved when its store is out of
/// reach. Nothing here is secret: a copy opens only with its passkey.
final class PasskeyBackupIndex {
  PasskeyBackupIndex({required this._storage});

  static const storageKey = 'wallet_passkey_backups_v1';

  final BaseStorage _storage;

  Future<List<PasskeyBackupEntry>> entriesFor(String walletKey) async => [
    for (final item in (await _items()).values)
      if (item.entry.walletKey == walletKey) item.entry,
  ]..sort((a, b) => b.created.compareTo(a.created));

  Future<PasskeyBackupEntry?> entry(String id) async =>
      (await _items())[id]?.entry;

  /// The sealed record as created, or null when this device has none.
  Future<String?> record(String id) async => (await _items())[id]?.record;

  /// The records of every wallet's backups on this device.
  Future<List<String>> records() async => [
    for (final item in (await _items()).values) item.record,
  ];

  Future<void> save(PasskeyBackupEntry entry, String record) =>
      _change((stored) {
        stored[entry.id] = _Item(entry, record).toJson();
        return true;
      });

  /// Leaves the index as it is when [id] has been removed meanwhile. A check
  /// finishes an unfinished backup: its stored copy just opened.
  Future<void> markChecked(String id, DateTime when) => _change((stored) {
    final current = _Item.tryParse(id, stored[id]);
    if (current == null) return false;
    final state = current.entry.state == PasskeyBackupEntryState.unfinished
        ? PasskeyBackupEntryState.ready
        : current.entry.state;
    stored[id] = current
        .copyWith(checkedHere: when.toUtc(), state: state)
        .toJson();
    return true;
  });

  /// The user saved this file backup somewhere.
  Future<void> markFileSaved(String id) => _change((stored) {
    final current = _Item.tryParse(id, stored[id]);
    if (current == null ||
        current.entry.state != PasskeyBackupEntryState.fileNotSaved) {
      return false;
    }
    stored[id] = current
        .copyWith(state: PasskeyBackupEntryState.ready)
        .toJson();
    return true;
  });

  Future<void> remove(String id) =>
      _change((stored) => stored.remove(id) != null);

  /// Every entry this build can read. One it cannot is skipped, and left as
  /// stored by every change: it may belong to a later build.
  Future<Map<String, _Item>> _items() async {
    final stored = await _stored() ?? const <String, dynamic>{};
    return {
      for (final MapEntry(:key, :value) in stored.entries)
        if (_Item.tryParse(key, value) case final item?) key: item,
    };
  }

  /// Null when the index as a whole cannot be read, which no change may
  /// overwrite.
  Future<Map<String, dynamic>?> _stored() async {
    try {
      final raw = await _storage.read(storageKey);
      if (raw == null) return {};
      final map = raw is String ? jsonDecode(raw) : raw;
      return map is Map ? Map<String, dynamic>.from(map) : null;
    } on Object {
      return null;
    }
  }

  /// [apply] edits the stored map and returns whether it changed anything.
  Future<void> _change(bool Function(Map<String, dynamic> stored) apply) =>
      _indexLock.protect(() async {
        final stored = await _stored();
        if (stored == null) throw _storageFailed;
        if (!apply(stored)) return;
        try {
          if (await _storage.write(storageKey, stored) &&
              jsonEncode(await _storage.read(storageKey)) ==
                  jsonEncode(stored)) {
            return;
          }
        } on Object {
          // Reported below, like a write the storage refused.
        }
        throw _storageFailed;
      });

  static const _storageFailed = PasskeyBackupException(
    PasskeyBackupFailure.storageFailed,
  );
}

final class _Item {
  const _Item(this.entry, this.record);

  static const _version = 1;

  final PasskeyBackupEntry entry;
  final String record;

  _Item copyWith({DateTime? checkedHere, PasskeyBackupEntryState? state}) =>
      _Item(
        PasskeyBackupEntry(
          id: entry.id,
          walletKey: entry.walletKey,
          store: entry.store,
          created: entry.created,
          synced: entry.synced,
          providerName: entry.providerName,
          checkedHere: checkedHere ?? entry.checkedHere,
          state: state ?? entry.state,
        ),
        record,
      );

  Map<String, Object?> toJson() => {
    'version': _version,
    'id': entry.id,
    'walletKey': entry.walletKey,
    'store': entry.store.name,
    'created': entry.created.toUtc().toIso8601String(),
    'synced': entry.synced,
    'providerName': entry.providerName,
    'checkedHere': entry.checkedHere?.toUtc().toIso8601String(),
    'state': entry.state.name,
    'record': record,
  };

  static _Item? tryParse(String key, Object? value) {
    if (value is! Map || !isBackupId(key)) return null;
    final json = Map<String, dynamic>.from(value);
    final walletKey = json['walletKey'];
    final store = BackupStoreKind.values
        .where((kind) => kind.name == json['store'])
        .firstOrNull;
    final created = _date(json['created']);
    final synced = json['synced'];
    final provider = json['providerName'];
    final checked = json['checkedHere'];
    final record = json['record'];
    final state = PasskeyBackupEntryState.values
        .where((value) => value.name == json['state'])
        .firstOrNull;
    if (state == null ||
        json['version'] != _version ||
        json['id'] != key ||
        walletKey is! String ||
        walletKey.isEmpty ||
        store == null ||
        created == null ||
        synced is! bool ||
        (provider != null && provider is! String) ||
        (checked != null && _date(checked) == null) ||
        record is! String ||
        record.isEmpty) {
      return null;
    }
    return _Item(
      PasskeyBackupEntry(
        id: key,
        walletKey: walletKey,
        store: store,
        created: created,
        synced: synced,
        providerName: provider as String?,
        checkedHere: checked == null ? null : _date(checked),
        state: state,
      ),
      record,
    );
  }

  static DateTime? _date(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
  }
}
