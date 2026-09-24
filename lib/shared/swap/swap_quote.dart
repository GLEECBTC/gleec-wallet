import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Where a swap's liquidity comes from.
///
/// The two sources are not interchangeable: one is peer-to-peer, the other
/// executes through a third-party aggregator's contracts. The difference shows
/// in how a swap completes, not in a provider name — infrastructure identity is
/// diagnostic, never customer-facing copy.
enum SwapLiquiditySource {
  /// KDF's own atomic-swap orderbook. Peer-to-peer, and the only route for
  /// assets no aggregator lists — GLEEC and the GRC-20 tokens above all.
  atomic,

  /// An external aggregator, executed by KDF. Reaches far more assets and
  /// bridges across chains.
  routed,
}

/// How a swap completes, which is what a user can reason about.
enum SwapRouteKind {
  /// A peer-to-peer exchange with a counterparty from the orderbook.
  direct,

  /// A conversion on one network. One transaction.
  sameChain,

  /// A move between networks, with a bridge wait that can run to tens of
  /// minutes.
  crossChain,
}

/// Which route an aggregator was asked for.
enum SwapQuoteOrder {
  /// The best quoted cost. The default.
  cheapest,

  /// The shortest estimated time.
  fastest,
}

/// The kind of a [SwapFeeComponent].
enum SwapFeeKind {
  /// Chain gas for the swap itself.
  network,

  /// Chain gas for the exact-amount approval (and reset) before the swap.
  approvalNetwork,

  /// A fee charged by the route: aggregator or protocol fees.
  swap,

  /// The atomic-swap trading fee.
  dexFee,
}

/// One cost of a quote.
class SwapFeeComponent extends Equatable {
  const SwapFeeComponent({
    required this.kind,
    required this.amount,
    required this.deductedFromReceive,
    this.asset,
    this.symbol,
    this.usdValue,
  });

  /// What kind of cost.
  final SwapFeeKind kind;

  /// How much, in units of the fee's own token.
  final Decimal amount;

  /// Whether the receive amounts already account for this cost. Counting it
  /// again double-charges in the UI.
  final bool deductedFromReceive;

  /// The wallet asset the fee is paid in, when it maps to one.
  final AssetId? asset;

  /// The provider's symbol when it does not. Display-only; never a ticker.
  final String? symbol;

  /// USD value, when known.
  final Decimal? usdValue;

  /// A short token label for display.
  String get tokenLabel => asset?.symbol.configSymbol ?? symbol ?? '';

  /// A copy with [usdValue] set.
  SwapFeeComponent withUsd(Decimal? usd) => SwapFeeComponent(
    kind: kind,
    amount: amount,
    deductedFromReceive: deductedFromReceive,
    asset: asset,
    symbol: symbol,
    usdValue: usd,
  );

  @override
  List<Object?> get props => [
    kind,
    amount,
    deductedFromReceive,
    asset,
    symbol,
    usdValue,
  ];
}

/// The permission a token sell grants before swapping.
class SwapApprovalRequirement extends Equatable {
  const SwapApprovalRequirement({
    required this.asset,
    required this.exactAmount,
    required this.resetsFirst,
  });

  /// The token being approved.
  final AssetId asset;

  /// The exact amount approved — never unlimited.
  final Decimal exactAmount;

  /// Whether the current permission is reset to zero first, which takes a
  /// second transaction.
  final bool resetsFirst;

  @override
  List<Object?> get props => [asset, exactAmount, resetsFirst];
}

/// The kind of a [SwapRouteStage].
enum SwapRouteStageKind {
  /// Checking the latest details before anything is signed.
  prepare,

  /// Resetting the token permission to zero.
  resetApproval,

  /// Approving the exact amount.
  approve,

  /// Sending the source transaction.
  send,

  /// Moving between networks.
  bridge,

  /// Converting on one network.
  convert,

  /// Exchanging with a peer-to-peer counterparty.
  exchange,

  /// Arriving at the destination.
  receive,
}

/// One step of how a swap completes.
///
/// Structured, not copy: the view layer turns it into words, so the same
/// stage renders in any language.
class SwapRouteStage extends Equatable {
  const SwapRouteStage({required this.kind, this.network, this.asset});

