import 'dart:typed_data';

import 'package:web_dex/services/logger/safe_log_exporter.dart';

/// Abstract interface for feedback providers
abstract class FeedbackProvider {
  /// Submits feedback to the provider
  Future<void> submitFeedback({
    required String description,
    required Uint8List screenshot,
    required String type,
    required Map<String, dynamic> metadata,
    SafeLogAttachment? diagnostics,
  });

  /// Returns true if this provider is configured and available for use
  bool get isAvailable;
}

/// Provider failures contain status information, never response bodies or URLs.
final class FeedbackSubmissionException implements Exception {
  const FeedbackSubmissionException(this.stage, this.statusCode);

  final String stage;
  final int statusCode;

  @override
  String toString() => 'Feedback submission failed at $stage ($statusCode).';
}
