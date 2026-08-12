import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Prices swaps through the aggregator, executed by KDF.
///
/// Everything hard about the routed contract already lives in
/// [RoutedSwapManager]; this only normalises the result so the UI can compare
/// it against an atomic quote.
class RoutedSwapQuoteSource implements SwapQuoteSource {
  /// Creates a source backed by [manager].
  const RoutedSwapQuoteSource(this.manager);

  /// The SDK manager doing the real work.
  final RoutedSwapManager manager;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<Set<AssetId>> tradableAssets() async {
    try {
      return await manager.eligibleAssets();
    } on Object {
      // A provider outage must not empty the picker — the atomic source can
      // still trade, and a silently shorter list reads as "unsupported".
      return const {};
    }
  }

  @override
  Future<SwapQuoteResult> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
  }) async {
    try {
      final offer = await manager.quote(from: from, to: to, amount: amount);
      return SwapQuoteAvailable(_normalise(offer));
    } on Object catch (error) {
      return SwapQuoteRejected(
        SwapQuoteUnavailable(
          source: SwapLiquiditySource.routed,
          reason: _reasonFor(error),
          message: error.toString(),
        ),
      );
    }
  }

  SwapQuote _normalise(RoutedSwapOffer offer) => SwapQuote(
    source: SwapLiquiditySource.routed,
    from: offer.from,
    to: offer.to,
    sellAmount: offer.sellAmount,
    expectedReceive: offer.expectedReceive,
    guaranteedReceive: offer.guaranteedReceive,
    costs: [
      for (final cost in offer.costs)
        SwapQuoteCost(
          label: cost.label,
          amount: cost.amount,
          tokenLabel: cost.tokenLabel,
          isDeductedFromReceive: cost.isDeductedFromReceive,
        ),
    ],
    // The quote omits approval gas entirely, and the SDK works out from the
    // sell asset whether one may be charged.
    hasUndisclosedCosts: offer.mayRequireApproval,
    providerLabel: offer.toolName,
    estimatedDuration: offer.estimatedDuration,
    isCrossChain: offer.isCrossChain,
    quotedAt: offer.quotedAt,
    payload: offer,
  );

  /// Classifies a failure without matching on message text.
  ///
  /// The typed error names come from the contract; anything else is treated as
  /// transient, which is the reading that offers a retry rather than telling
  /// the user their pair is unsupported when the provider was merely down.
  SwapQuoteUnavailableReason _reasonFor(Object error) {
    final name = error.runtimeType.toString();
    if (name.contains('PairNotSupported') || name.contains('CoinNotActive')) {
      return SwapQuoteUnavailableReason.pairUnsupported;
    }
    if (name.contains('NoRouteFound')) {
      return SwapQuoteUnavailableReason.noLiquidity;
    }
    if (name.contains('AmountOutOfBounds')) {
      return SwapQuoteUnavailableReason.amountOutOfBounds;
    }
    return SwapQuoteUnavailableReason.temporarilyUnavailable;
  }
}
