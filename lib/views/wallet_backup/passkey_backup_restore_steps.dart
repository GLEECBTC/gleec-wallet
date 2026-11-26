part of 'passkey_backup_restore.dart';

/// Where to look. Each place says what it will ask for before it asks.
class _RestoreChoose extends StatelessWidget {
  const _RestoreChoose({
    required this.stores,
    required this.notice,
    required this.onChoose,
    required this.onRetry,
    required this.onCancel,
  });

  final List<BackupStoreKind> stores;
  final _Notice? notice;
  final ValueChanged<BackupStoreKind> onChoose;

  /// Set when the places to look could not be loaded.
  final VoidCallback? onRetry;
  final VoidCallback onCancel;

  static (String, String, IconData) _labels(BackupStoreKind store) =>
      switch (store) {
        BackupStoreKind.iCloudKeychain => (
          'passkeyBackupRestoreFromICloud'.tr(),
          'passkeyBackupRestoreFromICloudHint'.tr(),
          Icons.cloud_outlined,
        ),
        BackupStoreKind.googleDrive => (
          'passkeyBackupRestoreFromDrive'.tr(),
          'passkeyBackupRestoreFromDriveHint'.tr(),
          Icons.add_to_drive_outlined,
        ),
        BackupStoreKind.file => (
          'passkeyBackupRestoreFromFile'.tr(),
          'passkeyBackupRestoreFromFileHint'.tr(),
          Icons.folder_open_outlined,
        ),
      };

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TransferTitle('passkeyBackupRestoreTitle'.tr()),
      const SizedBox(height: 12),
      TransferText('passkeyBackupRestoreIntro'.tr()),
      const SizedBox(height: 12),
      for (final store in stores)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TransferOpaqueText(
            child: Semantics(
              button: true,
              child: UiListActionRow(
                rowKey: ValueKey('passkey-backup-restore-${store.name}'),
                title: _labels(store).$1,
                subtitle: _labels(store).$2,
                leading: Icon(_labels(store).$3, size: 24),
                backgroundColor: Theme.of(context).cardColor,
                onTap: () => onChoose(store),
              ),
            ),
          ),
        ),
      if (notice case final notice?) ...[
        const SizedBox(height: 4),
        WalletAccessNotice(
          key: const Key('passkey-backup-restore-notice'),
          text: notice.text,
          tone: notice.tone,
        ),
      ],
      if (onRetry case final retry?) ...[
        const SizedBox(height: 12),
        UiPrimaryButton(
          key: const Key('passkey-backup-restore-retry'),
          text: LocaleKeys.tryAgain.tr(),
          expandForText: true,
          height: 50,
          onPressed: retry,
        ),
      ],
      const SizedBox(height: 12),
      UiUnderlineTextButton(
        key: const Key('passkey-backup-restore-cancel'),
        text: LocaleKeys.cancel.tr(),
        expandForText: true,
        onPressed: onCancel,
      ),
    ],
  );
}

/// The backups found, newest first. Picking one opens the passkey prompt,
/// which the line above the list announces.
class _RestorePick extends StatelessWidget {
  const _RestorePick({
    required this.backups,
    required this.notice,
    required this.onPick,
    required this.onChooseAgain,
  });

  final List<StoredBackup> backups;
  final _Notice? notice;
  final ValueChanged<StoredBackup> onPick;
  final VoidCallback onChooseAgain;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TransferTitle('passkeyBackupRestoreFoundTitle'.tr()),
      const SizedBox(height: 12),
      TransferText('passkeyBackupRestoreFoundHint'.tr()),
      const SizedBox(height: 12),
      for (final backup in backups)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TransferOpaqueText(
            child: Semantics(
              button: true,
              child: UiListActionRow(
                rowKey: ValueKey('passkey-backup-found-${backup.id}'),
                title: 'passkeyBackupRestoreItem'.tr(
                  args: [passkeyBackupDate(backup.created)],
                ),
                subtitle: passkeyBackupStoreName(backup.store),
                leading: const WalletPasskeyIcon(),
                backgroundColor: Theme.of(context).cardColor,
                onTap: () => onPick(backup),
              ),
            ),
          ),
        ),
      if (notice case final notice?) ...[
        const SizedBox(height: 4),
        WalletAccessNotice(
          key: const Key('passkey-backup-restore-notice'),
          text: notice.text,
          tone: notice.tone,
        ),
      ],
      const SizedBox(height: 12),
      UiUnderlineTextButton(
        key: const Key('passkey-backup-restore-elsewhere'),
        text: 'passkeyBackupRestoreOtherPlace'.tr(),
        expandForText: true,
        onPressed: onChooseAgain,
      ),
    ],
  );
}

class _RestoreWaiting extends StatelessWidget {
  const _RestoreWaiting({
    required this.title,
    required this.text,
    this.onCancel,
  });

  final String title;
  final String text;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TransferTitle(title),
      const SizedBox(height: 12),
      TransferText(text),
      const SizedBox(height: 20),
      Center(child: WalletAccessProgress(label: text)),
      if (onCancel case final cancel?) ...[
        const SizedBox(height: 20),
        UiUnderlineTextButton(
          key: const Key('passkey-backup-restore-wait-cancel'),
          text: LocaleKeys.cancel.tr(),
          expandForText: true,
          onPressed: cancel,
        ),
      ],
    ],
  );
}
