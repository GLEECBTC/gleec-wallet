import 'dart:convert';

import 'package:web_dex/services/storage/base_storage.dart';

import 'platform/credential_backend.dart';
import 'wallet_access_lock.dart';
import 'wallet_access_record.dart';
import 'wallet_access_types.dart';

/// Non-secret deletion intent survives engine removal and platform failures.
/// Authorization tokens remain in memory and are never put in the journal.
class WalletCredentialCleanup {
  WalletCredentialCleanup(this.storage, this.backend);

  static const journalKey = 'wallet_access_cleanup_v1';
  static const recordsKey = 'wallet_access_records_v1';
  final BaseStorage storage;
  final CredentialBackend backend;
  final Map<String, String> _authorizations = {};

  Future<Map<String, dynamic>> _read(String key) async {
    final stored = await storage.read(key);
    final raw = stored is String ? jsonDecode(stored) : stored;
    if (raw == null) return {};
    if (raw is! Map) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    return Map<String, dynamic>.from(raw);
  }

  Future<void> _write(String key, Map<String, dynamic> value) async {
    if (!await storage.write(key, value)) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    final persisted = await _read(key);
    if (jsonEncode(persisted) != jsonEncode(value)) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  Future<void> prepare(WalletAccessRecord record, String? authorization) =>
      withWalletAccessRecordLock(() async {
        final journal = await _read(journalKey);
        journal[record.entryId] = {
          'record': record.toJson(),
          'engineDeleted': false,
        };
        await _write(journalKey, journal);
        if (authorization != null) {
          _authorizations[record.entryId] = authorization;
        }
      });

  void revokeAuthorizations() => _authorizations.clear();

  /// Called after SDK deletion, including after a previously swallowed hook
  /// error. A failed cleanup remains journaled and is reported to the caller.
  Future<void> complete(
    String name,
    String? pubkeyHash, {
    bool discoverRecords = false,
    String? expectedEntryId,
  }) => withWalletAccessRecordLock(() async {
    final journal = await _read(journalKey);
    final records = await _read(recordsKey);
    for (final raw in discoverRecords ? records.values : const <dynamic>[]) {
      final record = WalletAccessRecord.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      if (record.walletName == name && record.pubkeyHash == pubkeyHash) {
        journal.putIfAbsent(
          record.entryId,
          () => {'record': record.toJson(), 'engineDeleted': true},
        );
      }
    }
    final targets = <String>[];
    for (final item in journal.entries) {
      final intent = Map<String, dynamic>.from(item.value as Map);
      final record = WalletAccessRecord.fromJson(
        Map<String, dynamic>.from(intent['record'] as Map),
      );
      if (record.walletName == name &&
          record.pubkeyHash == pubkeyHash &&
          (expectedEntryId != null
              ? item.key == expectedEntryId
              : discoverRecords || intent['engineDeleted'] == true)) {
        intent['engineDeleted'] = true;
        journal[item.key] = intent;
        targets.add(item.key);
      }
    }
    await _write(journalKey, journal);
    for (final id in targets) {
      await _remove(id, journal, records);
    }
  });

  /// Startup only performs noninteractive cleanup after proving the original
  /// immutable entry no longer exists. Protected leftovers require retry().
  Future<void> resume(Set<String> existingEntryIds) =>
      withWalletAccessRecordLock(() async {
        final journal = await _read(journalKey);
        final records = await _read(recordsKey);
        for (final id in journal.keys.toList()) {
          final intent = Map<String, dynamic>.from(journal[id] as Map);
          if (existingEntryIds.contains(id)) {
            continue;
          }
          intent['engineDeleted'] = true;
          journal[id] = intent;
          await _write(journalKey, journal);
          try {
            await _remove(id, journal, records);
          } catch (_) {
            // Keep the durable intent. Startup must not display an OS prompt
            // or prevent access to the user's other wallets.
          }
        }
      });

  Future<bool> get hasIntents async => (await _read(journalKey)).isNotEmpty;
  Future<bool> get hasPending async => (await _read(
    journalKey,
  )).values.any((value) => value is Map && value['engineDeleted'] == true);

  /// Explicit repair action; it is safe to retry after another process death.
  Future<void> retry(Future<String?> Function(String key) authorize) async {
    final journal = await _read(journalKey);
    for (final raw in journal.values) {
      final intent = Map<String, dynamic>.from(raw as Map);
      if (intent['engineDeleted'] != true) continue;
      final record = WalletAccessRecord.fromJson(
        Map<String, dynamic>.from(intent['record'] as Map),
      );
      final token = await authorize(record.credentialKey);
      if (token != null) _authorizations[record.entryId] = token;
      await complete(
        record.walletName,
        record.pubkeyHash,
        expectedEntryId: record.entryId,
      );
    }
  }

  Future<void> _remove(
    String id,
    Map<String, dynamic> journal,
    Map<String, dynamic> records,
  ) async {
    final intent = Map<String, dynamic>.from(journal[id] as Map);
    final record = WalletAccessRecord.fromJson(
      Map<String, dynamic>.from(intent['record'] as Map),
    );
    final token = _authorizations.remove(id);
    if (token != null) {
      // An OS-authorized deletion token can remove an invalidated key whose
      // metadata probe is no longer usable. Native code still checks its CAS.
      await backend.delete(record.credentialKey, authorization: token);
    } else {
      final info = await backend.metadata(record.credentialKey);
      if (info?.enrolled == true) {
        throw const WalletAccessException(WalletAccessFailure.storageFailed);
      }
      if (info != null) await backend.delete(record.credentialKey);
    }
    if (await backend.metadata(record.credentialKey) != null) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
    records.remove(id);
    await _write(recordsKey, records);
    for (final key in ['wallet_access_pending_v1', 'wallet_access_last_v1']) {
      final raw = await storage.read(key);
      if (raw == id || (raw is Map && raw['entryId'] == id)) {
        if (!await storage.delete(key) && await storage.read(key) != null) {
          throw const WalletAccessException(WalletAccessFailure.storageFailed);
        }
      }
    }
    journal.remove(id);
    await _write(journalKey, journal);
  }
}
