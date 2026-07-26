import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';

/// Returns the cached GasFree custody address only for the canonical software
/// wallet key. Missing, ambiguous, hardware-wallet, and secondary-key caches
/// fail closed.
String? cachedCanonicalTronGaslessCustodyAddress(
  KomodoDefiSdk sdk,
  Asset asset, {
  required WalletType? walletType,
  required WalletId? currentWalletId,
}) {
  final isSoftwareWallet =
      walletType == WalletType.iguana || walletType == WalletType.hdwallet;
  if (!isSoftwareWallet || currentWalletId == null) return null;
  final expectedDerivation = walletType == WalletType.hdwallet
      ? DerivationMethod.hdWallet
      : DerivationMethod.iguana;
  if (currentWalletId.authOptions.derivationMethod != expectedDerivation) {
    return null;
  }

  try {
    final cached = sdk.pubkeys.lastKnownForWallet(asset.id, currentWalletId);
    if (cached == null) return null;

    PubkeyInfo? canonical;
    for (final key in cached.keys) {
      if (!isCanonicalTronGaslessPubkey(
        key,
        isHdWallet: walletType == WalletType.hdwallet,
      )) {
        continue;
      }
      // More than one canonical candidate is an invalid cache, not a reason
      // to trust whichever entry happened to be first.
      if (canonical != null) return null;
      canonical = key;
    }

    final custodyAddress = canonical?.gasfreeAddress;
    return custodyAddress == null || custodyAddress.isEmpty
        ? null
        : custodyAddress;
  } catch (_) {
    return null;
  }
}

/// Final consolidation gate for Standard -> GasFree transfers.
///
/// Consolidation is a new custody deposit, so it must satisfy the same fresh,
/// typed account-status contract as the QR/copy surface. The cached canonical
/// address is also compared byte-for-byte before the shared verifier runs.
String? verifiedTronGaslessConsolidationAddress(
  KomodoDefiSdk sdk,
  Asset asset,
  CoinAddressesState state, {
  required WalletType? walletType,
  required WalletId? currentWalletId,
  DateTime? now,
}) {
  final currentWalletHash = currentWalletId?.pubkeyHash?.trim();
  final verifiedWalletHash = state.gaslessReceiveWalletPubkeyHash?.trim();
  if (currentWalletHash == null ||
      currentWalletHash.isEmpty ||
      verifiedWalletHash == null ||
      verifiedWalletHash.isEmpty ||
      currentWalletHash != verifiedWalletHash) {
    return null;
  }
  final cachedAddress = cachedCanonicalTronGaslessCustodyAddress(
    sdk,
    asset,
    walletType: walletType,
    currentWalletId: currentWalletId,
  );
  final verifiedAddress = state.verifiedGasfreeAddress;
  if (cachedAddress == null || cachedAddress != verifiedAddress) return null;

  return isVerifiedTronGaslessReceive(
        sdk,
        asset,
        capabilityReady:
            state.gaslessReceiveStatus == GaslessReceiveStatus.ready,
        accountStatus: state.gaslessAccountStatus,
        accountStatusObservedAt: state.gaslessAccountStatusObservedAt,
        verifiedAddress: verifiedAddress,
        custodyAddress: cachedAddress,
        expiresAt: state.gaslessReceiveConfigExpiresAt,
        expectedServiceProvider: tronGaslessServiceProvider,
        now: now,
      )
      ? cachedAddress
      : null;
}
