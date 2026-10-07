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
    this.automatic = false,
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

  /// Whether the form is re-pricing on its own rather than for someone's
  /// action. A source waiting out a rate limit answers these without asking.
  final bool automatic;

  /// This request, for [orders] instead.
  SwapQuoteRequest withOrders(Set<SwapQuoteOrder> orders) => SwapQuoteRequest(
    from: from,
    to: to,
    amount: amount,
    orders: orders,
    slippage: slippage,
    indicative: indicative,
    signedOut: signedOut,
    automatic: automatic,
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
    automatic,
  ];
}

/// What a Max reserve pays for.
enum SwapMaxReserve {
  /// Network fees.
  networkFees,

  /// Network fees, and the provider fees a route charges on top of the
  /// amount.
  networkAndProviderFees,

  /// The provider fees a route charges on top of the amount alone, as a
  /// token's network fees are paid in its network's coin.
  providerFees,

  /// The order book's trading fee alone, as a token's network fees are paid
  /// in its network's coin.
  tradingFee,

  /// The order book's trading fee and the network fees.
  tradingAndNetworkFees,
}

/// The largest sellable amount a source allows, keeping what fees need.
class SwapMaxAmount extends Equatable {
  const SwapMaxAmount({
    required this.amount,
    required this.reservedForFees,
    this.feeAsset,
    this.reserveCovers = SwapMaxReserve.networkFees,
    this.offerLimit = false,
    this.coversRefund = false,
  });

  /// What may be sold.
  final Decimal amount;

  /// Held back for what [reserveCovers] names, in [feeAsset] units, with any
  /// remainder of rounding down to the asset's decimals.
  final Decimal reservedForFees;

  /// The coin the reserve is held in.
  final AssetId? feeAsset;

  /// What [reservedForFees] pays for.
  final SwapMaxReserve reserveCovers;

  /// Whether [amount] is the largest order-book offer, below what the wallet
  /// could sell.
  final bool offerLimit;

  /// Whether [amount] already leaves what refunding a failed swap takes from
  /// this balance, as KDF's own Max does.
  final bool coversRefund;

  /// Whether selling [sold] from [balance] still leaves what [coversRefund]
  /// kept back: no more than [amount], from no less than Max was asked with.
  bool coversRefundFor(Decimal sold, Decimal? balance) =>
      coversRefund &&
      sold <= amount &&
      balance != null &&
      balance >= amount + reservedForFees;

  @override
  List<Object?> get props => [
    amount,
    reservedForFees,
    feeAsset,
    reserveCovers,
    offerLimit,
    coversRefund,
  ];
}
