import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_access/wallet_passkey_icon.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_file.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_setup.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_text.dart';

part 'passkey_backup_entry_tile.dart';

typedef _Notice = ({String text, WalletAccessTone tone});

/// Passkey backups of the open wallet. Shown only where this device can make
/// one, and only for a wallet with a seed of its own.
class PasskeyBackupSection extends StatelessWidget {
  const PasskeyBackupSection({this.fileSaver, super.key});

  final GuardedFileSaver? fileSaver;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PasskeyBackupController?>();
    if (controller == null) return const SizedBox.shrink();
    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, auth) {
        final user = auth.currentUser;
        if (user == null ||
            TransferWalletType.fromWalletType(user.wallet.config.type) ==
                null) {
          return const SizedBox.shrink();
        }
        final walletKey = WalletAccessService.entryId(user);
        return _PasskeyBackupPanel(
          key: ValueKey(walletKey),
          controller: controller,
          walletKey: walletKey,
          fileSaver: fileSaver,
        );
      },
    );
  }
}

class _PasskeyBackupPanel extends StatefulWidget {
  const _PasskeyBackupPanel({
    required this.controller,
    required this.walletKey,
    required this.fileSaver,
    super.key,
  });

  final PasskeyBackupController controller;
  final String walletKey;
  final GuardedFileSaver? fileSaver;

  @override
  State<_PasskeyBackupPanel> createState() => _PasskeyBackupPanelState();
}

class _PasskeyBackupPanelState extends State<_PasskeyBackupPanel> {
  PasskeyBackupAvailability? _availability;
  List<PasskeyBackupEntry> _entries = const [];
  bool _loadFailed = false;

