import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_file.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_text.dart';
import 'package:web_dex/views/wallet_move/read_wallet_transfer_secret.dart';
import 'package:web_dex/views/wallet_move/transfer_widgets.dart';

part 'passkey_backup_setup_steps.dart';

typedef _Notice = ({String text, WalletAccessTone tone});

/// Opens passkey backup setup over Security settings.
Future<void> openPasskeyBackupSetup(
  BuildContext context, {
  required PasskeyBackupController controller,
  required List<BackupStoreKind> stores,
  required String walletKey,
  GuardedFileSaver? fileSaver,
}) => openTransferFlow(
  context,
  title: 'passkeyBackupSetupTitle'.tr(),
  builder: (context) => PasskeyBackupSetup(
    controller: controller,
    stores: stores,
    walletKey: walletKey,
    fileSaver: fileSaver,
    onClose: () => closeTransferFlow(context),
  ),
);

/// Explains what a passkey backup is and who can use it, lets the user pick
/// where it is kept, says which prompts come, then creates it.
class PasskeyBackupSetup extends StatefulWidget {
  const PasskeyBackupSetup({
    required this.controller,
    required this.stores,
    required this.walletKey,
    required this.onClose,
    this.fileSaver,
    this.readSecret = readWalletTransferSecretResult,
    super.key,
  });

  final PasskeyBackupController controller;

  /// Usable stores, in the order the controller offers them.
  final List<BackupStoreKind> stores;
  final String walletKey;
  final VoidCallback onClose;
  final GuardedFileSaver? fileSaver;
  final WalletSecretReader readSecret;

  @override
  State<PasskeyBackupSetup> createState() => _PasskeyBackupSetupState();
}

enum _SetupStep { explain, store, prompts, working, done }

class _PasskeyBackupSetupState extends State<PasskeyBackupSetup> {
  _SetupStep _step = _SetupStep.explain;
  late BackupStoreKind _store = _defaultStore(widget.stores);
  PasskeyBackupEntry? _entry;
  _Notice? _notice;
  bool _busy = false;
  bool _fileSaved = false;

  /// iCloud Keychain on Apple devices, then Google Drive, then a file.
  static BackupStoreKind _defaultStore(List<BackupStoreKind> stores) => const [
    BackupStoreKind.iCloudKeychain,
    BackupStoreKind.googleDrive,
    BackupStoreKind.file,
  ].firstWhere(stores.contains, orElse: () => BackupStoreKind.file);

  bool get _choosesStore => widget.stores.length > 1;

  @override
  void dispose() {
    // A closed page must not leave a passkey prompt waiting for it.
    if (_step == _SetupStep.working) widget.controller.cancel().ignore();
    super.dispose();
  }

  void _go(_SetupStep step) => setState(() {
    _step = step;
    _notice = null;
  });

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    final read = await widget.readSecret(context);
    if (!mounted) return;
    final WalletTransferSecret secret;
    switch (read) {
      case WalletSecretReady(secret: final ready):
        secret = ready;
      case WalletSecretNotRead(:final reason):
        setState(() {
          _busy = false;
          _notice = _unreadNotice(reason);
        });
        return;
    }
    setState(() {
      _busy = false;
      _step = _SetupStep.working;
    });
    final PasskeyBackupEntry entry;
    try {
      entry = await runPasskeyBackupPrompt(
        context,
        () => widget.controller.create(
          walletKey: widget.walletKey,
          secret: secret,
          store: _store,
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      final canceled =
          error is PasskeyBackupException &&
          error.failure == PasskeyBackupFailure.canceled;
      setState(() {
        _step = _SetupStep.prompts;
        _notice = (
          text: passkeyBackupFailureText(error, store: _store),
          tone: canceled ? WalletAccessTone.info : WalletAccessTone.error,
        );
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _step = _SetupStep.done;
    });
    // A file backup exists only in this app until it is saved.
    if (entry.store == BackupStoreKind.file) await _saveFileOnceInFront();
  }

  static _Notice? _unreadNotice(WalletSecretUnread reason) => switch (reason) {
    WalletSecretUnread.canceled => null,
    WalletSecretUnread.interrupted => (
      text: 'passkeyBackupFailureInterrupted'.tr(),
      tone: WalletAccessTone.warning,
    ),
    WalletSecretUnread.unsupported => (
      text: 'passkeyBackupUnsupportedWallet'.tr(),
      tone: WalletAccessTone.error,
    ),
    WalletSecretUnread.failed => (
      text: 'passkeyBackupReadFailed'.tr(),
      tone: WalletAccessTone.error,
    ),
  };

  /// The save dialog can open only once the passkey prompts have handed the
  /// app back. If that takes too long, the save button is still there.
  Future<void> _saveFileOnceInFront() async {
    final coordinator = context.read<WalletAccessService?>()?.unlockCoordinator;
    if (coordinator != null && !coordinator.state.isForeground) {
      final back = Completer<void>();
      final changes = coordinator.changes.listen((state) {
        if (state.isForeground && !back.isCompleted) back.complete();
      });
      try {
        await back.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        return;
      } finally {
        await changes.cancel();
      }
    }
    if (mounted) await _saveFile();
  }

  Future<void> _saveFile() async {
    final entry = _entry;
    if (_busy || entry == null) return;
    setState(() => _busy = true);
    final outcome = await savePasskeyBackupFile(
      context,
      controller: widget.controller,
      entry: entry,
      saver: widget.fileSaver,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _fileSaved = outcome == PasskeyBackupFileOutcome.saved;
      _notice = passkeyBackupFileNotice(outcome);
    });
  }

  String? get _stepAnnouncement => switch (_step) {
    _SetupStep.explain => null,
    _SetupStep.store => 'passkeyBackupStoreTitle'.tr(),
    _SetupStep.prompts => 'passkeyBackupPromptsTitle'.tr(),
    _SetupStep.working => 'passkeyBackupWorkingTitle'.tr(),
    _SetupStep.done => 'passkeyBackupDoneTitle'.tr(),
  };

  @override
  Widget build(BuildContext context) => TransferStepFocus(
    key: ValueKey(_step),
    announce: _stepAnnouncement,
    child: switch (_step) {
      _SetupStep.explain => _SetupExplain(
        // Stolen Device Protection is on iPhone, not iPad.
        showStolenDeviceTip:
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.iOS &&
            MediaQuery.sizeOf(context).shortestSide < 600,
        onContinue: () =>
            _go(_choosesStore ? _SetupStep.store : _SetupStep.prompts),
        onCancel: widget.onClose,
      ),
      _SetupStep.store => _SetupStore(
        stores: widget.stores,
        selected: _store,
        onSelected: (store) => setState(() => _store = store),
        onContinue: () => _go(_SetupStep.prompts),
        onBack: () => _go(_SetupStep.explain),
      ),
      _SetupStep.prompts => _SetupPrompts(
        store: _store,
        notice: _notice,
        busy: _busy,
        onContinue: _create,
        onBack: () =>
            _go(_choosesStore ? _SetupStep.store : _SetupStep.explain),
      ),
      _SetupStep.working => _SetupWorking(
        onCancel: () => widget.controller.cancel().ignore(),
      ),
      _SetupStep.done => _SetupDone(
        entry: _entry!,
        notice: _notice,
        busy: _busy,
        needsFile: _entry!.store == BackupStoreKind.file && !_fileSaved,
        onSaveFile: _saveFile,
        onDone: widget.onClose,
      ),
    },
  );
}
