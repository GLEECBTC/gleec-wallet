import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// Distinguishes "your filter hid everything" from "nothing was exportable".
///
/// These need different responses from the reader, and a single unstyled
/// sentence gave them the same one.
class PrivateKeyExportEmptyState extends StatelessWidget {
  const PrivateKeyExportEmptyState({required this.hiddenByFilter, super.key});

  final bool hiddenByFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            hiddenByFilter ? Icons.filter_alt_off : Icons.inbox_outlined,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            hiddenByFilter
                ? LocaleKeys.privateKeyExportAllFiltered.tr()
                : LocaleKeys.privateKeyExportNoAssets.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          if (hiddenByFilter) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.read<PrivateKeyExportBloc>().add(
                const PrivateKeyExportBlockedAssetsChanged(true),
              ),
              child: Text(LocaleKeys.includeBlockedAssets.tr()),
            ),
          ],
        ],
      ),
    );
  }
}
