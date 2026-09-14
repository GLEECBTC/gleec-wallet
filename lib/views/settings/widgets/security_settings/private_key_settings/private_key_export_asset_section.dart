import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_labels.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/widgets/private_key_export_key_tile.dart';

class PrivateKeyExportAssetSection extends StatelessWidget {
  const PrivateKeyExportAssetSection({
    required this.outcome,
    required this.showKeys,
    required this.canDeliver,
    super.key,
  });

  final PrivateKeyExportOutcome outcome;
  final bool showKeys;
  final bool canDeliver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AssetHeader(outcome: outcome),
            // A failure used to render as body text identical to the
            // informational coverage line right beside it, so "the key could
            // not be retrieved" read like a footnote.
            if (outcome.failure case final failure?) ...[
              const SizedBox(height: 12),
              NoticeBanner(
                icon: Icons.error_outline,
                child: Text(
                  privateKeyExportFailureText(
                    failure,
                    assetId: outcome.assetId,
                  ),
                ),
              ),
            ],
            if (outcome.coverage case final coverage?) ...[
              const SizedBox(height: 12),
              _Detail(
                icon: Icons.account_tree_outlined,
                label: LocaleKeys.privateKeyExportCoverageLabel.tr(),
                value: privateKeyExportCoverageText(coverage),
              ),
            ],
            // Rendered inline rather than behind an ExpansionTile whose only
            // header content ("Keys included: N") restated the coverage line
            // directly above it and put a click between the reader and the
            // thing they came for.
            if (outcome.keys.isNotEmpty) ...[
              Divider(height: 24, color: theme.dividerColor),
              for (var index = 0; index < outcome.keys.length; index++)
                PrivateKeyExportKeyTile(
                  key: ValueKey(index),
                  privateKey: outcome.keys[index],
                  assetId: outcome.assetId,
                  index: index,
                  showKeys: showKeys,
                  canDeliver: canDeliver,
                  showDivider: index < outcome.keys.length - 1,
                  showOrdinal: outcome.keys.length > 1,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AssetHeader extends StatelessWidget {
  const _AssetHeader({required this.outcome});

  final PrivateKeyExportOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = outcome.keys.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                outcome.assetId.displayName,
                style: theme.textTheme.titleMedium,
              ),
              Text(
                outcome.assetId.id,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        _StatusBadge(
          label: available
              ? LocaleKeys.privateKeyExportIncludedBadge.tr(
                  namedArgs: {'count': '${outcome.keys.length}'},
                )
              : LocaleKeys.privateKeyExportUnavailableBadge.tr(),
          critical: !available,
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.critical});

  final String label;
  final bool critical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        style: theme.textTheme.labelSmall?.copyWith(
          color: critical
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              icon,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