  /// What happens.
  final SwapRouteStageKind kind;

  /// The network it happens on, or arrives at for a bridge.
  final String? network;

  /// The asset involved, when one is.
  final AssetId? asset;

  @override
  List<Object?> get props => [kind, network, asset];
}

/// What a quote costs and returns in US dollars, where prices are known.
class SwapQuotePricing extends Equatable {
  const SwapQuotePricing({
    this.payUsd,
    this.expectedUsd,
    this.minimumUsd,
    this.networkCostUsd,
    this.approvalNetworkCostUsd,
    this.swapCostUsd,
    this.isComplete = false,
  });

  /// Value of what is paid.
  final Decimal? payUsd;

  /// Value of the expected receive.
  final Decimal? expectedUsd;

  /// Value of the guaranteed minimum.
  final Decimal? minimumUsd;

  /// Network fees, including any approval gas.
  final Decimal? networkCostUsd;

  /// The approval share of [networkCostUsd].
  final Decimal? approvalNetworkCostUsd;

  /// Route and trading fees.
  final Decimal? swapCostUsd;

  /// Whether every cost was priced. An incomplete total is never presented
  /// as a total.
  final bool isComplete;

  /// Network plus swap costs, when both are known.
  Decimal? get totalCostUsd => networkCostUsd == null || swapCostUsd == null
      ? null
      : networkCostUsd! + swapCostUsd!;

  /// The fraction of value lost against the market estimate, from the
  /// expected receive: 0.05 is 5%. Null without prices.
  Decimal? get priceImpact {
    final pay = payUsd;
    final expected = expectedUsd;
    if (pay == null || expected == null || pay <= Decimal.zero) return null;
    return ((pay - expected) / pay).toDecimal(scaleOnInfinitePrecision: 8);
  }

  @override
  List<Object?> get props => [
    payUsd,
    expectedUsd,
    minimumUsd,
    networkCostUsd,
    approvalNetworkCostUsd,
    swapCostUsd,
    isComplete,
  ];
}

/// A priced way to perform one swap — the prototype's route candidate.
///
/// Both sources produce this, so the form and the review never branch on where
/// a price came from; they branch on [routeKind], which is what a user can
/// reason about.
class SwapQuote extends Equatable {
  const SwapQuote({
    required this.id,
    required this.source,
    required this.routeKind,
    required this.from,
    required this.to,
    required this.sellAmount,
    required this.expectedReceive,
    required this.guaranteedReceive,
    required this.fees,
    required this.stages,
    required this.quotedAt,
    this.order,
    this.approval,
    this.fromAddress,
    this.toAddress,
    this.estimatedDuration,
    this.slippage,
    this.pricing = const SwapQuotePricing(),
    this.diagnostic,
    this.payload,
  });

  /// Stable within one evaluation: identifies the option the user picked.
  final String id;

  /// Which liquidity source produced this.
  final SwapLiquiditySource source;

  /// How the swap completes.
  final SwapRouteKind routeKind;

  /// Which aggregator route was asked for; null for peer-to-peer.
  final SwapQuoteOrder? order;

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
  /// The number to show before confirmation. Leading with [expectedReceive]
  /// promises something neither source guarantees.
  final Decimal guaranteedReceive;

  /// Every cost, normalised.
  final List<SwapFeeComponent> fees;

  /// How it completes, step by step.
  final List<SwapRouteStage> stages;

  /// The token permission required first, if any.
  final SwapApprovalRequirement? approval;

  /// Where the funds are sent from.
  final String? fromAddress;

  /// Where the output lands.
  final String? toAddress;

  /// How long this is expected to take.
  final Duration? estimatedDuration;

  /// The slippage tolerance the minimum reflects, for routed quotes.
  final double? slippage;

  /// When this was priced.
  final DateTime quotedAt;

  /// US-dollar figures, where prices are known.
  final SwapQuotePricing pricing;

  /// Infrastructure identity (provider, tool) for support diagnostics. Never
  /// shown as primary copy.
  final String? diagnostic;

