import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';

/// Calculates the total 24-hour change percentage for a list of coins.
///
/// The method calculates the total 24-hour change percentage across all coins
/// based on their balances, USD prices, and 24-hour change percentages.
///
/// Parameters:
/// - [coins] (List<Coin>?): List of Coin objects representing different coins.
///
/// Return Value:
/// - (double?): The total 24-hour change percentage, or null if input is empty or null.
///
/// Example Usage:
/// ```dart
/// List<Coin> coins = [
///   Coin(1.0, usdPrice: Price(100.0, change24h: 0.05)),
///   Coin(2.0, usdPrice: Price(50.0, change24h: -0.03)),
///   Coin(3.0, usdPrice: Price(10.0, change24h: 0.02)),
/// ];
/// double? result = getTotal24Change(coins);
/// print(result); // Output: 0.014
/// ```
/// unit tests: [testGetTotal24Change]
/// TODO: consider removing or migrating to the SDK. This function is unreferenced
/// and the unit tests are skipped due to issues mocking the SDK classes/interfaces.
double? getTotal24Change(Iterable<Coin>? coins, KomodoDefiSdk sdk) {
  double getTotalUsdBalance(Iterable<Coin> coins) {
    return coins.fold(0, (prev, coin) {
      final balance = coin.lastKnownBalance(sdk)?.spendable.toDouble() ?? 0;
      if (balance == 0) return prev;

      // Last known USD price is failing for FTM, POL, so use fallback price
      // embedded in the coin object for now until backup/fallback price
      // providers are copied over to the SDK
      final coinPrice =
          coin.lastKnownUsdPrice(sdk) ?? coin.usdPrice?.price?.toDouble() ?? 0;
      return prev + balance * coinPrice;
    });
  }

  if (coins == null || coins.isEmpty) return null;

  final double totalUsdBalance = getTotalUsdBalance(coins);
  if (totalUsdBalance == 0) return null;

  Rational totalChange = Rational.zero;
  for (Coin coin in coins) {
    final double? coin24Change = coin.usdPrice?.change24h?.toDouble();
    if (coin24Change == null) continue;

    final balance = coin.lastKnownBalance(sdk)?.spendable.toDouble() ?? 0;

    final Rational coinFraction =
        Rational.parse(balance.toString()) *
        Rational.parse((coin.usdPrice?.price ?? 0).toString()) /
        Rational.parse(totalUsdBalance.toString());
    final coin24ChangeRat = Rational.parse(coin24Change.toString());
    totalChange = totalChange + coin24ChangeRat * coinFraction;
  }
  return totalChange.toDouble();
}
