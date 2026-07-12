import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// Non-terminal GasFree relay state shown after the provider accepted a
/// transfer but final status is temporarily unavailable.
class GaslessPendingTransferPanel extends StatelessWidget {
  const GaslessPendingTransferPanel({
    required this.title,
    required this.description,
    required this.continueLabel,
    required this.activityLabel,
    required this.supportLabel,
    required this.traceLabel,
    required this.isChecking,
    required this.onContinueChecking,
    required this.onViewActivity,
    required this.onSupport,
    this.traceId,
    super.key,
  });

  final String title;
  final String description;
  final String continueLabel;
  final String activityLabel;
  final String supportLabel;
  final String traceLabel;
  final String? traceId;
  final bool isChecking;
  final VoidCallback? onContinueChecking;
  final VoidCallback? onViewActivity;
  final VoidCallback? onSupport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTrace = traceId?.trim().isNotEmpty == true;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Semantics(
            header: true,
            label: '$title. $description',
            child: ExcludeSemantics(
              child: Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (hasTrace) ...[
            const SizedBox(height: 20),
            Semantics(
              label: '$traceLabel ${traceId!}',
              child: SelectableText(
                '$traceLabel: ${traceId!}',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 28),
          // A request-only journal record has not received a relay trace yet.
          // It must remain a non-retryable "still processing" state: there is
          // no authoritative trace to poll, so omit the polling affordance and
          // leave Activity/Support as the safe recovery paths.
          if (hasTrace) ...[
            FilledButton.icon(
              onPressed: isChecking ? null : onContinueChecking,
              icon: isChecking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(continueLabel, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: onViewActivity,
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(activityLabel, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onSupport,
            child: Text(supportLabel, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

@Preview(
  name: 'GasFree pending - phone light',
  group: 'GasFree withdrawal',
  size: Size(375, 640),
)
Widget gaslessPendingTransferLightPreview() => MaterialApp(
  theme: newThemeLight,
  home: const Material(
    child: SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: GaslessPendingTransferPanel(
        title: 'Transfer still processing',
        description:
            'Your transfer was accepted and may still confirm. Sending again '
            'is disabled until the provider reports a final result.',
        continueLabel: 'Continue checking',
        activityLabel: 'View activity',
        supportLabel: 'Support',
        traceLabel: 'Trace ID',
        traceId: '4f8f4bea-f0d6-49ad-a02f-e871408b6b22',
        isChecking: false,
        onContinueChecking: null,
        onViewActivity: null,
        onSupport: null,
      ),
    ),
  ),
);

@Preview(
  name: 'GasFree pending - narrow dark 200% text',
  group: 'GasFree withdrawal',
  size: Size(320, 760),
  textScaleFactor: 2,
)
Widget gaslessPendingTransferDarkPreview() => MaterialApp(
  theme: newThemeDark,
  home: const Material(
    child: SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: GaslessPendingTransferPanel(
        title: 'Transfer still processing',
        description:
            'Your transfer was accepted and may still confirm. Sending again '
            'is disabled until the provider reports a final result.',
        continueLabel: 'Continue checking',
        activityLabel: 'View activity',
        supportLabel: 'Support',
        traceLabel: 'Trace ID',
        traceId: '4f8f4bea-f0d6-49ad-a02f-e871408b6b22',
        isChecking: true,
        onContinueChecking: null,
        onViewActivity: null,
        onSupport: null,
      ),
    ),
  ),
);
