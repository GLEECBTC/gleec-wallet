import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/coin.dart';

/// Aggregates USD wallet value for display in wallet chrome (top bar, overview).
///
/// Uses [KomodoDefiSdk.balances.lastKnown] for spendable amounts and
/// [CoinsState.getPriceForAsset] for USD prices. Those prices come from the CEX
/// feed cached in [CoinsState.prices] (updated via [CoinsBloc] polling), not from
/// [KomodoDefiSdk.marketData.priceIfKnown]. Sorting, portfolio growth, and other
/// features may still use SDK pricing; sources can diverge by design until a
/// single SDK pricing path is adopted.
double? computeWalletTotalUsd({
  required Iterable<Coin> coins,
  required CoinsState coinsState,
  required KomodoDefiSdk sdk,
}) => computeWalletTotalUsdDetailed(
  coins: coins,
  coinsState: coinsState,
  sdk: sdk,
).totalUsd;

/// [computeWalletTotalUsd] plus how much of the wallet the total covers.
///
/// The coverage count exists for the `time_to_first_balance` metric: the total
/// turns non-null as soon as *one* asset has both a balance and a price, so the
/// timing is only interpretable next to how many assets that was out of how
/// many are held. One priced asset out of forty at 900ms and forty out of forty
/// at 900ms are very different outcomes and would otherwise be the same number.
({double? totalUsd, int pricedAssetCount, int assetCount})
computeWalletTotalUsdDetailed({
  required Iterable<Coin> coins,
  required CoinsState coinsState,
  required KomodoDefiSdk sdk,
}) {
  var pricedAssetCount = 0;
  var assetCount = 0;
  var total = 0.0;

  for (final coin in coins) {
    assetCount++;
    final balance = sdk.balances.lastKnown(coin.id)?.spendable.toDouble();
    final price = coinsState.getPriceForAsset(coin.id)?.price?.toDouble();
    if (balance == null || price == null) {
      continue;
    }
    pricedAssetCount++;
    total += balance * price;
  }

  if (pricedAssetCount == 0) {
    return (totalUsd: null, pricedAssetCount: 0, assetCount: assetCount);
  }

  final double resolved;
  if (total > 0.01) {
    resolved = total;
  } else {
    resolved = total != 0 ? 0.01 : 0;
  }
  return (
    totalUsd: resolved,
    pricedAssetCount: pricedAssetCount,
    assetCount: assetCount,
  );
}
