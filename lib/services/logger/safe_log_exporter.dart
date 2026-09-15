import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_dex/services/logger/diagnostic_log_record.dart';

final class DiagnosticLogsUnavailable implements Exception {
  const DiagnosticLogsUnavailable();

  @override
  String toString() => 'Diagnostic logs are unavailable.';
}

abstract interface class DiagnosticLogSource {
  Future<void> ensureReady();
  Stream<String> readRecords();
}

/// Only this library can construct a nonempty diagnostic attachment.
final class SafeLogAttachment {
  SafeLogAttachment._(Uint8List bytes) : _bytes = Uint8List.fromList(bytes);
  SafeLogAttachment.empty() : _bytes = Uint8List(0);

  final Uint8List _bytes;
  Uint8List get bytes => Uint8List.fromList(_bytes);
  bool get isEmpty => _bytes.isEmpty;
  int get length => _bytes.length;
  String get fileName => 'logs.txt';
}

/// Used by both manual downloads and feedback. Legacy/unframed records are
/// rejected, and current records are sanitized again before leaving the app.
final class SafeLogExporter {
  const SafeLogExporter({required DiagnosticLogSource source})
    : _source = source;

  static const feedbackMaxBytes = 9 * 1024 * 1024;
  static const maxRecordCharacters = 64 * 1024;
  final DiagnosticLogSource _source;

  Future<SafeLogAttachment> export({int? maxBytes}) async {
    if (maxBytes != null && maxBytes < 0) {
      throw ArgumentError('The diagnostic export limit must be nonnegative.');
    }
    try {
      return await _export(maxBytes: maxBytes);
    } on Object {
      // Storage/decoder exceptions may contain a path or rejected record.
      throw const DiagnosticLogsUnavailable();
    }
  }

  Future<SafeLogAttachment> _export({int? maxBytes}) async {
    await _source.ensureReady();
    final records = Queue<Uint8List>();
    var totalBytes = 0;
    await for (final line in _boundedRecords(_source.readRecords())) {
      DiagnosticLogRecord? record;
      try {
        record = DiagnosticLogRecord.fromJson(jsonDecode(line));
      } on FormatException {
        continue;
      }
      if (record == null) continue;
      final bytes = Uint8List.fromList(
        utf8.encode('${jsonEncode(record.toJson())}\n'),
      );
      if (maxBytes != null && bytes.length > maxBytes) continue;
      records.addLast(bytes);
      totalBytes += bytes.length;
      while (maxBytes != null && totalBytes > maxBytes) {
        totalBytes -= records.removeFirst().length;
      }
    }
    final output = BytesBuilder(copy: false);
    for (final record in records) {
      output.add(record);
    }
    return SafeLogAttachment._(output.takeBytes());
  }

  /// A newline terminates each JSON envelope. Oversized or incomplete records
  /// are discarded in full; chunk boundaries never become record boundaries.
  Stream<String> _boundedRecords(Stream<String> chunks) async* {
    var pending = '';
    var discard = false;
    await for (final chunk in chunks) {
      var start = 0;
      while (start < chunk.length) {
        final end = chunk.indexOf('\n', start);
        final partEnd = end < 0 ? chunk.length : end;
        if (!discard) {
          if (pending.length + partEnd - start > maxRecordCharacters) {
            pending = '';
            discard = true;
          } else {
            pending += chunk.substring(start, partEnd);
          }
        }
        if (end < 0) break;
        if (!discard && pending.isNotEmpty) yield pending;
        pending = '';
        discard = false;
        start = end + 1;
      }
    }
  }
}
