import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';

/// The master switch for revealing key material.
///
/// Reveal is a two-stage gate - this switch, then a per-key reveal - and
/// nothing on the screen used to say so. Every disabled control (the per-key
/// eye, copy and QR buttons, and the bulk export actions) hangs off this
/// switch, so the explanation belongs next to it rather than in a tooltip on
/// a greyed-out icon.
///
/// The clipboard warning lives here too, and only once keys are unlocked.
/// Shown at page load it fires when copying is still impossible, which is
/// exactly when a reader learns to skip it.
class PrivateKeyRevealGate extends StatelessWidget {
  const PrivateKeyRevealGate({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocSelector<PrivateKeyExportBloc, PrivateKeyExportState, bool>(
      selector: (state) => state.showKeys,
      builder: (context, showKeys) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Switch(
                  key: const Key('private-key-export-visibility'),
                  value: showKeys,
                  onChanged: (visible) => context
                      .read<PrivateKeyExportBloc>()
                      .add(PrivateKeyExportVisibilityChanged(visible)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    LocaleKeys.showPrivateKeys.tr(),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              showKeys
                  ? LocaleKeys.privateKeyExportRevealGateHintOn.tr()
                  : LocaleKeys.privateKeyExportRevealGateHint.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (showKeys) ...[
              const SizedBox(height: 12),
              NoticeBanner(
                key: const Key('private-key-export-notice-copy'),
                icon: Icons.content_paste_off,
                child: Text(LocaleKeys.copyWarning.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
