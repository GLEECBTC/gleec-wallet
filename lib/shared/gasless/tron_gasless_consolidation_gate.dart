import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';

/// Returns the cached GasFree custody address only for the canonical software
/// wallet key. Missing, ambiguous, hardware-wallet, and secondary-key caches
/// fail closed.
String? cachedCanonicalTronGaslessCustodyAddress(
  KomodoDefiSdk sdk,
  Asset asset, {
  required WalletType? walletType,
}) {
  final isSoftwareWallet =
      walletType == WalletType.iguana || walletType == WalletType.hdwallet;
  if (!isSoftwareWallet) return null;

  try {
    final cached = sdk.pubkeys.lastKnown(asset.id);
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
/// bound receive contract as the QR/copy surface. The cached canonical address
/// is also compared byte-for-byte before the shared receive verifier runs.
String? verifiedTronGaslessConsolidationAddress(
  KomodoDefiSdk sdk,
  Asset asset,
  CoinAddressesState state, {
  required WalletType? walletType,
  DateTime? now,
}) {
  final cachedAddress = cachedCanonicalTronGaslessCustodyAddress(
    sdk,
    asset,
    walletType: walletType,
  );
  final verifiedAddress = state.verifiedGasfreeAddress;
  if (cachedAddress == null || cachedAddress != verifiedAddress) return null;

  return isVerifiedBoundTronGaslessReceive(
        sdk,
        asset,
        capabilityReady:
            state.gaslessReceiveStatus == GaslessReceiveStatus.ready,
        verifiedAddress: verifiedAddress,
        custodyAddress: cachedAddress,
        expiresAt: state.gaslessReceiveConfigExpiresAt,
        now: now,
      )
      ? cachedAddress
      : null;
}
