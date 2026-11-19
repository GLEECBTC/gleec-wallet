import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// "Download all keys" in 0.9.2 to 0.9.6 wrote the keys here unencrypted.
final _privateKeyExport = RegExp(r'^private_keys_\d+\.(txt|json)$');

/// Far above any wallet file. A larger file is not one, so it is never read.
const _maxWalletFileBytes = 1024 * 1024;

/// Removes the secrets that iOS exports up to 0.10.0 left in app Documents,
/// and returns how many files it removed.
///
/// Each export wrote its file to Documents, then the share sheet took a copy
/// wherever the user chose. The app does not show Documents in Files, so the
/// copy left behind was reachable only through device backups, which include
/// Documents.
///
/// [isIOS] and [documents] stand in for the platform and the Documents lookup
/// in tests, which must never reach the host's own folders.
Future<int> purgeLegacyExportResidue({
  bool? isIOS,
  Future<Directory> Function()? documents,
}) async {
  if (!(isIOS ?? Platform.isIOS)) return 0;
  final directory = await (documents ?? getApplicationDocumentsDirectory)();
  return (await purgeExportResidueIn(directory)).length;
}

/// Directory-injected implementation for tests. Returns the names removed.
///
/// Looks only at files directly inside [directory] and never follows links.
/// One file that cannot be removed does not stop the others; the first
/// failure is rethrown once every file has been tried.
Future<List<String>> purgeExportResidueIn(Directory directory) async {
  final removed = <String>[];
  if (!await directory.exists()) return removed;
  Object? failure;
  StackTrace? failureTrace;
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is! File) continue;
    final name = path.basename(entry.path);
    try {
      if (_privateKeyExport.hasMatch(name) ||
          await _isLegacyWalletFile(entry)) {
        await entry.delete();
        removed.add(name);
      }
    } on FileSystemException catch (error, trace) {
      failure ??= error;
      failureTrace ??= trace;
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, failureTrace!);
  return removed;
}

/// The envelope `EncryptionTool.encryptData` wrote for "Download as file":
/// `{"0": ciphertext, "1": iv, "2": salt}`, each base64. Its name came from
/// the wallet's, so only the content identifies it.
Future<bool> _isLegacyWalletFile(File file) async {
  if (await file.length() > _maxWalletFileBytes) return false;
  final Object? json;
  try {
    json = jsonDecode(await file.readAsString());
  } on FormatException {
    return false;
  } on FileSystemException {
    // Not UTF-8: a binary file.
    return false;
  }
  if (json is! Map<String, dynamic> || json.length != 3) return false;
  final ciphertext = _base64Bytes(json['0']);
  return ciphertext != null &&
      ciphertext.isNotEmpty &&
      ciphertext.length % 16 == 0 &&
      _base64Bytes(json['1'])?.length == 16 &&
      _base64Bytes(json['2'])?.length == 16;
}

List<int>? _base64Bytes(Object? value) {
  if (value is! String) return null;
  try {
    return base64.decode(value);
  } on FormatException {
    return null;
  }
}
