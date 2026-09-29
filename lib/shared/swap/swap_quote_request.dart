part of 'swap_quote.dart';

/// The request one pricing attempt answers.
class SwapQuoteRequest extends Equatable {
  const SwapQuoteRequest({
    required this.from,
    required this.to,
    required this.amount,
    this.orders = const {SwapQuoteOrder.cheapest},
    this.slippage,
    this.indicative = false,
    this.signedOut = false,
  });

  /// The asset being sold.
  final AssetId from;

  /// The asset being bought.
  final AssetId to;

  /// How much of [from] to sell.
  final Decimal amount;

  /// Which routes an aggregator prices. Each is a separate provider request,
  /// so alternatives are asked for only when someone will compare them.
  final Set<SwapQuoteOrder> orders;

  /// The price movement a route may allow, as a fraction; null for the
  /// provider's default.
  final double? slippage;

  /// Whether the answer is a price to look at and never one to start: [amount]
  /// is more than the wallet holds, or no wallet is signed in. Sources skip
  /// checks that need the funds.
  final bool indicative;

  /// Whether no wallet is signed in, so only wallet-free sources are asked.
  final bool signedOut;

  /// This request, for [orders] instead.
  SwapQuoteRequest withOrders(Set<SwapQuoteOrder> orders) => SwapQuoteRequest(
    from: from,
    to: to,
    amount: amount,
    orders: orders,
    slippage: slippage,
    indicative: indicative,
    signedOut: signedOut,
  );

  @override
  List<Object?> get props => [
    from,
    to,
    amount,
    orders,
    slippage,
    indicative,
    signedOut,
  ];
}

/// The largest sellable amount a source allows, keeping what fees need.
class SwapMaxAmount extends Equatable {
  const SwapMaxAmount({
    required this.amount,
    required this.reservedForFees,
    this.feeAsset,
    this.offerLimit = false,
  });

  /// What may be sold.
  final Decimal amount;

  /// Held back for network fees, in [feeAsset] units. Zero when fees are paid
  /// in another coin.
  final Decimal reservedForFees;

  /// The coin the reserve is held in.
  final AssetId? feeAsset;

  /// Whether [amount] is the largest order-book offer, below what the wallet
  /// could sell.
  final bool offerLimit;

  @override
  List<Object?> get props => [amount, reservedForFees, feeAsset, offerLimit];
}
