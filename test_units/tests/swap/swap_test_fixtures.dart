import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

Decimal d(String value) => Decimal.parse(value);

/// A test asset. Pass [parent] for a token.
AssetId assetOf(
  String id, {
  CoinSubClass subClass = CoinSubClass.erc20,
  AssetId? parent,
  int chainId = 1,
  int? decimals = 18,
}) => AssetId(
  id: id,
  name: id,
  symbol: AssetSymbol(assetConfigId: id),
  chainId: AssetChainId(chainId: chainId, decimalsValue: decimals),
  derivationPath: null,
  subClass: subClass,
  parentId: parent,
);

final eth = assetOf('ETH');
final usdc = assetOf('USDC-ERC20', parent: eth);
final btc = assetOf(
  'BTC',
  subClass: CoinSubClass.utxo,
  chainId: 0,
  decimals: 8,
);
final gleec = assetOf(
  'GLEEC',
  subClass: CoinSubClass.utxo,
  chainId: 0,
  decimals: 8,
);

/// A priced quote with sensible defaults.
SwapQuote quoteOf({
  String id = 'q1',
  SwapLiquiditySource source = SwapLiquiditySource.routed,
  SwapRouteKind routeKind = SwapRouteKind.sameChain,
  SwapQuoteOrder? order = SwapQuoteOrder.cheapest,
  AssetId? from,
  AssetId? to,
  String sell = '1',
  String expected = '3000',
  String guaranteed = '2985',
  List<SwapFeeComponent>? fees,
  List<SwapRouteStage>? stages,
  SwapApprovalRequirement? approval,
  Duration? duration = const Duration(seconds: 45),
  DateTime? quotedAt,
  SwapQuotePricing? pricing,
  Object? payload,
}) => SwapQuote(
  id: id,
  source: source,
  routeKind: routeKind,
  order: order,
  from: from ?? eth,
  to: to ?? usdc,
  sellAmount: d(sell),
  expectedReceive: d(expected),
  guaranteedReceive: d(guaranteed),
  fees:
      fees ??
      [
        SwapFeeComponent(
          kind: SwapFeeKind.network,
          amount: d('0.001'),
          deductedFromReceive: false,
          asset: eth,
          usdValue: d('3'),
        ),
      ],
  stages:
      stages ??
      [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
        SwapRouteStage(kind: SwapRouteStageKind.send, asset: from ?? eth),
        SwapRouteStage(kind: SwapRouteStageKind.receive, asset: to ?? usdc),
      ],
  approval: approval,
  estimatedDuration: duration,
  quotedAt: quotedAt ?? DateTime(2026, 9, 24, 12),
  pricing:
      pricing ??
      SwapQuotePricing(
        payUsd: d('3000'),
        expectedUsd: d('3000'),
        minimumUsd: d(guaranteed),
        networkCostUsd: d('3'),
        swapCostUsd: d('0'),
        isComplete: true,
      ),
  payload: payload,
);

/// A swap snapshot with sensible defaults.
SwapExecutionSnapshot snapshotOf({
  String id = 'swap-1',
  SwapLiquiditySource source = SwapLiquiditySource.routed,
  SwapRouteKind routeKind = SwapRouteKind.sameChain,
  SwapProgressStage? stage = SwapProgressStage.confirming,
  SwapExecutionOutcome? outcome,
  SwapFundsMovement fundsMovement = SwapFundsMovement.sent,
  bool canCancel = false,
  bool approvalRemains = false,
  SwapApprovalRequirement? approval,
  List<String> approvalTxHashes = const [],
  String? sourceTxHash,
  List<SwapRouteStage>? stages,
  DateTime? createdAt,
  DateTime? finishedAt,
  DateTime? delayedSince,
  String? minimum = '2985',
}) => SwapExecutionSnapshot(
  id: id,
  source: source,
  routeKind: routeKind,
  from: eth,
  fromTicker: 'ETH',
  to: usdc,
  toTicker: 'USDC-ERC20',
  sellAmount: d('1'),
  expectedReceive: d('3000'),
  minimumReceive: minimum == null ? null : d(minimum),
  fromAddress: '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91',
  toAddress: '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91',
  stage: outcome == null ? stage : null,
  outcome: outcome,
  fundsMovement: fundsMovement,
  canCancel: canCancel,
  approval: approval,
  approvalRemains: approvalRemains,
  stages:
      stages ??
      [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
        SwapRouteStage(kind: SwapRouteStageKind.send, asset: eth),
        SwapRouteStage(kind: SwapRouteStageKind.receive, asset: usdc),
      ],
  createdAt: createdAt,
  finishedAt: finishedAt,
  delayedSince: delayedSince,
  evidence: SwapEvidence(
    executionId: id,
    approvalTxHashes: approvalTxHashes,
    sourceTxHash: sourceTxHash,
  ),
);

SwapExecutionOutcome completed({String amount = '3001'}) =>
    SwapExecutionOutcome(
      kind: SwapOutcomeKind.completed,
      receivedAmount: d(amount),
      receivedAsset: usdc,
    );

