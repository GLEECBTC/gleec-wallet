import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';

/// True only for the software-wallet key GasFree v1 binds to.
///
/// Non-HD wallets expose no derivation path. HD wallets must use the external
/// account-zero/address-zero key. Secondary and change keys remain standard
/// TRON addresses even if stale cached metadata carries a GasFree address.
bool isCanonicalTronGaslessPubkey(
  PubkeyInfo pubkey, {
  required bool isHdWallet,
}) {
  final derivationPath = pubkey.derivationPath?.trim();
  final chain = pubkey.chain?.trim().toLowerCase();

  if (!isHdWallet) {
    // Iguana wallets have one software key and no HD metadata. Reject stale
    // derivation metadata rather than treating it as another custody account.
    return (derivationPath == null || derivationPath.isEmpty) &&
        (chain == null || chain.isEmpty || chain == 'external');
  }

  // GasFree v1 is bound to TRON BIP44 account 0, external chain, address 0.
  // A suffix check is not sufficient: account 1 and other coin types can end
  // in `/0/0` as well. Missing metadata fails closed for HD wallets.
  return chain == 'external' && derivationPath == "m/44'/195'/0'/0/0";
}

extension LegacyCoinMigrationExtensions on Coin {
  /// Gets the current USD price of this coin
  ///
  /// Uses the SDK's price manager for up-to-date data
  Future<double?> getUsdPrice(KomodoDefiSdk sdk) async {
    final priceDecimal = await sdk.marketData.maybeFiatPrice(id);
    if (priceDecimal == null) return null;
    return priceDecimal.toDouble();
  }

  /// Calculates the USD value of a given amount of this coin
  ///
  /// Uses the SDK's price manager for up-to-date data
  Future<double> calculateUsdAmount(KomodoDefiSdk sdk, double amount) async {
    final priceDecimal = await sdk.marketData.maybeFiatPrice(id);
    if (priceDecimal == null) return 0;
    return (priceDecimal * Decimal.parse(amount.toString())).toDouble();
  }

  /// Last known spendable balance of this coin
  ///
  /// NB: This is not a real-time balance. Prefer using [getBalance] or
  /// [watchBalance] for up-to-date data.
  double? balance(KomodoDefiSdk sdk) =>
      sdk.balances.lastKnown(id)?.spendable.toDouble();

  /// Gets the current USD balance of this coin
  ///
  /// Uses the SDK's balance and price managers for up-to-date data
  Future<double?> getUsdBalance(KomodoDefiSdk sdk) async {
    final balance = await sdk.balances.getBalance(id);
    if (balance.spendable == Decimal.zero) return 0;

    final price = await sdk.marketData.maybeFiatPrice(id);
    if (price == null) return null;

    return (price * Decimal.parse(balance.spendable.toString())).toDouble();
  }

  double? lastKnownUsdBalance(KomodoDefiSdk sdk) {
    final balance = sdk.balances.lastKnown(id);
    if (balance == null) return null;
    if (balance.spendable == Decimal.zero) return 0;

    final price = sdk.marketData.priceIfKnown(id);
    if (price == null) return null;

    return (price * balance.spendable).toDouble();
  }

  double? lastKnownUsdPrice(KomodoDefiSdk sdk) {
    final price = sdk.marketData.priceIfKnown(id);
    if (price == null) return null;
    return price.toDouble();
  }

  /// Get cached 24hr change from CoinsBloc state
  /// This bridges the gap until SDK provides cached 24hr data
  double? lastKnown24hChange(BuildContext context) {
    return context.read<CoinsBloc>().state.get24hChangeForAsset(id);
  }

  /// Whether this asset is a TRON TRC-20 token eligible for gas-free (GasFree)
  /// transfers.
  ///
  /// For these assets the spendable balance lives at the deterministic CREATE2
  /// **GasFree custody address**, not the EOA — a gasless withdrawal settles
  /// from custody and ordinarily pays its fee in the token. Exceptional
  /// recovery may still require TRX in the Standard wallet.
  /// The coin's `my_balance` still reports the EOA balance, so custody-aware
  /// surfaces must use [gasfreeCustodyBalance] instead.
  bool isGaslessAsset(KomodoDefiSdk sdk) =>
      isTronGaslessConfigured && _matchesGaslessAssetPolicy;

  /// Whether the custody receive address may be exposed for this asset.
  /// Sending and recovery can remain available while new GasFree deposits are
  /// disabled independently.
  bool isGaslessReceiveAsset(KomodoDefiSdk sdk) =>
      isTronGaslessReceiveConfigured && _matchesGaslessAssetPolicy;

  /// Existing custody/pending/recovery visibility must survive send and
  /// receive kill switches. This derives network identity from the coin
  /// itself while retaining the exact token policy.
  bool get isGaslessRecoveryAsset => isTronGaslessAssetIdEligible(
    id,
    isCustomToken: isCustomCoin,
    isTestnet: isTestCoin,
    platform: protocolData?.platform,
    contractAddress: protocolData?.contractAddress,
    providerNetworkPath: isTestCoin ? 'nile' : 'tron',
  );

  /// Whether this coin falls under the TRON gasless single-address model.
  ///
  /// TRX and its TRC-20 tokens share one HD address list, and the custody
  /// model binds to the primary address only — so address creation must be
  /// gated on the TRX platform page too, or a TRX-created address would be
  /// invisible (the SDK's phantom-address filter hides unfunded secondary
  /// TRON addresses).
  bool isGaslessSingleAddressScope(KomodoDefiSdk sdk) =>
      isTronGaslessConfigured &&
      (_matchesGaslessAssetPolicy || _matchesGaslessParentPolicy);

  /// GasFree v1 supports only the pinned Tether contracts on their matching
  /// provider network. Custom tokens and network/contract lookalikes fail
  /// closed even when KDF happens to return a `gasfreeAddress` field.
  bool get _matchesGaslessAssetPolicy {
    return isTronGaslessAssetIdEligible(
      id,
      isCustomToken: isCustomCoin,
      isTestnet: isTestCoin,
      platform: protocolData?.platform,
      contractAddress: protocolData?.contractAddress,
    );
  }

  bool get _matchesGaslessParentPolicy {
    if (id.subClass != CoinSubClass.trx) return false;
    return switch (tronGaslessNetworkPath(tronGaslessBaseUrl)) {
      'tron' => !isTestCoin && id.id == 'TRX',
      'nile' => isTestCoin && id.id == 'TRXT',
      _ => false,
    };
  }

  /// The GasFree custody balance for a gas-free TRC-20 asset — the balance a
  /// gasless withdrawal actually settles from. Returns `null` for non-gasless
  /// assets or when the status could not be fetched.
  ///
  /// This is an on-demand fetch (`gasless::account_status`); callers that need a
  /// synchronous value should cache the result.
  Future<BalanceInfo?> gasfreeCustodyBalance(KomodoDefiSdk sdk) async {
    if (!isGaslessRecoveryAsset) return null;
    try {
      final status = await sdk.withdrawals.gaslessAccountStatus(id);
      return status.custodyBalance;
    } catch (_) {
      return null;
    }
  }
}
