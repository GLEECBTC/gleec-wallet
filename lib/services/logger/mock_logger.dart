import 'dart:typed_data';

import 'package:web_dex/services/logger/logger.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';

class MockLogger implements LoggerInterface {
  const MockLogger();

  @override
  Future<void> write(String logMessage, [String? path]) async {}
  @override
  void setSessionMetadata(Map<String, Object?> metadata) {}
  @override
  Future<void> getLogFile() async {}
  @override
  Future<void> init() async {}
  @override
  Future<SafeLogAttachment> exportLogs({int? maxBytes}) async =>
      SafeLogAttachment.empty();
  @override
  Future<Uint8List> exportRecentLogsBytes({
    int maxBytes = SafeLogExporter.feedbackMaxBytes,
  }) async => Uint8List(0);
  @override
  Future<void> dispose() async {}
}