  /// Source-specific data needed to execute. Opaque to the UI.
  final Object? payload;

  /// How long a quote may be relied on before it is refreshed.
  static const lifetime = Duration(seconds: 60);

  /// When this quote should no longer be started without re-pricing.
  DateTime get expiresAt => quotedAt.add(lifetime);

  /// Whether this quote is old enough to need re-pricing.
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// Whether a token permission is needed first.
  bool get requiresApproval => approval != null;

  /// Whether net return can be compared with other options.
  ///
  /// Only when the minimum and every cost are priced; otherwise a comparison
  /// would rank an option on the costs it happens to disclose.
  bool get isRankable =>
      pricing.isComplete && pricing.minimumUsd != null && netReturnUsd != null;

  /// What the user is guaranteed to end up with, net of the costs the receive
  /// amount does not already account for.
  Decimal? get netReturnUsd {
    final minimum = pricing.minimumUsd;
    if (minimum == null || !pricing.isComplete) return null;
    var extra = Decimal.zero;
    for (final fee in fees) {
      if (fee.deductedFromReceive) continue;
      final usd = fee.usdValue;
      if (usd == null) return null;
      extra += usd;
    }
    return minimum - extra;
  }

  /// Units of [to] per unit of [from] at the expected receive.
  Decimal? get expectedRate => _rate(expectedReceive);

  /// Units of [to] per unit of [from] at the guaranteed minimum.
  Decimal? get guaranteedRate => _rate(guaranteedReceive);

  Decimal? _rate(Decimal receive) {
    if (sellAmount <= Decimal.zero) return null;
    return (receive / sellAmount).toDecimal(scaleOnInfinitePrecision: 18);
  }

  /// The costs of one [kind].
  Iterable<SwapFeeComponent> feesOf(SwapFeeKind kind) =>
      fees.where((fee) => fee.kind == kind);

  /// A copy with [pricing] and fee USD values replaced.
  SwapQuote withPricing(
    SwapQuotePricing pricing, {
    List<SwapFeeComponent>? fees,
  }) => SwapQuote(
    id: id,
    source: source,
    routeKind: routeKind,
    order: order,
    from: from,
    to: to,
    sellAmount: sellAmount,
    expectedReceive: expectedReceive,
    guaranteedReceive: guaranteedReceive,
    fees: fees ?? this.fees,
    stages: stages,
    approval: approval,
    fromAddress: fromAddress,
    toAddress: toAddress,
    estimatedDuration: estimatedDuration,
    slippage: slippage,
    quotedAt: quotedAt,
    pricing: pricing,
    diagnostic: diagnostic,
    payload: payload,
  );

  @override
  List<Object?> get props => [
    id,
    source,
    routeKind,
    order,
    from,
    to,
    sellAmount,
    expectedReceive,
    guaranteedReceive,
    fees,
    stages,
    approval,
    fromAddress,
    toAddress,
    estimatedDuration,
    slippage,
    quotedAt,
    pricing,
    diagnostic,
  ];
}

/// The request one pricing attempt answers.
class SwapQuoteRequest extends Equatable {
  const SwapQuoteRequest({
    required this.from,
    required this.to,
    required this.amount,
    this.includeAlternatives = true,
  });

  /// The asset being sold.
  final AssetId from;

  /// The asset being bought.
  final AssetId to;

  /// How much of [from] to sell.
  final Decimal amount;

  /// Whether to also price alternative routes (e.g. the fastest one) for
  /// comparison, or only the default.
  final bool includeAlternatives;

  @override
  List<Object?> get props => [from, to, amount, includeAlternatives];
}

/// The largest sellable amount a source allows, keeping what fees need.
class SwapMaxAmount extends Equatable {
  const SwapMaxAmount({
    required this.amount,
    required this.reservedForFees,
    this.feeAsset,
  });

  /// What may be sold.
  final Decimal amount;

  /// Held back for network fees, in [feeAsset] units. Zero when fees are paid
  /// in another coin.
  final Decimal reservedForFees;

  /// The coin the reserve is held in.
  final AssetId? feeAsset;

  @override
  List<Object?> get props => [amount, reservedForFees, feeAsset];
}
