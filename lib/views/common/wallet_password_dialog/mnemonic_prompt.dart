import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';

/// Asks for the wallet password and returns the plaintext recovery phrase, or
/// null if the user cancelled or the phrase could not be read.
///
/// Deliberately does **not** fetch per-coin private keys. The settings page
/// pairs this with a loop over every parent coin calling `showPrivKey`, which
/// is an N-RPC round trip the seed-backup flow has no use for - `SeedShow`
/// renders nothing for an empty key map.
Future<String?> promptForPlaintextMnemonic(BuildContext context) async {
  final password = await walletPasswordDialog(context);
  if (password == null) return null;
  if (!context.mounted) return null;

  final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
  final mnemonic = await sdk.auth.getMnemonicPlainText(password);
  final plaintext = mnemonic.plaintextMnemonic;
  if (plaintext == null || plaintext.isEmpty) return null;
  return plaintext;
}
