part of 'passkey_backup_setup.dart';

/// What a backup does, where it works and who can restore it: everything
/// the user needs before deciding.
class _SetupExplain extends StatelessWidget {
  const _SetupExplain({
    required this.showStolenDeviceTip,
    required this.onContinue,
    required this.onCancel,
  });

  final bool showStolenDeviceTip;
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TransferTitle('passkeyBackupSetupExplainTitle'.tr()),
      const SizedBox(height: 12),
      TransferText('passkeyBackupSetupWhat'.tr()),
      const SizedBox(height: 16),
      _Heading('passkeyBackupSetupWhereTitle'.tr()),
      TransferText('passkeyBackupSetupWhere'.tr()),
      const SizedBox(height: 16),
      _Heading('passkeyBackupSetupWhoTitle'.tr()),
      _Bullet('passkeyBackupSetupWhoYou'.tr()),
      _Bullet('passkeyBackupSetupWhoShared'.tr()),
      _Bullet('passkeyBackupSetupWhoAccount'.tr()),
      if (showStolenDeviceTip) ...[
        const SizedBox(height: 12),
        WalletAccessNotice(
          key: const Key('passkey-backup-stolen-device-tip'),
          text: 'passkeyBackupSetupStolenDevice'.tr(),
          announce: false,
        ),
      ],
      const SizedBox(height: 12),
      WalletAccessNotice(
        text: 'passkeyBackupSetupKeepPhrase'.tr(),
        tone: WalletAccessTone.warning,
        announce: false,
      ),
      const SizedBox(height: 20),
      UiPrimaryButton(
        key: const Key('passkey-backup-explain-continue'),
        text: LocaleKeys.continueText.tr(),
        expandForText: true,
        height: 50,
        onPressed: onContinue,
      ),
      const SizedBox(height: 12),
      UiUnderlineTextButton(
        text: LocaleKeys.cancel.tr(),
        expandForText: true,
        onPressed: onCancel,
      ),
    ],
  );
}

class _SetupStore extends StatelessWidget {
  const _SetupStore({
    required this.stores,
    required this.selected,
    required this.onSelected,
    required this.onContinue,
    required this.onBack,
  });

  final List<BackupStoreKind> stores;
  final BackupStoreKind selected;
  final ValueChanged<BackupStoreKind> onSelected;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  static String _hint(BackupStoreKind store) => switch (store) {
    BackupStoreKind.iCloudKeychain => 'passkeyBackupStoreICloudHint',
    BackupStoreKind.googleDrive => 'passkeyBackupStoreDriveHint',
    BackupStoreKind.file => 'passkeyBackupStoreFileHint',
  }.tr();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TransferTitle('passkeyBackupStoreTitle'.tr()),
      const SizedBox(height: 12),
      RadioGroup<BackupStoreKind>(
        groupValue: selected,
        onChanged: (store) {
          if (store != null) onSelected(store);
        },
        child: Column(
          children: [
            for (final store in stores)
              RadioListTile<BackupStoreKind>(
                key: ValueKey('passkey-backup-store-${store.name}'),
                value: store,
                contentPadding: EdgeInsets.zero,
                activeColor: Theme.of(context).colorScheme.primary,
                title: TransferText(passkeyBackupStoreName(store), bold: true),
                subtitle: TransferText(_hint(store)),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      UiPrimaryButton(
        key: const Key('passkey-backup-store-continue'),
        text: LocaleKeys.continueText.tr(),
        expandForText: true,
        height: 50,
        onPressed: onContinue,
      ),
      const SizedBox(height: 12),
      UiUnderlineTextButton(
        text: LocaleKeys.back.tr(),
        expandForText: true,
        onPressed: onBack,
      ),
    ],
  );
}

/// Says which prompts come, in the order they open, before the first one.
class _SetupPrompts extends StatelessWidget {
  const _SetupPrompts({
    required this.store,
    required this.notice,
    required this.busy,
    required this.onContinue,
    required this.onBack,
  });

  final BackupStoreKind store;
  final _Notice? notice;
  final bool busy;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  /// Drive asks for the Google account before the passkey exists.
  static List<String> _steps(BackupStoreKind store) => [
    'passkeyBackupPromptAuthorize',
    if (store == BackupStoreKind.googleDrive) 'passkeyBackupPromptDrive',
    'passkeyBackupPromptCreate',
    'passkeyBackupPromptConfirm',
    switch (store) {
      BackupStoreKind.iCloudKeychain => 'passkeyBackupPromptSavedICloud',
      BackupStoreKind.googleDrive => 'passkeyBackupPromptSavedDrive',
      BackupStoreKind.file => 'passkeyBackupPromptSaveFile',
    },
  ];

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TransferTitle('passkeyBackupPromptsTitle'.tr()),
      const SizedBox(height: 12),
      for (final (index, key) in _steps(store).indexed)
        TransferStep(number: index + 1, text: key.tr()),
      const SizedBox(height: 16),
      if (notice case final notice?) ...[
        WalletAccessNotice(
          key: const Key('passkey-backup-setup-notice'),
          text: notice.text,
          tone: notice.tone,
        ),
        const SizedBox(height: 12),
      ],
      if (busy) ...[
        WalletAccessProgress(label: LocaleKeys.pleaseWait.tr()),
        const SizedBox(height: 12),
      ],
      UiPrimaryButton(
        key: const Key('passkey-backup-create'),
        text: notice == null
            ? LocaleKeys.continueText.tr()
            : LocaleKeys.tryAgain.tr(),
        expandForText: true,
        height: 50,
        // Stays pressable while busy so it keeps focus; repeats are ignored.
        onPressed: onContinue,
      ),
      const SizedBox(height: 12),
      UiUnderlineTextButton(
        text: LocaleKeys.back.tr(),
        expandForText: true,
        onPressed: onBack,
      ),
    ],
  );
}

