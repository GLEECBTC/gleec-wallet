import 'dart:typed_data';

import 'package:feedback/feedback.dart';
import 'package:web_dex/services/feedback/feedback_service.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

/// Starts before opening feedback, spanning its preview, capture and submission.
final class FeedbackCaptureSession {
  FeedbackCaptureSession.begin(ScreenshotSensitivityController? controller)
    : _policy = ScreenshotCapturePolicy.capture(controller);

  final ScreenshotCapturePolicy _policy;

  Future<bool> submit(
    UserFeedback feedback, {
    required FeedbackService service,
    required ScreenshotSensitivityController? Function() currentController,
    Duration settleDelay = const Duration(milliseconds: 500),
  }) async {
    await Future<void>.delayed(settleDelay);
    final sanitized = _policy.canIncludeScreenshot(currentController())
        ? feedback
        : UserFeedback(
            text: feedback.text,
            extra: feedback.extra,
            screenshot: Uint8List.fromList(_transparentPng),
          );
    return service.handleFeedback(sanitized);
  }

  // A valid 1x1 transparent PNG keeps ordinary feedback transports unchanged.
  static const _transparentPng = <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    11,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    96,
    0,
    2,
    0,
    0,
    5,
    0,
    1,
    122,
    94,
    171,
    63,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ];
}