SwapExecutionOutcome failed(
  SwapFailureReason reason, {
  SwapNextStep next = SwapNextStep.retry,
  SwapQuote? freshQuote,
}) => SwapExecutionOutcome(
  kind: SwapOutcomeKind.failed,
  failure: SwapExecutionFailure(
    reason: reason,
    nextStep: next,
    freshQuote: freshQuote,
  ),
);

/// Prices from a map; unknown assets are unpriced.
class FakePriceSource implements SwapPriceSource {
  FakePriceSource([Map<AssetId, Decimal>? prices]) : prices = prices ?? {};

  final Map<AssetId, Decimal> prices;
  int warmCalls = 0;

  @override
  Decimal? usdPrice(AssetId asset) => prices[asset];

  @override
  Future<void> warm(Iterable<AssetId> assets) async => warmCalls++;
}

/// A quote source that answers from a script.
class FakeQuoteSource implements SwapQuoteSource {
  FakeQuoteSource(
    this.source, {
    Set<AssetId>? tradable,
    this.results = const [],
    this.requoteResult,
    this.max,
    this.delay,
    this.respond,
  }) : tradable = tradable ?? {eth, usdc, btc, gleec};

  /// Answers per request, when set; otherwise [results].
  List<SwapQuoteResult> Function(SwapQuoteRequest request)? respond;

  @override
  final SwapLiquiditySource source;
  Set<AssetId> tradable;
  List<SwapQuoteResult> results;
  SwapQuoteResult? requoteResult;
  SwapMaxAmount? max;
  Duration? delay;
  Completer<void>? gate;
  Completer<void>? requoteGate;
  final List<SwapQuoteRequest> requests = [];
  final List<SwapQuote> requoted = [];

  /// Tradable assets the wallet holds but has not activated.
  Set<AssetId> inactive = {};

  /// How current the list reads, for outage tests.
  SwapCatalogStatus status = SwapCatalogStatus.fresh;

  int assetsCalls = 0;

  @override
  Future<SwapSourceAssets> assets({
    required Set<AssetId> known,
    required Set<AssetId> activated,
  }) async {
    assetsCalls++;
    return SwapSourceAssets(
      source: source,
      quotable: tradable.difference(inactive),
      onceActive: tradable.intersection(inactive),
      status: status,
    );
  }

  @override
  Future<List<SwapQuoteResult>> quote(SwapQuoteRequest request) async {
    requests.add(request);
    if (delay != null) await Future<void>.delayed(delay!);
    if (gate != null) await gate!.future;
    return respond?.call(request) ?? results;
  }

  @override
  Future<SwapQuoteResult> requote(SwapQuote quote) async {
    requoted.add(quote);
    if (requoteGate != null) await requoteGate!.future;
    return requoteResult ?? SwapQuoteAvailable(quote);
  }

  @override
  Future<SwapMaxAmount?> maxAmount({
    required AssetId from,
    required AssetId to,
    required Decimal balance,
  }) async => max;

  @override
  Future<Decimal?> minimumAmount({required AssetId from}) async => null;
}

/// A handle whose updates the test pushes.
class FakeHandle implements SwapExecutionHandle {
  FakeHandle(this._latest);

  SwapExecutionSnapshot _latest;
  final StreamController<SwapExecutionSnapshot> _controller =
      StreamController<SwapExecutionSnapshot>.broadcast();
  Object? cancelError;
  int cancelCalls = 0;
  bool closed = false;

  void push(SwapExecutionSnapshot snapshot) {
    _latest = snapshot;
    _controller.add(snapshot);
  }

  @override
  String get id => _latest.id;

  @override
  SwapExecutionSnapshot get latest => _latest;

  @override
  Stream<SwapExecutionSnapshot> get updates => Stream.multi((out) {
    out.add(_latest);
    final subscription = _controller.stream.listen(out.add);
    out.onCancel = subscription.cancel;
  });

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }
}

/// An executor that hands out [FakeHandle]s.
class FakeExecutor implements SwapExecutor {
  FakeExecutor(this.source);

  @override
  final SwapLiquiditySource source;
  final Map<String, FakeHandle> resumable = {};
  final List<SwapQuote> started = [];
  Object? startError;
  FakeHandle? lastStarted;
  var _next = 0;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    started.add(quote);
    final error = startError;
    if (error != null) throw error;
    final handle = FakeHandle(
      snapshotOf(
        id: '${source.name}-${++_next}',
        source: source,
        stage: SwapProgressStage.preparing,
        fundsMovement: SwapFundsMovement.none,
        canCancel: true,
      ),
    );
    lastStarted = handle;
    return handle;
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async => resumable[id];
}

/// Storage in memory.
class MemoryStorage implements BaseStorage {
  final Map<String, dynamic> values = {};

  @override
  Future<bool> delete(String key) async => values.remove(key) != null;

  @override
  Future<dynamic> read(String key) async => values[key];

  @override
  Future<bool> write(String key, dynamic data) async {
    values[key] = data;
    return true;
  }
}

/// A failure result.
SwapQuoteRejected rejected(
  SwapQuoteFailureKind kind, {
  SwapLiquiditySource source = SwapLiquiditySource.routed,
  AssetId? asset,
}) => SwapQuoteRejected(
  SwapQuoteFailure(source: source, kind: kind, asset: asset),
);