class _SetupWorking extends StatelessWidget {
  const _SetupWorking({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TransferTitle('passkeyBackupWorkingTitle'.tr()),
      const SizedBox(height: 12),
      TransferText('passkeyBackupWorking'.tr()),
      const SizedBox(height: 20),
      Center(
        child: WalletAccessProgress(label: 'passkeyBackupWorkingTitle'.tr()),
      ),
      const SizedBox(height: 20),
      UiUnderlineTextButton(
        key: const Key('passkey-backup-working-cancel'),
        text: LocaleKeys.cancel.tr(),
        expandForText: true,
        onPressed: onCancel,
      ),
    ],
  );
}

/// Where restoring will work, then the step that proves it.
class _SetupDone extends StatelessWidget {
  const _SetupDone({
    required this.entry,
    required this.notice,
    required this.busy,
    required this.needsFile,
    required this.onSaveFile,
    required this.onDone,
  });

  final PasskeyBackupEntry entry;
  final _Notice? notice;
  final bool busy;
  final bool needsFile;
  final VoidCallback onSaveFile;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final provider = entry.providerName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TransferTitle('passkeyBackupDoneTitle'.tr()),
        const SizedBox(height: 12),
        TransferText(
          switch (entry.store) {
            BackupStoreKind.iCloudKeychain => 'passkeyBackupDoneICloud',
            BackupStoreKind.googleDrive => 'passkeyBackupDoneDrive',
            BackupStoreKind.file => 'passkeyBackupDoneFile',
          }.tr(),
        ),
        if (provider != null) ...[
          const SizedBox(height: 8),
          TransferText('passkeyBackupDoneProvider'.tr(args: [provider])),
        ],
        if (!entry.synced) ...[
          const SizedBox(height: 12),
          WalletAccessNotice(
            text: 'passkeyBackupDoneNotSynced'.tr(),
            tone: WalletAccessTone.warning,
            announce: false,
          ),
        ],
        const SizedBox(height: 16),
        _Heading('passkeyBackupDoneNextTitle'.tr()),
        TransferText('passkeyBackupDoneNext'.tr()),
        const SizedBox(height: 16),
        if (notice case final notice?) ...[
          WalletAccessNotice(
            key: const Key('passkey-backup-done-notice'),
            text: notice.text,
            tone: notice.tone,
          ),
          const SizedBox(height: 12),
        ],
        if (busy) ...[
          WalletAccessProgress(label: LocaleKeys.pleaseWait.tr()),
          const SizedBox(height: 12),
        ],
        if (needsFile)
          UiPrimaryButton(
            key: const Key('passkey-backup-done-save-file'),
            text: 'passkeyBackupSaveFileAction'.tr(),
            prefix: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.file_download_outlined, size: 20),
            ),
            expandForText: true,
            height: 50,
            onPressed: onSaveFile,
          )
        else
          UiPrimaryButton(
            key: const Key('passkey-backup-done'),
            text: LocaleKeys.done.tr(),
            expandForText: true,
            height: 50,
            onPressed: onDone,
          ),
        if (needsFile) ...[
          const SizedBox(height: 12),
          UiUnderlineTextButton(
            key: const Key('passkey-backup-done-later'),
            text: 'passkeyBackupSaveFileLater'.tr(),
            expandForText: true,
            onPressed: onDone,
          ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Semantics(header: true, child: TransferText(text, bold: true)),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ExcludeSemantics(child: TransferText('•')),
        const SizedBox(width: 8),
        Expanded(child: TransferText(text)),
      ],
    ),
  );
}
