import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_legacy_wallet_migration/komodo_legacy_wallet_migration.dart';
import 'package:web_dex/model/wallet.dart';

/// Result of preparing a legacy wallet for KDF migration.
@immutable
class PreparedLegacyMigration {
  const PreparedLegacyMigration({
    required this.sourceWallet,
    required this.seedPhrase,
    required this.suggestedTargetWalletName,
    required this.requiresNameConfirmation,
    required this.requiresNewKdfPassword,
    this.requestedZhtlcCoinIds = const <String>[],
    this.zhtlcSyncPolicy,
    this.legacyWalletExtras = const <String, dynamic>{},
    this.nativeLegacySecrets,
    this.alreadyMigratedWalletName,
  });

  final Wallet sourceWallet;
  final String seedPhrase;
  final LegacyWalletSecrets? nativeLegacySecrets;
  final String suggestedTargetWalletName;
  final bool requiresNameConfirmation;
  final bool requiresNewKdfPassword;
  final List<String> requestedZhtlcCoinIds;
  final ZhtlcRecurringSyncPolicy? zhtlcSyncPolicy;
  final Map<String, dynamic> legacyWalletExtras;
  final String? alreadyMigratedWalletName;

  bool get needsCompatibilityPrompt =>
      requiresNameConfirmation || requiresNewKdfPassword;

  bool get shouldRouteToExistingWallet =>
      alreadyMigratedWalletName != null &&
      alreadyMigratedWalletName!.isNotEmpty;
}
