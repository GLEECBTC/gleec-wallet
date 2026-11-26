import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_access/wallet_passkey_icon.dart';
import 'package:web_dex/views/wallet_backup/passkey_backup_text.dart';
import 'package:web_dex/views/wallet_move/transfer_import_review.dart';
import 'package:web_dex/views/wallet_move/transfer_widgets.dart';

part 'passkey_backup_restore_steps.dart';

typedef _Notice = ({String text, WalletAccessTone tone});

/// Restores a wallet from a passkey backup, opened from the import options:
/// where to look, which backup, one passkey prompt, then the review.
class PasskeyBackupRestore extends StatefulWidget {
  const PasskeyBackupRestore({
    required this.onCancel,
    this.fileLoader,
    super.key,
  });

  final VoidCallback onCancel;

  /// Picks a backup file. Defaults to the platform's picker.
  final FileLoader? fileLoader;

  @override
  State<PasskeyBackupRestore> createState() => _PasskeyBackupRestoreState();
}

enum _RestoreStep { choose, searching, pick, unlocking, review }

class _PasskeyBackupRestoreState extends State<PasskeyBackupRestore> {
  late final PasskeyBackupController _controller;
  List<BackupStoreKind> _stores = const [];
  _RestoreStep _step = _RestoreStep.choose;
  List<StoredBackup> _found = const [];
  WalletTransferSecret? _secret;
  _Notice? _notice;
  bool _storesFailed = false;

  /// A search the user walked away from answers into nothing.
  int _search = 0;

  @override
  void initState() {
    super.initState();
    _controller = context.read<PasskeyBackupController>();
    _loadStores();
  }

  @override
  void dispose() {
    if (_step == _RestoreStep.unlocking) _controller.cancel().ignore();
    _secret = null;
    super.dispose();
  }

  Future<void> _loadStores() async {
    setState(() {
      _storesFailed = false;
      _notice = null;
    });
    try {
      final availability = await _controller.availability();
      if (!mounted) return;
      setState(
        () => _stores = availability.canRestore ? availability.stores : [],
      );
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _storesFailed = true;
        _notice = _failure(error);
      });
    }
  }

  _Notice _failure(Object error, {BackupStoreKind? store}) {
    final failure = switch (error) {
      PasskeyBackupException(:final failure) => failure,
      _ => null,
    };
    return (
      // Here the passkey exists already: the fix is the one it was made in.
      text: failure == PasskeyBackupFailure.prfUnavailable
          ? 'passkeyBackupRestorePrfUnavailable'.tr()
          : passkeyBackupFailureText(error, store: store),
      tone: failure == PasskeyBackupFailure.canceled
          ? WalletAccessTone.info
          : WalletAccessTone.error,
    );
  }

  Future<void> _lookIn(BackupStoreKind store) async {
    if (store == BackupStoreKind.file) return _openFile();
    final search = ++_search;
    setState(() {
      _step = _RestoreStep.searching;
      _notice = null;
    });
    try {
      final found = await runPasskeyBackupPrompt(
        context,
        () => _controller.find(store),
      );
      if (!mounted || search != _search) return;
      if (found.isEmpty) {
        setState(() {
          _step = _RestoreStep.choose;
          _notice = (
            text: 'passkeyBackupRestoreNoneFound'.tr(
              args: [passkeyBackupStoreName(store)],
            ),
            tone: WalletAccessTone.warning,
          );
        });
        return;
      }
      setState(() {
        // Newest first: the one most likely made with today's passkey.
        _found = [...found]..sort((a, b) => b.created.compareTo(a.created));
        _step = _RestoreStep.pick;
      });
    } on Exception catch (error) {
      if (!mounted || search != _search) return;
      setState(() {
        _step = _RestoreStep.choose;
        _notice = _failure(error, store: store);
      });
    }
  }

  void _stopSearch() {
    _search++;
    setState(() => _step = _RestoreStep.choose);
  }

  Future<void> _openFile() async {
    setState(() => _notice = null);
    // Any file: a backup is .json, which the text filter takes only as
    // .txt.json. Its content is checked strictly instead.
    await (widget.fileLoader ?? FileLoader.fromPlatform()).upload(
      onUpload: (_, content) {
        if (!mounted) return;
        try {
          final backup = _controller.parseFile(content ?? '');
          setState(() {
            _found = [backup];
            _step = _RestoreStep.pick;
          });
        } on Exception catch (error) {
          setState(() => _notice = _failure(error));
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(
          () => _notice = (
            text: 'passkeyBackupRestoreFileRejected'.tr(),
            tone: WalletAccessTone.error,
          ),
        );
      },
    );
  }

  Future<void> _unlock(StoredBackup backup) async {
    if (_step == _RestoreStep.unlocking) return;
    setState(() {
      _step = _RestoreStep.unlocking;
      _notice = null;
    });
    try {
      final secret = await runPasskeyBackupPrompt(
        context,
        () => _controller.unlock(backup),
      );
      if (!mounted) return;
      setState(() {
        _secret = secret;
        _step = _RestoreStep.review;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _step = _RestoreStep.pick;
        _notice = _failure(error, store: backup.store);
      });
    }
  }

  void _chooseAgain() => setState(() {
    _found = const [];
    _notice = null;
    _step = _RestoreStep.choose;
  });

  @override
  Widget build(BuildContext context) {
    final secret = _secret;
    return TransferStepFocus(
      key: ValueKey(_step),
      announce: switch (_step) {
        _RestoreStep.choose => null,
        _RestoreStep.searching => 'passkeyBackupRestoreSearching'.tr(),
        _RestoreStep.pick => 'passkeyBackupRestoreFoundTitle'.tr(),
        _RestoreStep.unlocking => 'passkeyBackupRestoreUnlockingTitle'.tr(),
        _RestoreStep.review => 'walletTransferReviewTitle'.tr(),
      },
      child: switch (_step) {
        _RestoreStep.choose => _RestoreChoose(
          stores: _stores,
          notice: _notice,
          onChoose: _lookIn,
          onRetry: _storesFailed ? _loadStores : null,
          onCancel: widget.onCancel,
        ),
        _RestoreStep.searching => _RestoreWaiting(
          title: 'passkeyBackupRestoreTitle'.tr(),
          text: 'passkeyBackupRestoreSearching'.tr(),
          onCancel: _stopSearch,
        ),
        _RestoreStep.pick => _RestorePick(
          backups: _found,
          notice: _notice,
          onPick: _unlock,
          onChooseAgain: _chooseAgain,
        ),
        _RestoreStep.unlocking => _RestoreWaiting(
          title: 'passkeyBackupRestoreUnlockingTitle'.tr(),
          text: 'passkeyBackupRestoreUnlocking'.tr(),
          onCancel: () => _controller.cancel().ignore(),
        ),
        _RestoreStep.review when secret != null => TransferImportReview(
          secret: secret,
          source: ManagedImportSource.passkeyBackup,
          onCancel: widget.onCancel,
        ),
        _RestoreStep.review => const SizedBox.shrink(),
      },
    );
  }
}
