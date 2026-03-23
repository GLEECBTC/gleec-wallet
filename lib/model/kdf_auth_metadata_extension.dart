import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' show Asset;
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';

final Logger _walletMetadataLog = Logger('KdfAuthMetadataExtension');

extension KdfAuthMetadataExtension on KomodoDefiSdk {
  /// Checks if a wallet with the specified ID exists in the system.
  ///
  /// Returns `true` if a user with the given [walletId] is found among
  /// all registered users, `false` otherwise.
  Future<bool> walletExists(String walletId) async {
    final users = await auth.getUsers();
    return users.any((user) => user.walletId.name == walletId);
  }

  /// Returns the wallet associated with the currently authenticated user.
  ///
  /// Returns `null` if no user is currently signed in.
  Future<Wallet?> currentWallet() async {
    final user = await auth.currentUser;
    return user?.wallet;
  }

  /// Returns the stored list of wallet coin/asset IDs.
  ///
  /// If no user is signed in, returns an empty list.
  Future<List<String>> getWalletCoinIds() async {
    final user = await auth.currentUser;
    if (user == null) return [];
    return user.metadata.valueOrNull<List<String>>('activated_coins') ?? [];
  }

  /// Returns the stored list of wallet assets resolved from configuration IDs.
  ///
  /// Missing assets (for example, delisted coins) are skipped and logged for
  /// visibility.
  ///
  /// Throws [StateError] if multiple assets are found with the same configuration ID.
  Future<List<Asset>> getWalletAssets() async {
    final coinIds = await getWalletCoinIds();
    if (coinIds.isEmpty) {
      return [];
    }

    final missingCoinIds = <String>{};
    final walletAssets = <Asset>[];

    for (final coinId in coinIds) {
      final matchingAssets = assets.findAssetsByConfigId(coinId);
      if (matchingAssets.isEmpty) {
        missingCoinIds.add(coinId);
        continue;
      }

      if (matchingAssets.length > 1) {
        final assetIds = matchingAssets.map((asset) => asset.id.id).join(', ');
        final message =
            'Multiple assets found for activated coin ID "$coinId": $assetIds';
        _walletMetadataLog.shout(message);
        throw StateError(message);
      }

      walletAssets.add(matchingAssets.single);
    }

    if (missingCoinIds.isNotEmpty) {
      _walletMetadataLog.warning(
        'Skipping ${missingCoinIds.length} activated coin(s) that are no longer '
        'available in the SDK (likely delisted): '
        '${missingCoinIds.join(', ')}',
      );
    }

    return walletAssets;
  }

  /// Returns the stored list of wallet coins converted from asset configuration IDs.
  ///
  /// This method retrieves the coin IDs from user metadata and converts them
  /// to [Coin] objects. Uses `single` to maintain existing behavior which will
  /// throw an exception if multiple assets share the same ticker.
  ///
  /// Missing assets (for example, delisted coins) are skipped and logged for
  /// visibility.
  ///
  /// If no user is signed in, returns an empty list.
  ///
  /// Throws [StateError] if multiple assets are found with the same configuration ID.
  Future<List<Coin>> getWalletCoins() async {
    final walletAssets = await getWalletAssets();
    return walletAssets.map((asset) => asset.toCoin()).toList();
  }

  /// Adds new coin/asset IDs to the current user's activated coins list.
  ///
  /// This method atomically merges the provided [coins] with the existing
  /// activated coins, ensuring no duplicates and no lost writes under
  /// concurrent calls.
  ///
  /// If no user is currently signed in, the operation will throw.
  ///
  /// [coins] - An iterable of coin/asset configuration IDs to add.
  Future<void> addActivatedCoins(Iterable<String> coins) async {
    await auth.updateActiveUserKeyValue('activated_coins', (current) {
      final existing = (current as List<dynamic>?)?.cast<String>() ?? [];
      return <String>{...existing, ...coins}.toList();
    });
  }

  /// Removes specified coin/asset IDs from the current user's activated coins list.
  ///
  /// This method atomically removes all occurrences of the provided [coins]
  /// from the user's activated coins list, ensuring no lost writes under
  /// concurrent calls.
  ///
  /// If no user is currently signed in, the operation will throw.
  ///
  /// [coins] - A list of coin/asset configuration IDs to remove.
  Future<void> removeActivatedCoins(List<String> coins) async {
    await auth.updateActiveUserKeyValue('activated_coins', (current) {
      final existing = (current as List<dynamic>?)?.cast<String>() ?? [];
      final updated = existing.where((c) => !coins.contains(c)).toList();
      return updated.isEmpty ? null : updated;
    });
  }

  /// Sets the seed backup confirmation status for the current user.
  ///
  /// This method stores whether the user has confirmed backing up their seed phrase.
  /// This is typically used to track wallet security compliance.
  ///
  /// If no user is currently signed in, the operation will complete but have no effect.
  ///
  /// [hasBackup] - Whether the seed has been backed up. Defaults to `true`.
  Future<void> confirmSeedBackup({bool hasBackup = true}) async {
    await auth.setOrRemoveActiveUserKeyValue('has_backup', hasBackup);
  }

  /// Sets the wallet type for the current user.
  ///
  /// This method stores the wallet type in user metadata, which can be used
  /// to determine wallet-specific behavior and features.
  ///
  /// If no user is currently signed in, the operation will complete but have no effect.
  ///
  /// [type] - The wallet type to set for the current user.
  Future<void> setWalletType(WalletType type) async {
    await auth.setOrRemoveActiveUserKeyValue('type', type.name);
  }

  /// Sets the wallet provenance for the current user.
  ///
  /// Stored values are used by wallet selection UIs to show quick metadata
  /// tags (generated/imported).
  Future<void> setWalletProvenance(WalletProvenance provenance) async {
    await auth.setOrRemoveActiveUserKeyValue(
      'wallet_provenance',
      provenance.name,
    );
  }

  /// Sets the wallet creation timestamp for the current user.
  ///
  /// Stored as milliseconds since epoch.
  Future<void> setWalletCreatedAt(DateTime createdAt) async {
    await auth.setOrRemoveActiveUserKeyValue(
      'wallet_created_at',
      createdAt.millisecondsSinceEpoch,
    );
  }
}
