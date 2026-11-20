import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';

/// The short checklist of what is left to make a new wallet safe: a lock on
/// this device and a backed-up recovery phrase. The two are independent, and
/// neither gates transactions.
///
/// Callers own navigation and authorization; this widget holds no wallet data.
class WalletSetupCard extends StatelessWidget {
  const WalletSetupCard({
    required this.hasRecoveryPhrase,
    required this.hasDeviceProtection,
    required this.onBackup,
    required this.onProtect,
    this.protectionDescription,
    this.protectionSetup,
    this.recoveryDescription,
    this.backupActionLabel,
    this.backupLeads = false,
    super.key,
  });

  final bool hasRecoveryPhrase;
  final bool hasDeviceProtection;
  final VoidCallback onBackup;
  final VoidCallback onProtect;
  final String? protectionDescription;

  /// The live wallet-lock step. It draws its own finished state, so it is
  /// shown whether or not the lock is set up.
  final Widget? protectionSetup;
  final String? recoveryDescription;
  final String? backupActionLabel;

  /// Whether backing up is the main thing to do although the lock is not set
  /// up: the lock cannot be turned on in one step on this device.
  final bool backupLeads;

  @override
  Widget build(BuildContext context) {
    if (hasRecoveryPhrase && hasDeviceProtection) {
      return const SizedBox.shrink();
    }
    final backupIsPrimary = hasDeviceProtection || backupLeads;
    final protection =
        protectionSetup ??
        (hasDeviceProtection
            ? WalletSetupDone(label: 'authProtectionEnabled'.tr())
            : WalletSetupTask(
                icon: const Icon(Icons.lock_outline),
                title: 'authDeviceProtectionTitle'.tr(),
                description:
                    protectionDescription ??
                    'authDeviceProtectionReminder'.tr(),
                action: WalletSetupAction(
                  key: const Key('wallet-setup-protect'),
                  primary: !backupIsPrimary,
                  text: 'authProtectDevice'.tr(),
                  onPressed: onProtect,
                ),
              ));
    final backup = hasRecoveryPhrase
        ? WalletSetupDone(label: 'authRecoveryBackedUp'.tr())
        : WalletSetupTask(
            icon: const Icon(Icons.shield_outlined),
            title: 'authRecoveryNotReady'.tr(),
            description: recoveryDescription ?? 'authRecoveryTaskReason'.tr(),
            action: WalletSetupAction(
              key: const Key('wallet-setup-backup'),
              primary: backupIsPrimary,
              text: backupActionLabel ?? 'authBackUpRecoveryPhrase'.tr(),
              onPressed: onBackup,
            ),
          );
    return Card(
      key: const Key('wallet-setup-card'),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'authWalletSetupTitle'.tr(),
                style: SecuritySectionText.title(context),
              ),
            ),
            const SizedBox(height: 14),
            protection,
            const SizedBox(height: 18),
            backup,
          ],
        ),
      ),
    );
  }
}

/// One open step: what it is, why it matters, and the one thing to press.
class WalletSetupTask extends StatelessWidget {
  const WalletSetupTask({
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.footer,
    super.key,
  });

  /// Width of the action when it sits beside the text.
  static const double actionWidth = 230;

  final Widget icon;
  final String title;
  final String description;
  final Widget? action;

  /// Progress or the outcome of the action, under it.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: IconTheme.merge(
            data: IconThemeData(color: scheme.primary, size: 24),
            child: icon,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: SecuritySectionText.label(context)),
              ),
              const SizedBox(height: 4),
              Text(description, style: SecuritySectionText.body(context)),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final beside =
            action != null &&
            constraints.maxWidth >= 600 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.5;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (beside)
              Row(
                children: [
                  Expanded(child: text),
                  const SizedBox(width: 16),
                  SizedBox(width: actionWidth, child: action),
                ],
              )
            else ...[
              text,
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
            if (footer != null)
              Padding(
                // Under the text it belongs to when the action sits beside.
                padding: EdgeInsetsDirectional.only(
                  top: 12,
                  start: beside ? 36 : 0,
                ),
                child: footer,
              ),
          ],
        );
      },
    );
  }
}

/// The one action of a [WalletSetupTask]. The step that matters most carries
/// the primary button; the other stays a real, quieter button.
class WalletSetupAction extends StatelessWidget {
  const WalletSetupAction({
    required this.text,
    required this.onPressed,
    this.primary = true,
    this.icon,
    super.key,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool primary;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => primary
      ? UiPrimaryButton(
          expandForText: true,
          onPressed: onPressed,
          prefix: icon == null
              ? null
              : Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: icon,
                ),
          text: text,
        )
      : SecuritySecondaryButton(text: text, icon: icon, onPressed: onPressed);
}

/// A finished step, kept as one quiet line so progress stays visible.
class WalletSetupDone extends StatelessWidget {
  const WalletSetupDone({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: Icon(
          Icons.check_circle_outline,
          size: 24,
          color: theme.custom.successColor,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(label, style: SecuritySectionText.body(context)),
        ),
      ),
    ],
  );
}
