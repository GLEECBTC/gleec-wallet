import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';

enum PasskeyBackupFileOutcome { saved, canceled, unconfirmed, failed }

/// The record's name in every store, so a saved file and a synced copy match.
/// It names no wallet, as the record itself does not.
String passkeyBackupFileName(PasskeyBackupEntry entry) =>
    'gleec-passkey-backup-${entry.id}.json';

/// Saves the sealed record as a file the way the encrypted wallet file is
/// saved: the destination dialog is bound to this wallet's session and the
/// write is refused once the wallet locks or changes. A file backup counts
/// as saved only once a save completes.
Future<PasskeyBackupFileOutcome> savePasskeyBackupFile(
  BuildContext context, {
  required PasskeyBackupController controller,
  required PasskeyBackupEntry entry,
  GuardedFileSaver? saver,
}) async {
  final walletId = context.read<AuthBloc>().state.currentUser?.walletId;
  final access = context.read<WalletAccessService?>();
  if (walletId == null) return PasskeyBackupFileOutcome.failed;
  try {
    final authorization = await access?.captureSensitiveExport(walletId);
    final raw = await controller.exportFile(entry);
    authorization?.ensureCurrent();
    final outcome = await (saver ?? GuardedFileSaver.fromPlatform()).save(
      fileName: passkeyBackupFileName(entry),
      data: raw,
      beforeWrite: () async => authorization?.ensureCurrent(),
      beforeCommit: () => authorization?.ensureCurrent(),
      selectDestination: authorization?.selectDestination,
    );
    if (outcome == FileSaveOutcome.completed &&
        (entry.store == BackupStoreKind.file ||
            entry.state == PasskeyBackupEntryState.fileNotSaved)) {
      try {
        await controller.markFileSaved(entry);
      } on Exception {
        // Saved, but still listed as not saved: say it is unconfirmed.
        return PasskeyBackupFileOutcome.unconfirmed;
      }
    }
    return switch (outcome) {
      FileSaveOutcome.completed => PasskeyBackupFileOutcome.saved,
      FileSaveOutcome.cancelled => PasskeyBackupFileOutcome.canceled,
      FileSaveOutcome.unconfirmed => PasskeyBackupFileOutcome.unconfirmed,
    };
  } on Exception {
    return PasskeyBackupFileOutcome.failed;
  }
}

({String text, WalletAccessTone tone}) passkeyBackupFileNotice(
  PasskeyBackupFileOutcome outcome,
) => switch (outcome) {
  PasskeyBackupFileOutcome.saved => (
    text: 'passkeyBackupFileSaved'.tr(),
    tone: WalletAccessTone.success,
  ),
  PasskeyBackupFileOutcome.canceled => (
    text: 'passkeyBackupFileCanceled'.tr(),
    tone: WalletAccessTone.info,
  ),
  PasskeyBackupFileOutcome.unconfirmed => (
    text: 'passkeyBackupFileUnconfirmed'.tr(),
    tone: WalletAccessTone.warning,
  ),
  PasskeyBackupFileOutcome.failed => (
    text: 'passkeyBackupFileFailed'.tr(),
    tone: WalletAccessTone.error,
  ),
};
