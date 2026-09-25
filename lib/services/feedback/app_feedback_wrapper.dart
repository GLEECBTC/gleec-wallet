import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/services/feedback/custom_feedback_form.dart';
import 'package:web_dex/services/feedback/feedback_screenshot_guard.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

/// Wraps the app with BetterFeedback and provides consistent theming.
class AppFeedbackWrapper extends StatelessWidget {
  const AppFeedbackWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return BetterFeedback(
      feedbackBuilder: CustomFeedbackForm.feedbackBuilder,
      themeMode: ThemeMode.system,
      theme: _buildFeedbackTheme(brightness),
      darkTheme: _buildFeedbackTheme(Brightness.dark),
      child: Builder(
        builder: (context) => FeedbackScreenshotGuard(
          feedbackController: BetterFeedback.of(context),
          sensitivityController: ScreenshotSensitivity.maybeOf(context),
          child: child,
        ),
      ),
    );
  }

  FeedbackThemeData _buildFeedbackTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? FeedbackThemeData.light()
        : FeedbackThemeData.dark();
    return FeedbackThemeData(
      background: base.background,
      feedbackSheetColor: base.feedbackSheetColor,
      activeFeedbackModeColor: base.activeFeedbackModeColor,
      drawColors: base.drawColors,
      bottomSheetDescriptionStyle: base.bottomSheetDescriptionStyle,
      bottomSheetTextInputStyle: base.bottomSheetTextInputStyle,
      dragHandleColor: base.dragHandleColor,
      colorScheme: base.colorScheme,
      sheetIsDraggable: true,
      feedbackSheetHeight: 0.35,
    );
  }
}
