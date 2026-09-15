import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';

/// Bulk export actions.
///
/// These were `ActionChip`s - Material's low-emphasis, inline, contextual
/// control - for what is the highest-consequence operation on the screen.
/// They are buttons now, and they say why they are disabled instead of
/// leaving the reader to discover the reveal gate by trial.
class PrivateKeyActionsWidget extends StatelessWidget {
  const PrivateKeyActionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<PrivateKeyExportBloc, PrivateKeyExportState>(
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleKeys.privateKeyExportBulkActionsTitle.tr(),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final buttons = [
                for (final action in const [
                  PrivateKeyExportAction.copy,
                  PrivateKeyExportAction.download,
                ])
                  _ActionButton(
                    action: action,
                    enabled: state.canDeliver,
                    busy: state.isDelivering,
                  ),
              ];
              // Stack below the width where the buttons stop being legible
              // side by side; the old Wrap reflowed them into an arbitrary
              // order mixed in with the visibility switch and the filter.
              if (constraints.maxWidth < 480) {
                return Column(
                  children: [
                    for (final button in buttons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: button,
                      ),
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: buttons[i]),
                  ],
                ],
              );
            },
          ),
          if (!state.canDeliver && !state.isDelivering) ...[
            const SizedBox(height: 8),
            Text(
              LocaleKeys.privateKeyExportRevealGateHint.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.enabled,
    required this.busy,
  });

  final PrivateKeyExportAction action;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final key = Key('private-key-export-${action.name}');
    final onPressed = enabled
        ? () => context.read<PrivateKeyExportBloc>().add(
            PrivateKeyExportDeliveryRequested(action),
          )
        : null;
    final label = switch (action) {
      PrivateKeyExportAction.copy => LocaleKeys.copyDisplayedKeys.tr(),
      PrivateKeyExportAction.download => LocaleKeys.downloadDisplayedKeys.tr(),
    };
    final icon = switch (action) {
      PrivateKeyExportAction.copy => Icons.copy,
      PrivateKeyExportAction.download => Icons.download,
    };

    // The spinner belongs inside the control that is working. Appended to the
    // old Wrap it could reflow onto its own line, detached from whatever it
    // was reporting on.
    final child = busy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    if (action == PrivateKeyExportAction.copy) {
      return UiPrimaryButton(
        key: key,
        onPressed: onPressed,
        height: 44,
        child: child,
      );
    }
    return UiSecondaryButton(
      key: key,
      onPressed: onPressed,
      height: 44,
      child: child,
    );
  }
}
