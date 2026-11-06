import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

/// Release policy for KDF Max quotes that leave no allowance for changing gas.
///
/// KDF remains the authority on spendable funds. Its Max principal plus gas
/// establishes a conservative budget, already excluding recognized swap locks.
/// Only complete, newly priced offers can be returned at a reduced principal.
/// Remove this policy after KDF covers quote-to-execution funding changes; see
/// docs/NATIVE_MAX_GAS_RESERVE.md for the validation and removal criteria.
class RoutedSwapMaxPolicy {
  const RoutedSwapMaxPolicy();

  /// Release default; operators can roll back without altering RPC semantics.
  static const enabledByDefault = bool.fromEnvironment(
    'SWAP_NATIVE_MAX_GAS_RESERVE',
    defaultValue: true,
  );

  /// One initial exact quote and at most two reductions if its fees increase.
  static const _maxExactQuotes = 3;

  /// Quotes native Max with twice the current required gas balance retained.
  /// Tokens keep their full KDF Max; their gas is paid in another asset.
  Future<({RoutedSwapOffer offer, Decimal? retainedBalance})> quote({
    required RoutedSwapManager manager,
    required AssetId from,
    required AssetId to,
    required Duration timeout,
    double? slippage,
    RoutedSwapOrder? order,
    bool enabled = enabledByDefault,
  }) async {
    final elapsed = Stopwatch()..start();
    Future<RoutedSwapOffer> request(
      Future<RoutedSwapOffer> Function() fetch,
    ) async {
      final left = timeout - elapsed.elapsed;
      if (left <= Duration.zero) throw TimeoutException('Max quote timed out');
      // Time out the awaited request itself: a late response must not initiate
      // another provider call after the caller has already stopped waiting.
      return fetch().timeout(left);
    }

    final maximum = await request(
      () => manager.quoteMax(
        from: from,
        to: to,
        slippage: slippage,
        order: order,
      ),
    );
    if (!enabled || from.isChildAsset) {
      return (offer: maximum, retainedBalance: null);
    }
    _validatePair(maximum, from, to);
    final gas = _requiredGas(maximum);
    final budget = maximum.sellAmount + gas;
    // KDF's ETH family uses 18 native decimals when config omits the value.
    final decimals = from.chainId.decimals ?? 18;
    if (decimals < 0 || decimals > 18) {
      throw _unavailable('Unsupported native amount precision');
    }
    var current = maximum;
    for (var attempt = 0; attempt < _maxExactQuotes; attempt++) {
      final reserve = _requiredGas(current) * Decimal.fromInt(2);
      final amount = (budget - reserve - _providerFees(current)).floor(
        scale: decimals,
      );
      if (amount <= Decimal.zero) {
        throw _unavailable(
          'The native Max gas reserve leaves no sellable amount',
        );
      }
      // Never increase principal in search of a larger Max or reuse a minimum
      // belonging to another amount. Every candidate is priced by KDF.
      final candidate = amount < current.sellAmount
          ? amount
          : current.sellAmount;
      final fresh = await request(
        () => manager.quote(
          from: from,
          to: to,
          amount: candidate,
          slippage: slippage,
          order: order,
          provider: maximum.provider,
        ),
      );
      _validatePair(fresh, from, to);
      if (fresh.provider != maximum.provider ||
          fresh.fromAddress != maximum.fromAddress ||
          fresh.toAddress != maximum.toAddress) {
        throw _unavailable('The quote funding account or recipient changed');
      }
      if (fresh.sellAmount != candidate) {
        throw _unavailable('The exact quote changed the requested principal');
      }
      final required =
          fresh.sellAmount +
          _providerFees(fresh) +
          _requiredGas(fresh) * Decimal.fromInt(2);
      if (required <= budget) {
        return (offer: fresh, retainedBalance: budget - fresh.sellAmount);
      }
      current = fresh;
    }
    throw _unavailable(
      'Native Max fees did not stabilize within the quote budget',
    );
  }

  static void _validatePair(RoutedSwapOffer offer, AssetId from, AssetId to) {
    if (offer.from != from ||
        offer.to != to ||
        offer.sellAmount <= Decimal.zero) {
      throw _unavailable('The Max quote has an invalid pair or principal');
    }
  }

  static Decimal _requiredGas(RoutedSwapOffer offer) {
    var total = Decimal.zero;
    var found = false;
    for (final fee in offer.networkFees) {
      if (fee.assetId != offer.from && fee.ticker != offer.from.id) continue;
      final required = fee.requiredBalance;
      if (required == null ||
          required < fee.amount ||
          fee.amount < Decimal.zero) {
        throw _unavailable('The native quote lacks a reliable gas requirement');
      }
      total += required;
      found = true;
    }
    if (!found || total <= Decimal.zero) {
      throw _unavailable('The native quote lacks a positive gas requirement');
    }
    return total;
  }

  static Decimal _providerFees(RoutedSwapOffer offer) {
    var total = Decimal.zero;
    for (final fee in offer.costs) {
      if (fee.kind != RoutedSwapCostKind.providerFee ||
          fee.isDeductedFromReceive ||
          fee.assetId != offer.from) {
        continue;
      }
      if (fee.amount < Decimal.zero) {
        throw _unavailable('The quote reports a negative provider fee');
      }
      total += fee.amount;
    }
    return total;
  }

  static SwapMaxUnavailableException _unavailable(String detail) =>
      SwapMaxUnavailableException(
        SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.serviceError,
          detail: detail,
        ),
      );
}
