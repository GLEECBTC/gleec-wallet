import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:web_dex/services/file_loader/diagnostic_artifacts.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/logger/diagnostic_log_record.dart';
import 'package:web_dex/services/logger/diagnostic_log_store.dart';
import 'package:web_dex/services/logger/logger.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';
import 'package:web_dex/services/platform_info/platform_info.dart';

class UniversalLogger implements LoggerInterface, DiagnosticLogSource {
  UniversalLogger({
    required this.platformInfo,
    DiagnosticLogStore? store,
    Future<void> Function()? purgeLegacyArtifacts,
    FileLoader? fileLoader,
    DateTime Function()? now,
  }) : _store = store ?? const DragonDiagnosticLogStore(),
       _purgeLegacyArtifacts =
           purgeLegacyArtifacts ?? purgeLegacyDiagnosticArtifacts,
       _fileLoader = fileLoader,
       _now = now ?? DateTime.now;

  final PlatformInfo platformInfo;
  final DiagnosticLogStore _store;
  final Future<void> Function() _purgeLegacyArtifacts;
  final FileLoader? _fileLoader;
  final DateTime Function() _now;
  late final _exporter = SafeLogExporter(source: this);
  Future<void>? _initialization;
  bool _ready = false;
  bool _disposed = false;
  Map<String, Object?> _metadata = const {};

  @override
  Future<void> init() {
    if (_ready || _disposed) return Future.value();
    return _initialization ??= _initialize().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initialize() async {
    try {
      await _purgeLegacyArtifacts();
      await _store.initialize();
      _ready = !_disposed;
    } on Object {
      // Logging is optional. Wallet startup proceeds, but exports fail closed.
      _ready = false;
    }
  }

  @override
  Future<void> ensureReady() async {
    await init();
    if (!_ready || _disposed) throw const DiagnosticLogsUnavailable();
  }

  @override
  void setSessionMetadata(Map<String, Object?> metadata) {
    _metadata = Map.unmodifiable(metadata);
  }

  @override
  Future<void> write(String message, [String? path]) async {
    // Startup callbacks must never print or enqueue unreviewed pre-init data.
    await _initialization;
    if (!_ready || _disposed) return;
    final record = DiagnosticLogRecord.create(
      timestamp: _now().millisecondsSinceEpoch,
      message: message,
      source: path,
      context: _metadata,
    );
    if (record == null) return;
    try {
      await _store.writeRecord(jsonEncode(record.toJson()));
    } on Object {
      throw const DiagnosticLogsUnavailable();
    }
  }

  @override
  Stream<String> readRecords() async* {
    await ensureReady();
    yield* _store.readRecords();
  }

  @override
  Future<SafeLogAttachment> exportLogs({int? maxBytes}) =>
      _exporter.export(maxBytes: maxBytes);

  @override
  Future<Uint8List> exportRecentLogsBytes({
    int maxBytes = SafeLogExporter.feedbackMaxBytes,
  }) async => (await exportLogs(maxBytes: maxBytes)).bytes;

  @override
  Future<void> getLogFile() async {
    final attachment = await exportLogs();
    final date = DateFormat('dd.MM.yyyy_HH-mm-ss').format(_now());
    try {
      await (_fileLoader ?? FileLoader.fromPlatform()).save(
        fileName: 'komodo_wallet_log_$date',
        data: utf8.decode(attachment.bytes),
        type: LoadFileType.compressed,
      );
    } on Object {
      throw const DiagnosticLogsUnavailable();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _ready = false;
    await _initialization;
    await _store.dispose();
  }
}
