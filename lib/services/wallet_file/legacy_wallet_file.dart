import 'dart:convert';

import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_file/wallet_file_format.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';

/// Reads a file from before version 2: the wallet config encrypted with
/// [EncryptionTool], its phrase encrypted again under the same password.
/// Neither layer is authenticated, so the config's `type` may have been
/// rewritten without the password.
Future<WalletConfig> openLegacyWalletFile(
  String password,
  String content,
) async {
  final tool = EncryptionTool();
  final outer = await tool.decryptData(
    password,
    normalizeWalletFileText(content),
  );
  if (outer == null) {
    throw const WalletFileException(WalletFileFailure.cannotOpen);
  }
  final WalletConfig config;
  try {
    config = WalletConfig.fromJson(jsonDecode(outer) as Map<String, dynamic>);
  } catch (_) {
    // Without a MAC, a wrong password can still decrypt to valid padding.
    throw const WalletFileException(WalletFileFailure.cannotOpen);
  }
  final seed = await tool.decryptData(password, config.seedPhrase);
  if (seed == null || seed.isEmpty) {
    throw const WalletFileException(WalletFileFailure.damaged);
  }
  return config..seedPhrase = seed;
}
