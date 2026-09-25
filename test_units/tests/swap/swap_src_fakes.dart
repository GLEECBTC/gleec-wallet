import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';

import 'swap_test_fixtures.dart';

/// One order-book bid; a null field is missing from KDF's answer.
OrderInfo bidOf(String? price, String? min, String? max) => OrderInfo(
  price: price == null ? null : NumericValue(decimal: price),
  baseMinVolume: min == null ? null : NumericValue(decimal: min),
  baseMaxVolume: max == null ? null : NumericValue(decimal: max),
);

/// One fee line of a trade preimage.
PreimageCoinFee coinFeeOf(
  String coin,
  String amount, {
  bool fromVolume = false,
}) => PreimageCoinFee(
  coin: coin,
  amount: amount,
  amountFraction: Fraction(numer: '0', denom: '1'),
  amountRat: Rational.zero,
  paidFromTradingVol: fromVolume,
);

/// A trade preimage with the given fee lines.
TradePreimageResponse preimageOf({
  PreimageCoinFee? takerFee,
  PreimageCoinFee? feeToSendTakerFee,
  PreimageCoinFee? baseCoinFee,
  PreimageCoinFee? relCoinFee,
}) => TradePreimageResponse(
  mmrpc: '2.0',
  totalFees: const [],
  takerFee: takerFee,
  feeToSendTakerFee: feeToSendTakerFee,
  baseCoinFee: baseCoinFee,
  relCoinFee: relCoinFee,
);

/// KDF's trading RPCs, answered from a script.
class SrcTrading implements TradingManager {
  String minimum = '0.001';
  Object? minimumError;
  String maxTaker = '1';
  Object? maxTakerError;
  List<OrderInfo> bids = [bidOf('20', '0.01', '5')];
  Object? bookError;
  TradePreimageResponse preimage = preimageOf();
  Object? preimageError;

  final List<({String coin, String? tradeWith})> maxCalls = [];
  final List<({String base, String rel})> books = [];
  final List<({String volume, String price, SwapMethod method})> preimages = [];

  @override
  Future<MinTradingVolumeResponse> minTradingVolume({
    required String coin,
  }) async {
    final error = minimumError;
    if (error != null) throw error;
    return MinTradingVolumeResponse(mmrpc: '2.0', amount: minimum);
  }

  @override
  Future<MaxTakerVolumeResponse> maxTakerVolume({
    required String coin,
    String? tradeWith,
  }) async {
    maxCalls.add((coin: coin, tradeWith: tradeWith));
    final error = maxTakerError;
    if (error != null) throw error;
    return MaxTakerVolumeResponse(mmrpc: '2.0', amount: maxTaker);
  }

  @override
  Future<OrderbookResponse> getOrderbook({
    required String base,
    required String rel,
  }) async {
    books.add((base: base, rel: rel));
    final error = bookError;
    if (error != null) throw error;
    return OrderbookResponse(
      mmrpc: '2.0',
      base: base,
      rel: rel,
      bids: bids,
      asks: const [],
      numBids: bids.length,
      numAsks: 0,
      timestamp: 0,
    );
  }

