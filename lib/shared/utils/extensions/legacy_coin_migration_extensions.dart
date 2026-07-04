import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';

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
  /// from custody and pays its fee in the token, so the user never needs TRX.
  /// The coin's `my_balance` still reports the EOA balance, so custody-aware
  /// surfaces must use [gasfreeCustodyBalance] instead.
  bool isGaslessAsset(KomodoDefiSdk sdk) =>
      id.subClass == CoinSubClass.trc20 && isTronGaslessConfigured;

  /// Whether this coin falls under the TRON gasless single-address model.
  ///
  /// TRX and its TRC-20 tokens share one HD address list, and the custody
  /// model binds to the primary address only — so address creation must be
  /// gated on the TRX platform page too, or a TRX-created address would be
  /// invisible (the SDK's phantom-address filter hides unfunded secondary
  /// TRON addresses).
  bool isGaslessSingleAddressScope(KomodoDefiSdk sdk) =>
      isTronGaslessConfigured &&
      (id.subClass == CoinSubClass.trc20 || id.subClass == CoinSubClass.trx);

  /// The GasFree custody balance for a gas-free TRC-20 asset — the balance a
  /// gasless withdrawal actually settles from. Returns `null` for non-gasless
  /// assets or when the status could not be fetched.
  ///
  /// This is an on-demand fetch (`gasless::account_status`); callers that need a
  /// synchronous value should cache the result.
  Future<BalanceInfo?> gasfreeCustodyBalance(KomodoDefiSdk sdk) async {
    if (!isGaslessAsset(sdk)) return null;
    try {
      final status = await sdk.withdrawals.gaslessAccountStatus(id);
      return status.custodyBalance;
    } catch (_) {
      return null;
    }
  }
}
