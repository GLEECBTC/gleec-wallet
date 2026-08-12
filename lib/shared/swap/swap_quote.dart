import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Where a swap's liquidity comes from.
///
/// The two sources are not interchangeable and the difference is visible to
/// users, so it is modelled explicitly rather than hidden behind one number.
enum SwapLiquiditySource {
  /// KDF's own atomic-swap orderbook. Peer-to-peer, no third party ever holds
  /// the funds, and the only route available for assets an aggregator does not
  /// list — including GLEEC and the GRC-20 tokens, which no aggregator
  /// supports because the Gleec chain is not one they index.
  atomic,

  /// An external aggregator, executed by KDF. Reaches far more assets and
  /// bridges across chains, but the funds transit third-party contracts.
  routed,
}

/// A cost line on a quote, normalised across sources.
class SwapQuoteCost {
  const SwapQuoteCost({
    required this.label,
    required this.amount,
    required this.tokenLabel,
    required this.isDeductedFromReceive,
  });

  /// What to call this cost in the UI.
  final String label;

  /// How much, in units of [tokenLabel].
  final Decimal amount;

  /// The token this is paid in. May differ from either side of the swap —
  /// network fees are usually paid in the chain's native coin.
  final String tokenLabel;

  /// Whether it is already subtracted from the receive amount.
  final bool isDeductedFromReceive;
}

/// A priced way to perform one swap.
///
/// Both sources produce this, so the form and the confirm sheet never branch
/// on where a price came from. What they *do* branch on is
/// [SwapQuote.source], because "peer-to-peer" and "routed through a third
/// party" is a distinction users are entitled to see.
class SwapQuote {
  const SwapQuote({
    required this.source,
    required this.from,
    required this.to,
    required this.sellAmount,
    required this.expectedReceive,
    required this.guaranteedReceive,
    required this.costs,
    required this.quotedAt,
    required this.hasUndisclosedCosts,
    this.providerLabel,
    this.estimatedDuration,
    this.isCrossChain = false,
    this.payload,
  });

  /// Which liquidity source produced this.
  final SwapLiquiditySource source;

  /// The asset being sold.
  final AssetId from;

  /// The asset being bought.
  final AssetId to;

  /// How much of [from] is spent.
  final Decimal sellAmount;

  /// The likely receive amount.
  final Decimal expectedReceive;

  /// The receive amount the user is guaranteed at minimum.
  ///
  /// This is the number to show. Leading with [expectedReceive] promises
  /// something neither source guarantees.
  final Decimal guaranteedReceive;

  /// Normalised costs.
  final List<SwapQuoteCost> costs;

  /// Whether some cost is known to exist but is not in [costs].
  ///
  /// True for a routed swap that may need an ERC-20 approval, whose gas the
  /// quote never reports. A UI showing a total must say the real figure can be
  /// higher rather than presenting a precise number it cannot stand behind.
  final bool hasUndisclosedCosts;

  /// Display name of the executing venue, when there is one.
  final String? providerLabel;

  /// How long this is expected to take.
  final Duration? estimatedDuration;

  /// Whether the swap moves between chains.
  final bool isCrossChain;

  /// Source-specific data needed to execute. Opaque to the UI.
  final Object? payload;

  /// When this was priced.
  final DateTime quotedAt;

  /// Whether this quote is old enough to need re-pricing.
  bool isStaleAt(
    DateTime now, {
    Duration maxAge = const Duration(seconds: 60),
  }) => now.difference(quotedAt) >= maxAge;

  /// The effective rate, as units of [to] per unit of [from].
  ///
  /// Computed from the guaranteed amount, so comparing two quotes compares
  /// what each actually promises rather than what each hopes for.
  Decimal? get guaranteedRate {
    if (sellAmount == Decimal.zero) return null;
    return (guaranteedReceive / sellAmount).toDecimal(
      scaleOnInfinitePrecision: 18,
    );
  }
}

/// Why no quote could be produced.
///
/// Separating "this pair is not supported here" from "supported, but no price
/// right now" matters: the first should steer the user elsewhere, the second
/// should offer a retry.
enum SwapQuoteUnavailableReason {
  /// This source cannot trade this pair at all.
  pairUnsupported,

  /// Supported, but nothing is available at this size right now.
  noLiquidity,

  /// The amount is outside the accepted bounds.
  amountOutOfBounds,

  /// A transient failure. Retrying may work.
  temporarilyUnavailable,
}

/// A source that failed to price a swap, and why.
class SwapQuoteUnavailable {
  const SwapQuoteUnavailable({
    required this.source,
    required this.reason,
    this.message,
  });

  /// Which source could not price it.
  final SwapLiquiditySource source;

  /// Why.
  final SwapQuoteUnavailableReason reason;

  /// A human-readable detail, when the source gave one.
  final String? message;
}

/// One place the app can get a swap price from.
abstract interface class SwapQuoteSource {
  /// Which source this is.
  SwapLiquiditySource get source;

  /// The assets this source can currently trade.
  ///
  /// Used to gate the pickers. Membership does not promise a route exists —
  /// only [quote] can answer that.
  Future<Set<AssetId>> tradableAssets();

  /// Prices a swap, or explains why it cannot.
  ///
  /// Must not throw for an ordinary "no price" outcome: a source that throws
  /// takes the whole aggregation down with it, and one venue being unable to
  /// fill an order is not an error.
  Future<SwapQuoteResult> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
  });
}

/// The outcome of asking one source for a price.
sealed class SwapQuoteResult {
  const SwapQuoteResult();
}

/// A source produced a price.
final class SwapQuoteAvailable extends SwapQuoteResult {
  const SwapQuoteAvailable(this.quote);

  /// The priced swap.
  final SwapQuote quote;
}

/// A source could not produce a price.
final class SwapQuoteRejected extends SwapQuoteResult {
  const SwapQuoteRejected(this.unavailable);

  /// Why not.
  final SwapQuoteUnavailable unavailable;
}
