import 'dart:convert';
import 'dart:typed_data';

import '../passkey_backup_types.dart';

/// Record ids are base64url of 16 random bytes in every store.
final _backupId = RegExp(r'^[A-Za-z0-9_-]{22}$');

/// A sealed record never needs more; anything larger is not one of ours.
const maxBackupRecordBytes = 16 * 1024;

bool isBackupId(Object? id) => id is String && _backupId.hasMatch(id);

/// The bytes a store writes for [raw], after the checks every store makes.
Uint8List backupRecordBytes(String id, String raw) {
  final bytes = utf8.encode(raw);
  if (!isBackupId(id) || bytes.isEmpty || bytes.length > maxBackupRecordBytes) {
    throw const PasskeyBackupException(PasskeyBackupFailure.storageFailed);
  }
  return bytes;
}

/// The record's own creation time, for listing only: nothing trusts it
/// until the record decodes, and the service reads it again from there.
DateTime backupCreatedHint(String raw) {
  try {
    final json = jsonDecode(raw);
    final created = json is Map ? json['created'] : null;
    if (created is String) return DateTime.parse(created).toUtc();
  } on Object {
    // Not a record this build can read; the service drops it.
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}
