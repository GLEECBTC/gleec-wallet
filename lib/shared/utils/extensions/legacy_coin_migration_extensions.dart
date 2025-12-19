import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/coin.dart';

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
  double? balance(KomodoDefiSdk sdk) {
    try {
      return sdk.balances.lastKnown(id)?.spendable.toDouble();
    } on StateError {
      // SDK has been disposed, return null
      return null;
    }
  }

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
    try {
      final balance = sdk.balances.lastKnown(id);
      if (balance == null) return null;
      if (balance.spendable == Decimal.zero) return 0;

      final price = sdk.marketData.priceIfKnown(id);
      if (price == null) return null;

      return (price * balance.spendable).toDouble();
    } on StateError {
      // SDK has been disposed, return null
      return null;
    }
  }

  double? lastKnownUsdPrice(KomodoDefiSdk sdk) {
    try {
      final price = sdk.marketData.priceIfKnown(id);
      if (price == null) return null;
      return price.toDouble();
    } on StateError {
      // SDK has been disposed, return null
      return null;
    }
  }

  /// Get cached 24hr change from CoinsBloc state
  /// This bridges the gap until SDK provides cached 24hr data
  double? lastKnown24hChange(BuildContext context) {
    return context.read<CoinsBloc>().state.get24hChangeForAsset(id);
  }
}
