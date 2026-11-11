import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A small reminder with independent device-protection and recovery statuses.
/// Callers own navigation and authorization; this widget holds no wallet data.
class WalletSetupCard extends StatelessWidget {
  const WalletSetupCard({
    required this.hasRecoveryPhrase,
    required this.hasDeviceProtection,
    required this.onBackup,
    required this.onProtect,
    this.protectionDescription,
    super.key,
  });

  final bool hasRecoveryPhrase;
  final bool hasDeviceProtection;
  final VoidCallback onBackup;
  final VoidCallback onProtect;
  final String? protectionDescription;

  @override
  Widget build(BuildContext context) {
    if (hasRecoveryPhrase && hasDeviceProtection) {
      return const SizedBox.shrink();
    }
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
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (!hasRecoveryPhrase) Text('authRecoveryReminder'.tr()),
            if (!hasDeviceProtection) ...[
              if (!hasRecoveryPhrase) const SizedBox(height: 8),
              Text(
                protectionDescription ?? 'authDeviceProtectionReminder'.tr(),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (!hasRecoveryPhrase)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    key: const Key('wallet-setup-backup'),
                    onPressed: onBackup,
                    icon: const Icon(Icons.key_outlined),
                    label: Text('authBackUpRecoveryPhrase'.tr()),
                  ),
                if (!hasDeviceProtection)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    key: const Key('wallet-setup-protect'),
                    onPressed: onProtect,
                    icon: const Icon(Icons.lock_outline),
                    label: Text('authProtectDevice'.tr()),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
