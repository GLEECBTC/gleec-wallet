part of 'passkey_backup_section.dart';

/// One backup: where it is, what holds its passkey, and whether it can be
/// relied on. Only a ready backup says whether it synced or opened here.
class _BackupEntryTile extends StatelessWidget {
  const _BackupEntryTile({
    required this.entry,
    required this.busy,
    required this.notice,
    required this.onCheck,
    required this.onSaveFile,
    required this.onRemove,
    super.key,
  });

  final PasskeyBackupEntry entry;
  final bool busy;
  final _Notice? notice;
  final VoidCallback onCheck;
  final VoidCallback onSaveFile;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final provider = entry.providerName;
    final checked = entry.checkedHere;
    final ready = entry.state == PasskeyBackupEntryState.ready;
    final supporting = SecuritySectionText.supporting(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passkeyBackupStoreName(entry.store),
                  style: SecuritySectionText.label(context),
                ),
                const SizedBox(height: 4),
                Text(
                  provider == null
                      ? 'passkeyBackupEntryProviderUnknown'.tr()
                      : 'passkeyBackupEntryProvider'.tr(args: [provider]),
                  style: supporting,
                ),
                Text(
                  'passkeyBackupEntryCreated'.tr(
                    args: [passkeyBackupDate(entry.created)],
                  ),
                  style: supporting,
                ),
                if (ready) ...[
                  Text(
                    entry.synced
                        ? 'passkeyBackupEntrySynced'.tr()
                        : 'passkeyBackupEntryNotSynced'.tr(),
                    style: supporting,
                  ),
                  Text(
                    checked == null
                        ? 'passkeyBackupEntryNotChecked'.tr()
                        : 'passkeyBackupEntryChecked'.tr(
                            args: [passkeyBackupDate(checked)],
                          ),
                    key: const Key('passkey-backup-entry-checked'),
                    style: supporting,
                  ),
                ],
              ],
            ),
          ),
          if (!ready) ...[
            const SizedBox(height: 8),
            WalletAccessNotice(
              key: const Key('passkey-backup-entry-state'),
              text: switch (entry.state) {
                PasskeyBackupEntryState.fileNotSaved =>
                  'passkeyBackupEntryFileNotSaved'.tr(),
                _ => 'passkeyBackupEntryUnfinished'.tr(),
              },
              tone: WalletAccessTone.warning,
              announce: false,
            ),
          ],
          if (entry.state != PasskeyBackupEntryState.fileNotSaved) ...[
            const SizedBox(height: 8),
            Text('passkeyBackupCheckHint'.tr(), style: supporting),
          ],
          if (busy) ...[
            const SizedBox(height: 8),
            WalletAccessProgress(
              label: LocaleKeys.pleaseWait.tr(),
              showLabel: true,
            ),
          ],
          if (notice case final notice?) ...[
            const SizedBox(height: 8),
            WalletAccessNotice(
              key: const Key('passkey-backup-entry-notice'),
              text: notice.text,
              tone: notice.tone,
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 640
                  ? (constraints.maxWidth - 16) / 3
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._actions(width),
                  _Named(
                    label: 'passkeyBackupRemoveNamed'.tr(args: [_date]),
                    onPressed: onRemove,
                    child: SecuritySecondaryButton(
                      key: const Key('passkey-backup-remove'),
                      width: width,
                      icon: const Icon(Icons.delete_outline),
                      text: 'passkeyBackupRemove'.tr(),
                      onPressed: onRemove,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String get _date => passkeyBackupDate(entry.created);

  Widget _check(double width) => _Named(
    label: 'passkeyBackupCheckNamed'.tr(args: [_date]),
    onPressed: onCheck,
    child: SecuritySecondaryButton(
      key: const Key('passkey-backup-check'),
      width: width,
      text: 'passkeyBackupCheck'.tr(),
      onPressed: onCheck,
    ),
  );

  /// Every state can be removed; what else it offers depends on the state.
  List<Widget> _actions(double width) => switch (entry.state) {
    // The record lives only in this app: saving it is the one next step.
    PasskeyBackupEntryState.fileNotSaved => [
      _Named(
        label: 'passkeyBackupSaveFileNamed'.tr(args: [_date]),
        onPressed: onSaveFile,
        child: UiPrimaryButton(
          key: const Key('passkey-backup-save-file'),
          width: width,
          expandForText: true,
          prefix: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.file_download_outlined, size: 20),
          ),
          text: 'passkeyBackupSaveFileNow'.tr(),
          onPressed: onSaveFile,
        ),
      ),
    ],
    // Checking proves the stored copy opens, which finishes it.
    PasskeyBackupEntryState.unfinished => [_check(width)],
    PasskeyBackupEntryState.ready => [
      _check(width),
      _Named(
        label: 'passkeyBackupSaveFileNamed'.tr(args: [_date]),
        onPressed: onSaveFile,
        child: SecuritySecondaryButton(
          key: const Key('passkey-backup-save-file'),
          width: width,
          icon: const Icon(Icons.file_download_outlined),
          text: 'passkeyBackupSaveFile'.tr(),
          onPressed: onSaveFile,
        ),
      ),
    ],
  };
}

/// A button read out with the backup it acts on: three Removes in a list
/// are otherwise indistinguishable to a screen reader.
class _Named extends StatelessWidget {
  const _Named({
    required this.label,
    required this.onPressed,
    required this.child,
  });

  final String label;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: label,
    onTap: onPressed,
    child: ExcludeSemantics(child: child),
  );
}
