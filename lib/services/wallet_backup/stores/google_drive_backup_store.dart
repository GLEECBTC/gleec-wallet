import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../passkey_backup_types.dart';
import 'backup_store_limits.dart';
import 'google_drive_authorizer.dart';

part 'google_drive_requests.dart';

/// Sealed records in the app's hidden data folder in the user's Google
/// Drive, which no other app's client can read. Drive REST v3.
final class GoogleDriveBackupStore implements BackupRecordStore {
  GoogleDriveBackupStore({
    required this._authorizer,
    http.Client? client,
    DateTime Function()? clock,
    Random? random,
    this._timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static const filePrefix = 'gleec-passkey-backup-';

  /// One sign-in covers the few calls of one backup action, such as a write
  /// and its readback, without the token outliving it.
  static const tokenReuse = Duration(minutes: 5);

  static String fileNameFor(String id) => '$filePrefix$id.json';

  final GoogleDriveAuthorizer _authorizer;
  final http.Client _client;
  final DateTime Function() _clock;
  final Random _random;
  final Duration _timeout;
  String? _token;
  DateTime? _tokenExpires;
  Future<String>? _authorizing;

  @override
  BackupStoreKind get kind => BackupStoreKind.googleDrive;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _authorizer.isAvailable();
    } on Object {
      return false;
    }
  }

  @override
  Future<List<StoredBackup>> list() async {
    final token = await _bearer();
    final backups = <String, StoredBackup>{};
    for (final file in await _files(token)) {
      if (backups.containsKey(file.backupId)) continue;
      final raw = await _download(token, file.id);
      if (raw == null) continue;
      backups[file.backupId] = StoredBackup(
        id: file.backupId,
        store: kind,
        created: backupCreatedHint(raw),
        raw: raw,
      );
    }
    return backups.values.toList();
  }

  @override
  Future<void> write(String id, String raw) async {
    final body = backupRecordBytes(id, raw);
    final token = await _bearer();
    final existing = [
      for (final file in await _files(token))
        if (file.backupId == id) file,
    ];
    if (existing.isEmpty) {
      await _create(token, id, raw, body);
    } else {
      await _update(token, existing.first.id, body);
    }
  }

  @override
  Future<void> delete(String id) async {
    if (!isBackupId(id)) throw _storageFailed;
    final token = await _bearer();
    for (final file in await _files(token)) {
      if (file.backupId == id) await _deleteFile(token, file.id);
    }
  }

  @override
  Future<void> prepare() => _bearer();

  /// Drops the in-memory token, as after a sign-out.
  void forgetToken() {
    _token = null;
    _tokenExpires = null;
  }

  Future<String> _bearer() async {
    final token = _token;
    final expires = _tokenExpires;
    if (token != null && expires != null && _clock().isBefore(expires)) {
      return token;
    }
    forgetToken();
    // Concurrent calls share one sign-in instead of stacking prompts.
    final pending = _authorizing ??= _authorizer.authorize().whenComplete(
      () => _authorizing = null,
    );
    final fresh = await pending;
    _token = fresh;
    _tokenExpires = _clock().add(tokenReuse);
    return fresh;
  }

  static const _storageFailed = PasskeyBackupException(
    PasskeyBackupFailure.storageFailed,
  );
  static const _unavailable = PasskeyBackupException(
    PasskeyBackupFailure.storeUnavailable,
  );
}