  @override
  Future<TradePreimageResponse> tradePreimage({
    required String base,
    required String rel,
    required SwapMethod swapMethod,
    String? volume,
    bool? max,
    String? price,
  }) async {
    preimages.add((volume: volume!, price: price!, method: swapMethod));
    final error = preimageError;
    if (error != null) throw error;
    return preimage;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A routed offer with sensible defaults: 1 ETH for USDC, same chain.
RoutedSwapOffer offerOf({
  AssetId? from,
  AssetId? to,
  String sell = '1',
  String expected = '3000',
  String guaranteed = '2985',
  RoutedSwapRouteKind kind = RoutedSwapRouteKind.sameChain,
  List<RoutedSwapCost> costs = const [],
  List<RoutedSwapNetworkFee> networkFees = const [],
  List<RoutedSwapLeg> legs = const [],
  RoutedSwapApprovalInfo? approval,
  RoutedSwapOrder? order,
  DateTime? quotedAt,
  String toolKey = 'tool',
  double? slippage,
  Duration? duration,
}) {
  final sold = from ?? eth;
  final bought = to ?? usdc;
  return RoutedSwapOffer(
    from: sold,
    to: bought,
    sellAmount: d(sell),
    expectedReceive: d(expected),
    guaranteedReceive: d(guaranteed),
    kind: kind,
    costs: costs,
    networkFees: networkFees,
    legs: legs,
    quotedAt: quotedAt ?? DateTime(2026, 9, 24, 12),
    provider: 'lifi',
    toolKey: toolKey,
    toolName: 'Tool',
    route: RoutedSwapRoute.fromJson({
      'from': {'coin': sold.id, 'amount': sell},
      'to': {'coin': bought.id, 'amount': expected, 'amount_min': guaranteed},
      'tool': {'key': toolKey, 'name': 'Tool'},
      'kind': kind.wire,
    }),
    order: order,
    fromAddress: '0xfrom',
    toAddress: '0xto',
    approval: approval,
    estimatedDuration: duration,
    slippage: slippage,
  );
}

/// The arguments of one routed quote request.
typedef SrcQuoteCall = ({
  AssetId from,
  AssetId to,
  Decimal amount,
  double? slippage,
  RoutedSwapOrder? order,
});

/// The SDK's routed-swap manager, answered from a script.
class SrcRoutedSwaps implements RoutedSwapManager {
  final List<SrcQuoteCall> quotes = [];

  /// Answers each quote; by default an [offerOf] for the asked amount.
  RoutedSwapOffer Function(SrcQuoteCall call)? respond;
  Object? quoteError;

  /// Leaves every quote unanswered, for timeouts.
  bool hangQuotes = false;

  Set<AssetId> eligible = {};
  Object? eligibleError;
  bool hangEligible = false;

  RoutedSwapMaxSell? max;
  Object? maxError;
  bool hangMax = false;
  int maxCalls = 0;

  List<String> inFlightIds = [];
  Object? inFlightError;
  int inFlightCalls = 0;

  /// Swaps [watch] finds; any other id is unknown.
  Set<String> watchable = {};
  final List<String> watched = [];

  @override
  Future<RoutedSwapOffer> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
    double? slippage,
    RoutedSwapOrder? order,
    String? provider,
  }) async {
    final call = (
      from: from,
      to: to,
      amount: amount,
      slippage: slippage,
      order: order,
    );
    quotes.add(call);
    if (hangQuotes) await Completer<void>().future;
    final error = quoteError;
    if (error != null) throw error;
    return respond?.call(call) ??
        offerOf(
          from: from,
          to: to,
          sell: '$amount',
          order: order,
          slippage: slippage,
        );
  }

  @override
  Future<Set<AssetId>> eligibleAssets({String? provider}) async {
    if (hangEligible) await Completer<void>().future;
    final error = eligibleError;
    if (error != null) throw error;
    return eligible;
  }

  @override
  Future<RoutedSwapMaxSell> maxSellAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
    double? slippage,
    RoutedSwapOrder? order,
    String? provider,
  }) async {
    maxCalls++;
    if (hangMax) await Completer<void>().future;
    final error = maxError;
    if (error != null) throw error;
    return max ??
        RoutedSwapMaxSell(
          amount: balance,
          reservedForFees: Decimal.zero,
          feeAsset: from.parentId,
        );
  }

  @override
  Future<List<RoutedSwapProgress>> inFlight({int pageSize = 50}) async {
    inFlightCalls++;
    final error = inFlightError;
    if (error != null) throw error;
    return [for (final id in inFlightIds) runningSwap(id)];
  }

  @override
  Future<RoutedSwapHandle> watch(String uuid) async {
    watched.add(uuid);
    if (!watchable.contains(uuid)) throw RoutedSwapNotFoundException(uuid);
    return SrcRoutedHandle(runningSwap(uuid));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A routed swap still bridging.
RoutedSwapProgress runningSwap(String uuid) => RoutedSwapProgress(
  uuid: uuid,
  phase: RoutedSwapPhase.bridging,
  canCancel: false,
);

/// A handle on a routed swap that reports nothing further.
class SrcRoutedHandle implements RoutedSwapHandle {
  SrcRoutedHandle(this.latest);

  @override
  final RoutedSwapProgress latest;

  @override
  String get uuid => latest.uuid;

  @override
  Stream<RoutedSwapProgress> get progress => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
