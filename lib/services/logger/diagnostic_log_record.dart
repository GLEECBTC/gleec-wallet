import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

/// An independently framed diagnostic copy. Raw RPC payloads never belong here.
final class DiagnosticLogRecord {
  const DiagnosticLogRecord._({
    required this.timestamp,
    required this.message,
    required this.context,
    this.source,
  });

  static const schemaVersion = 1;
  static const _fields = {
    'schema',
    'timestamp',
    'message',
    'source',
    'context',
  };
  static const _contextFields = {
    'appVersion',
    'mm2Version',
    'appLanguage',
    'platform',
    'osLanguage',
    'screenSize',
  };

  final int timestamp;
  final String message;
  final String? source;
  final Map<String, String> context;

  static DiagnosticLogRecord? create({
    required Object? message,
    required int timestamp,
    Object? source,
    Map<String, Object?> context = const {},
  }) {
    final safeMessage = DiagnosticSanitizer.sanitizeMessage(message);
    if (safeMessage == null || timestamp < 0 || timestamp > 8640000000000000) {
      return null;
    }
    return DiagnosticLogRecord._(
      timestamp: timestamp,
      message: safeMessage,
      source: DiagnosticSanitizer.sanitizeMessage(source),
      context: Map.unmodifiable({
        for (final key in _contextFields)
          if (DiagnosticSanitizer.sanitizeMessage(context[key])
              case final String value)
            key: value,
      }),
    );
  }

  static DiagnosticLogRecord? fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['schema'] != schemaVersion ||
        value['timestamp'] is! int ||
        value.keys.any((key) => !_fields.contains(key))) {
      return null;
    }
    final context = value['context'];
    if (context != null && context is! Map<String, dynamic>) return null;
    return create(
      message: value['message'],
      timestamp: value['timestamp'] as int,
      source: value['source'],
      context: context as Map<String, dynamic>? ?? const {},
    );
  }

  Map<String, Object?> toJson() => {
    'schema': schemaVersion,
    'timestamp': timestamp,
    'message': message,
    if (source != null) 'source': source,
    if (context.isNotEmpty) 'context': context,
  };
}
