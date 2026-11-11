import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';

/// Asks for the wallet password and returns the plaintext recovery phrase, or
/// null if the user cancelled or the phrase could not be read.
///
/// Deliberately does **not** fetch per-coin private keys. The settings page
/// pairs this with a loop over every parent coin calling `showPrivKey`, which
/// is an N-RPC round trip the seed-backup flow has no use for - `SeedShow`
/// renders nothing for an empty key map.
Future<String?> promptForPlaintextMnemonic(BuildContext context) async {
  final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
  final session = await sdk.auth.captureSessionContext();
  if (!context.mounted) return null;
  final password = await walletPasswordDialog(context);
  if (password == null) return null;
  if (!context.mounted) return null;

  try {
    final ensureAccess =
        context.read<WalletAccessService?>()?.captureSensitiveOperation(
          session.walletId,
        ) ??
        WalletOperationGate.instance.capture().ensureCurrent;
    void ensureCurrent() {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!context.mounted ||
          !sdk.auth.isSessionContextCurrent(session) ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
      ensureAccess();
    }

    ensureCurrent();
    final mnemonic = await RpcDispatchGuard.run(
      ensureCurrent,
      () => sdk.auth.getMnemonicPlainText(password),
      methods: const {'get_mnemonic'},
    );
    ensureCurrent();
    final plaintext = mnemonic.plaintextMnemonic;
    if (plaintext == null || plaintext.isEmpty) return null;
    return plaintext;
  } on WalletAccessException {
    return null;
  } on WalletOperationDenied {
    return null;
  } on RpcDispatchRejected {
    return null;
  } on AuthSessionChangedException {
    return null;
  }
}
