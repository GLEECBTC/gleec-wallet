import 'package:flutter/foundation.dart';
import 'package:web_dex/services/feedback/feedback_provider.dart';
import 'package:web_dex/services/logger/safe_log_exporter.dart';

class DebugConsoleFeedbackProvider implements FeedbackProvider {
  @override
  bool get isAvailable => true;

  @override
  Future<void> submitFeedback({
    required String description,
    required Uint8List screenshot,
    required String type,
    required Map<String, dynamic> metadata,
    SafeLogAttachment? diagnostics,
  }) async {
    // User-entered feedback and contact details must not become console logs.
    debugPrint('Feedback captured by debug provider; no upload performed.');
  }
}
