import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_backup/passkey_backup_types.dart';

String passkeyBackupStoreName(BackupStoreKind store) => switch (store) {
  BackupStoreKind.iCloudKeychain => 'passkeyBackupStoreICloud',
  BackupStoreKind.googleDrive => 'passkeyBackupStoreDrive',
  BackupStoreKind.file => 'passkeyBackupStoreFile',
}.tr();

String passkeyBackupDate(DateTime date) =>
    DateFormat.yMMMd().format(date.toLocal());

/// One message per failure, each ending in what to do next. [store] names
/// the place that could not be reached.
String passkeyBackupFailureText(Object error, {BackupStoreKind? store}) {
  if (error is PasskeyBackupException) {
    return switch (error.failure) {
      PasskeyBackupFailure.notConfigured =>
        'passkeyBackupFailureNotConfigured'.tr(),
      PasskeyBackupFailure.unavailable =>
        'passkeyBackupFailureUnavailable'.tr(),
      PasskeyBackupFailure.canceled => 'passkeyBackupFailureCanceled'.tr(),
      PasskeyBackupFailure.prfUnavailable =>
        'passkeyBackupFailurePrfUnavailable'.tr(),
      PasskeyBackupFailure.localOnly => 'passkeyBackupFailureLocalOnly'.tr(),
      PasskeyBackupFailure.createdElsewhere =>
        'passkeyBackupFailureCreatedElsewhere'.tr(),
      PasskeyBackupFailure.notReproducible =>
        'passkeyBackupFailureNotReproducible'.tr(),
      PasskeyBackupFailure.storeUnavailable =>
        store == null
            ? 'passkeyBackupFailureStoreUnavailableAny'.tr()
            : 'passkeyBackupFailureStoreUnavailable'.tr(
                args: [passkeyBackupStoreName(store)],
              ),
      PasskeyBackupFailure.storageFailed =>
        'passkeyBackupFailureStorageFailed'.tr(),
      PasskeyBackupFailure.noBackupFound =>
        'passkeyBackupFailureNoBackupFound'.tr(),
      PasskeyBackupFailure.wrongPasskey =>
        'passkeyBackupFailureWrongPasskey'.tr(),
      PasskeyBackupFailure.damaged => 'passkeyBackupFailureDamaged'.tr(),
      PasskeyBackupFailure.otherRelyingParty =>
        'passkeyBackupFailureOtherRelyingParty'.tr(),
      PasskeyBackupFailure.newerVersion =>
        'passkeyBackupFailureNewerVersion'.tr(),
    };
  }
  if (error is WalletAccessException) {
    return switch (error.failure) {
      WalletAccessFailure.canceled => 'passkeyBackupFailureCanceled'.tr(),
      WalletAccessFailure.busy => 'authProtectionBusy'.tr(),
      WalletAccessFailure.staleOperation =>
        'passkeyBackupFailureInterrupted'.tr(),
      WalletAccessFailure.prfUnavailable =>
        'passkeyBackupFailurePrfUnavailable'.tr(),
      WalletAccessFailure.passkeyNotFound =>
        'passkeyBackupFailureWrongPasskey'.tr(),
      WalletAccessFailure.unavailable => 'passkeyBackupFailureUnavailable'.tr(),
      _ => 'passkeyBackupFailureGeneric'.tr(),
    };
  }
  return 'passkeyBackupFailureGeneric'.tr();
}

/// Runs [action], whose system prompts (passkey, Google sign-in) this app
/// started, so a prompt covering the app is not taken for the user leaving.
Future<T> runPasskeyBackupPrompt<T>(
  BuildContext context,
  Future<T> Function() action,
) {
  final coordinator = context.read<WalletAccessService?>()?.unlockCoordinator;
  return coordinator == null ? action() : coordinator.runSystemPrompt(action);
}
