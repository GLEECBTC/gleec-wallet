import 'package:flutter/widgets.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';

/// Requests the provider's own save prompt after durable wallet creation.
/// No app confirmation, credential reveal, or additional save action is needed.
/// A provider refusal or failure must never turn creation into an error.
Future<void> offerWalletPasswordSave(
  BuildContext context, {
  required WalletAccessService access,
  required WalletId walletId,
  String? expectedEntryId,
}) async {
  if (!context.mounted) return;
  void Function()? ensureCurrent;
  try {
    ensureCurrent = access.captureSensitiveOperation(walletId);
    if (expectedEntryId != null) {
      final status = await access.status(walletId: walletId);
      if (status.entryId != expectedEntryId) return;
    }
    if (!context.mounted) return;
    ensureCurrent();
    await access.saveToPasswordManager(walletId: walletId);
  } on WalletAccessException catch (error) {
    if (error.failure == WalletAccessFailure.staleOperation ||
        error.failure == WalletAccessFailure.busy) {
      return;
    }
    try {
      if (!context.mounted) return;
      ensureCurrent?.call();
      await access.recordPasswordManagerOutcome(
        walletId: walletId,
        outcome: error.failure == WalletAccessFailure.canceled
            ? PasswordManagerOutcome.declined
            : PasswordManagerOutcome.failed,
      );
    } catch (_) {
      // Optional provider bookkeeping cannot affect the committed wallet.
    }
  } catch (_) {
    // Provider failures carry no credentials into UI diagnostics.
  }
}
