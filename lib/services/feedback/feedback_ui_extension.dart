import 'package:easy_localization/easy_localization.dart';
import 'package:feedback/feedback.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/feedback/feedback_service.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/services/feedback/feedback_capture_session.dart';

extension BuildContextShowFeedback on BuildContext {
  /// Shows the feedback dialog if the feedback service is available.
  /// Does nothing if the feedback service is not configured.
  void showFeedback() {
    final feedbackService = FeedbackService.create();
    if (feedbackService == null) {
      debugPrint(
        'Feedback dialog not shown: feedback service is not configured',
      );
      return;
    }

    final feedbackController = BetterFeedback.of(this);
    if (feedbackController.isVisible) return;
    final capture = FeedbackCaptureSession.begin(
      ScreenshotSensitivity.maybeOf(this),
    );
    feedbackController.show((feedback) async {
      try {
        final success = await capture.submit(
          feedback,
          service: feedbackService,
          currentController: () =>
              mounted ? ScreenshotSensitivity.maybeOf(this) : null,
        );
        if (!mounted) return;

        if (success) {
          feedbackController.hide();

          String? contactMethod;
          if (feedback.extra != null && feedback.extra is JsonMap) {
            final extras = feedback.extra!;
            contactMethod = extras.valueOrNull<String>('contact_method');
          }

          if (contactMethod == 'discord') {
            await Future.delayed(const Duration(milliseconds: 300));
            if (!mounted) return;
            await _showDiscordInfoDialog(this);
            if (!mounted) return;
          }

          ScaffoldMessenger.of(this).showSnackBar(
            SnackBar(
              content: Text(
                'Thank you! ${LocaleKeys.feedbackFormDescription.tr()}',
              ),
              action: SnackBarAction(
                label: LocaleKeys.addMoreFeedback.tr(),
                onPressed: () => showFeedback(),
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          final theme = Theme.of(this);
          ScaffoldMessenger.of(this).showSnackBar(
            SnackBar(
              content: Text(
                LocaleKeys.feedbackError.tr(),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          );
        }
      } catch (e) {
        debugPrint('Feedback submission failed.');
        if (!mounted) return;
        final theme = Theme.of(this);
        ScaffoldMessenger.of(this).showSnackBar(
          SnackBar(
            content: Text(
              LocaleKeys.feedbackError.tr(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
      }
    });
  }

  bool get isFeedbackAvailable =>
      FeedbackService.create()?.isAvailable ?? false;
}

Future<void> _showDiscordInfoDialog(BuildContext context) {
  final theme = Theme.of(context);

  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Let\'s Connect on Discord!'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'To ensure we can reach you:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• Make sure you\'re a member of the Komodo Discord server',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '• Watch for our team in the support channel',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '• Feel free to reach out to us anytime in the server',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text('Close'),
        ),
        SizedBox(
          width: 230,
          child: UiPrimaryButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _openDiscordSupport();
            },
            child: Text('Join Komodo Discord'),
          ),
        ),
      ],
    ),
  );
}

Future<void> _openDiscordSupport() async {
  try {
    await launchUrl(discordInviteUrl, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('Unable to open the support link.');
  }
}
