import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

final _legacyDiagnosticArchive = RegExp(
  r'^komodo_wallet_log_\d{2}\.\d{2}\.\d{4}_\d{2}-\d{2}-\d{2}\.zip$',
);

/// Removes only diagnostic archives previously placed in iOS app Documents.
///
/// Failures propagate to logging readiness; an incomplete migration must never
/// permit exporting legacy diagnostics. Wallet backups and links are untouched.
Future<void> purgeLegacyDiagnosticArtifacts() async {
  if (!Platform.isIOS) return;
  await purgeDiagnosticArchivesIn(await getApplicationDocumentsDirectory());
}

/// Directory-injected implementation for migration tests.
Future<void> purgeDiagnosticArchivesIn(Directory directory) async {
  if (!await directory.exists()) return;
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is File &&
        _legacyDiagnosticArchive.hasMatch(path.basename(entry.path))) {
      await entry.delete();
    }
  }
}

/// New diagnostic share files never enter the persistent backup directory.
Future<Directory> diagnosticShareDirectory() async {
  final temporary = await getTemporaryDirectory();
  return Directory(
    path.join(temporary.path, 'gleec_diagnostics_v1'),
  ).create(recursive: true);
}
