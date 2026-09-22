import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// Title, one-line framing, and an at-a-glance count of what came back.
///
/// The counts matter because partial failure used to be invisible: three
/// unavailable assets out of twelve showed up only as three grey sentences
/// buried in three separate cards.
class PrivateKeyExportHeader extends StatelessWidget {
  const PrivateKeyExportHeader({
    required this.assetCount,
    required this.keyCount,
    required this.unavailableCount,
    super.key,
  });

  final int assetCount;
  final int keyCount;
  final int unavailableCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.privateKeyExportTitle.tr(),
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          LocaleKeys.privateKeyExportDescription.tr(),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip(
              label: LocaleKeys.privateKeyExportSummaryCounts.tr(
                namedArgs: {'assets': '$assetCount', 'keys': '$keyCount'},
              ),
            ),
            if (unavailableCount > 0)
              _CountChip(
                label: LocaleKeys.privateKeyExportSomeUnavailable.tr(
                  namedArgs: {'count': '$unavailableCount'},
                ),
                critical: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, this.critical = false});

  final String label;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = critical
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: critical
            ? theme.colorScheme.error.withValues(alpha: 0.12)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}