  /// The entry an action is running for. Buttons stay pressable so they keep
  /// focus; a second press while busy does nothing.
  String? _busyId;
  ({String? entryId, _Notice notice})? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    PasskeyBackupAvailability availability;
    try {
      availability = await widget.controller.availability();
    } on Exception {
      availability = PasskeyBackupAvailability.none;
    }
    // Entries first, so the section never shows "off" before its list.
    if (availability.canCreate) await _loadEntries();
    if (mounted) setState(() => _availability = availability);
  }

  Future<void> _loadEntries() async {
    try {
      final entries = await widget.controller.backupsFor(widget.walletKey);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loadFailed = false;
      });
    } on Exception {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _run(
    PasskeyBackupEntry entry,
    Future<_Notice> Function() action,
  ) async {
    if (_busyId != null) return;
    setState(() {
      _busyId = entry.id;
      _notice = null;
    });
    final notice = await action();
    if (!mounted) return;
    await _loadEntries();
    if (!mounted) return;
    final stillListed = _entries.any((item) => item.id == entry.id);
    setState(() {
      _busyId = null;
      _notice = (entryId: stillListed ? entry.id : null, notice: notice);
    });
  }

  Future<void> _check(PasskeyBackupEntry entry) => _run(entry, () async {
    try {
      await runPasskeyBackupPrompt(
        context,
        () => widget.controller.check(entry),
      );
      return (
        text: 'passkeyBackupCheckOk'.tr(),
        tone: WalletAccessTone.success,
      );
    } on Exception catch (error) {
      return (
        text: passkeyBackupFailureText(error, store: entry.store),
        tone: WalletAccessTone.error,
      );
    }
  });

  Future<void> _saveFile(PasskeyBackupEntry entry) => _run(entry, () async {
    final outcome = await savePasskeyBackupFile(
      context,
      controller: widget.controller,
      entry: entry,
      saver: widget.fileSaver,
    );
    return passkeyBackupFileNotice(outcome);
  });

  Future<void> _remove(PasskeyBackupEntry entry) async {
    if (_busyId != null) return;
    final confirmed = await _confirmRemoval(context, entry);
    if (!mounted || confirmed != true) return;
    await _run(entry, () async {
      try {
        await widget.controller.remove(entry);
        return (
          text: 'passkeyBackupRemoved'.tr(),
          tone: WalletAccessTone.success,
        );
      } on Exception catch (error) {
        return (
          text: passkeyBackupFailureText(error, store: entry.store),
          tone: WalletAccessTone.error,
        );
      }
    });
  }

  Future<void> _setUp() async {
    final availability = _availability;
    if (_busyId != null || availability == null) return;
    await openPasskeyBackupSetup(
      context,
      controller: widget.controller,
      stores: availability.stores,
      walletKey: widget.walletKey,
      fileSaver: widget.fileSaver,
    );
    if (mounted) await _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    if (availability == null || !availability.canCreate) {
      return const SizedBox.shrink();
    }
    final notice = _notice;
    final sectionNotice = notice != null && notice.entryId == null
        ? notice.notice
        : null;
    final details = <Widget>[
      for (final entry in _entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _BackupEntryTile(
            key: ValueKey('passkey-backup-entry-${entry.id}'),
            entry: entry,
            busy: _busyId == entry.id,
            notice: notice?.entryId == entry.id ? notice?.notice : null,
            onCheck: () => _check(entry),
            onSaveFile: () => _saveFile(entry),
            onRemove: () => _remove(entry),
          ),
        ),
      if (_loadFailed) ...[
        WalletAccessNotice(
          key: const Key('passkey-backup-load-failed'),
          text: 'passkeyBackupLoadFailed'.tr(),
          tone: WalletAccessTone.error,
        ),
        const SizedBox(height: 8),
        SecuritySecondaryButton(
          text: LocaleKeys.tryAgain.tr(),
          onPressed: _load,
        ),
      ],
      if (sectionNotice != null) ...[
        WalletAccessNotice(
          key: const Key('passkey-backup-notice'),
          text: sectionNotice.text,
          tone: sectionNotice.tone,
        ),
        const SizedBox(height: 12),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final setUp = SecuritySecondaryButton(
            key: const Key('passkey-backup-set-up'),
            width: SecurityActionPlate.isWide(context, constraints)
                ? SecurityActionPlate.actionWidth
                : double.infinity,
            text: _entries.isEmpty
                ? 'passkeyBackupSetUp'.tr()
                : 'passkeyBackupAddAnother'.tr(),
            onPressed: _setUp,
          );
          return SecurityActionPlate(
            key: const Key('passkey-backup-section'),
            icon: const WalletPasskeyIcon(size: 50),
            title: 'passkeyBackupTitle'.tr(),
            description: 'passkeyBackupDescription'.tr(),
            status: _entries.isEmpty && !_loadFailed
                ? WalletAccessNotice(
                    key: const Key('passkey-backup-status'),
                    text: 'passkeyBackupStatusOff'.tr(),
                    announce: false,
                  )
                : null,
            // With backups listed, adding another comes after them.
            trailingWidget: _entries.isEmpty ? setUp : null,
            details: details.isEmpty && _entries.isEmpty
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...details,
                      if (_entries.isNotEmpty)
                        Align(alignment: Alignment.centerLeft, child: setUp),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

Future<bool?> _confirmRemoval(BuildContext context, PasskeyBackupEntry entry) =>
    AppDialog.show<bool>(
      context: context,
      width: 420,
      child: Builder(
        builder: (dialogContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'passkeyBackupRemoveTitle'.tr(),
                style: SecuritySectionText.title(dialogContext),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'passkeyBackupRemoveBody'.tr(),
              style: SecuritySectionText.body(dialogContext),
            ),
            if (entry.store == BackupStoreKind.file) ...[
              const SizedBox(height: 8),
              Text(
                'passkeyBackupRemoveFileNote'.tr(),
                key: const Key('passkey-backup-remove-file-note'),
                style: SecuritySectionText.body(dialogContext),
              ),
            ],
            const SizedBox(height: 20),
            UiPrimaryButton(
              key: const Key('passkey-backup-remove-confirm'),
              text: 'passkeyBackupRemoveConfirm'.tr(),
              expandForText: true,
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
            const SizedBox(height: 8),
            UiUnderlineTextButton(
              key: const Key('passkey-backup-remove-cancel'),
              text: LocaleKeys.cancel.tr(),
              expandForText: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
          ],
        ),
      ),
    );
