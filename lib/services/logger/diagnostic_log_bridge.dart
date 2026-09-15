import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/services/logger/logger.dart';

/// Builds one safe copy for every app sink; error objects and stack traces are
/// intentionally not forwarded to developer logging or persistent diagnostics.
Future<void> forwardDiagnosticRecord(
  LogRecord record,
  LoggerInterface sink, {
  void Function(String message)? debugOutput,
}) async {
  final message = record.object == null
      ? DiagnosticSanitizer.sanitizeMessage(record.message)
      : null;
  if (message == null && record.error == null) return;
  // Custom Level names are caller-controlled; persist only known categories.
  final level = switch (record.level.value) {
    >= 1200 => 'SHOUT',
    >= 1000 => 'SEVERE',
    >= 900 => 'WARNING',
    >= 800 => 'INFO',
    _ => 'DEBUG',
  };
  final text =
      '$level: ${message ?? 'Diagnostic event omitted'}'
      '${record.error == null ? '' : ' (${DiagnosticSanitizer.safeError(record.error)})'}';
  final source = DiagnosticSanitizer.sanitizeMessage(record.loggerName);
  debugOutput?.call(text);
  await sink.write(text, source);
}
