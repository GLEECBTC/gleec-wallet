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
}) {
  var hasAnyUsdBalance = false;
  var total = 0.0;

  for (final coin in coins) {
    final balance = sdk.balances.lastKnown(coin.id)?.spendable.toDouble();
    final price = coinsState.getPriceForAsset(coin.id)?.price?.toDouble();
    if (balance == null || price == null) {
      continue;
    }
    hasAnyUsdBalance = true;
    total += balance * price;
  }

  if (!hasAnyUsdBalance) {
    return null;
  }

  if (total > 0.01) {
    return total;
  }

  return total != 0 ? 0.01 : 0;
}
