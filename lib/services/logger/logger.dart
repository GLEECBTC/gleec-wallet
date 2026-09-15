import 'dart:typed_data';

import 'package:web_dex/services/logger/safe_log_exporter.dart';

abstract class LoggerInterface {
  Future<void> init();
  void setSessionMetadata(Map<String, Object?> metadata);
  Future<void> write(String logMessage, [String? path]);
  Future<void> getLogFile();
  Future<SafeLogAttachment> exportLogs({int? maxBytes});
  Future<Uint8List> exportRecentLogsBytes({int maxBytes});
  Future<void> dispose();
}
