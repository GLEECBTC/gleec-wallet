import 'package:dragon_logs/dragon_logs.dart';

/// Storage for current-policy JSONL diagnostics, separate from wallet storage.
abstract interface class DiagnosticLogStore {
  Future<void> initialize();
  Future<void> writeRecord(String record);
  Stream<String> readRecords();
  Future<void> dispose();
}

final class DragonDiagnosticLogStore implements DiagnosticLogStore {
  const DragonDiagnosticLogStore();

  static const storageNamespace = 'gleec_diagnostics_v1';

  @override
  Future<void> initialize() =>
      DragonLogs.init(storageNamespace: storageNamespace, purgeLegacy: true);

  @override
  Future<void> writeRecord(String record) => DragonLogs.writeRecord(record);

  @override
  Stream<String> readRecords() => DragonLogs.exportLogsStream();

  @override
  Future<void> dispose() => DragonLogs.dispose();
}
