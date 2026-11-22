part of 'seed_backup_gate.dart';

class _SeedBackupGateNotice extends StatelessWidget {
  const _SeedBackupGateNotice({
    required this.isGenerated,
    required this.reason,
    required this.interruption,
    required this.onBackUp,
    required this.onImportInstead,
    required this.onContinueAnyway,
  });

  final bool isGenerated;
  final SeedBackupGateReason reason;
  final String? interruption;
  final VoidCallback onBackUp;
  final VoidCallback onImportInstead;
  final VoidCallback onContinueAnyway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      key: const Key('seed-backup-gate-notice'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.shield_outlined, size: 40, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          LocaleKeys.seedBackupGateTitle.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 12),
        Text(
          isGenerated
              ? LocaleKeys.seedBackupGateGeneratedBody.tr()
              : LocaleKeys.seedBackupGateBody.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
        ),
        if (interruption != null) ...[
          const SizedBox(height: 16),
          WalletAccessNotice(
            key: const Key('seed-backup-gate-interrupted'),
            text: interruption!,
          ),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('seed-backup-gate-backup-button'),
          height: 48,
          text: LocaleKeys.seedBackupGateBackUpNow.tr(),
          onPressed: onBackUp,
        ),
        if (isGenerated) ...[
          const SizedBox(height: 12),
          UiUnderlineTextButton(
            key: const Key('seed-backup-gate-import-instead-button'),
            text: LocaleKeys.seedBackupGateImportInstead.tr(),
            onPressed: onImportInstead,
          ),
        ],
        const SizedBox(height: 4),
        UiUnderlineTextButton(
          key: const Key('seed-backup-gate-continue-button'),
          text: LocaleKeys.seedBackupGateContinueAnyway.tr(),
          onPressed: onContinueAnyway,
        ),
      ],
    );
  }
}

class _SeedBackupGateSuccess extends StatelessWidget {
  const _SeedBackupGateSuccess({required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SeedConfirmSuccess(),
        const SizedBox(height: 16),
        UiPrimaryButton(
          key: const Key('seed-backup-gate-done-button'),
          height: 48,
          text: LocaleKeys.seedBackupGateShowAddress.tr(),
          onPressed: onDone,
        ),
      ],
    );
  }
}
