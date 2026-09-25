import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// Shown while the export runs.
///
/// The screen previously rendered nothing at all during `starting` and
/// `exporting`, so unlocking the wallet dropped the reader onto a blank page
/// with no indication that anything was happening.
class PrivateKeyExportLoadingView extends StatelessWidget {
  const PrivateKeyExportLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 16),
          Text(
            LocaleKeys.privateKeyExportLoading.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
