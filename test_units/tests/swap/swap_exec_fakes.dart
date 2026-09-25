import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';

import 'swap_test_fixtures.dart';

/// ETH on Arbitrum: a second EVM network, for cross-chain routes.
final arbEth = assetOf(
  'ETH-ARB20',
  subClass: CoinSubClass.arbitrum,
  chainId: 42161,
);

final execNetworks = SwapNetworks([eth, usdc, btc, gleec, arbEth]);

AssetId? resolveTicker(String ticker) => {
  for (final asset in [eth, usdc, btc, gleec, arbEth]) asset.id: asset,
}[ticker];

/// A routed offer with sensible defaults.
RoutedSwapOffer offerOf({
  AssetId? from,
  AssetId? to,
  String sell = '1',
  String expected = '3000',
  String guaranteed = '2985',
  rpc.RoutedSwapRouteKind kind = rpc.RoutedSwapRouteKind.sameChain,
  rpc.RoutedSwapOrder? order,
  RoutedSwapApprovalInfo? approval,
  Duration? duration = const Duration(seconds: 30),
}) {
  final pay = from ?? eth;
  final receive = to ?? usdc;
  return RoutedSwapOffer(
    from: pay,
    to: receive,
    sellAmount: d(sell),
    expectedReceive: d(expected),
    guaranteedReceive: d(guaranteed),
    kind: kind,
    costs: [
      RoutedSwapCost(
        label: 'Network fee',
        amount: d('0.001'),
        kind: RoutedSwapCostKind.gas,
        isDeductedFromReceive: false,
        assetId: eth,
      ),
    ],
    networkFees: const [],
    legs: const [],
    quotedAt: DateTime.utc(2026, 9, 24, 12),
    provider: 'lifi',
    toolKey: 'stargate',
    toolName: 'Stargate',
    route: rpc.RoutedSwapRoute(
      provider: 'lifi',
      from: rpc.RoutedSwapAmount(amount: sell, coin: pay.id),
      to: rpc.RoutedSwapAmount(amount: expected, coin: receive.id),
      toMinimum: rpc.RoutedSwapAmount(amount: guaranteed, coin: receive.id),
      tool: const rpc.RoutedSwapTool(key: 'stargate', name: 'Stargate'),
      kind: kind,
      steps: const [],
      feeCosts: const [],
      gasCosts: const [],
      totalGasCosts: const [],
    ),
    order: order,
    fromAddress: '0xfrom',
    toAddress: '0xfrom',
    approval: approval,
    estimatedDuration: duration,
  );
}

/// A routed swap snapshot with sensible defaults.
RoutedSwapProgress progressOf({
  String uuid = 'r-1',
  RoutedSwapPhase phase = RoutedSwapPhase.preparing,
  bool canCancel = false,
  RoutedSwapOffer? offer,
  RoutedSwapOffer? executed,
  RoutedSwapReceipt? receipt,
  RoutedSwapFailure? failure,
  List<String> approvals = const [],
  RoutedSwapBridgeStage? bridgeStage,
  RoutedSwapRequest? requested,
  Decimal? minimum,
  Duration? duration,
  List<RoutedSwapGasPaid> gasSpent = const [],
}) => RoutedSwapProgress(
  uuid: uuid,
  phase: phase,
  canCancel: canCancel,
  acceptedOffer: offer,
  executedOffer: executed,
  receipt: receipt,
  failure: failure,
  approvalTxHashes: approvals,
  bridgeStage: bridgeStage,
  requested: requested,
  minToAmountAccepted: minimum,
  estimatedDuration: duration,
  gasSpent: gasSpent,
);

/// A terminal routed failure with sensible defaults.
RoutedSwapFailure failureOf(
  RoutedSwapFailureKind kind, {
  RoutedSwapFundsMovement movement = RoutedSwapFundsMovement.none,
  RoutedSwapRetryPolicy policy = RoutedSwapRetryPolicy.retry,
  String errorType = 'SomeError',
  String message = 'went wrong',
  RoutedSwapOffer? freshOffer,
  rpc.RoutedSwapTxFailureReason? txReason,
  rpc.RoutedSwapPreflightCheck? check,
  RoutedSwapShortfall? shortfall,
  List<String> noRouteReasons = const [],
  String? providerRequestId,
}) => RoutedSwapFailure(
  kind: kind,
  errorType: errorType,
  message: message,
  fundsMovement: movement,
  retryPolicy: policy,
  freshOffer: freshOffer,
  txFailureReason: txReason,
  preflightCheck: check,
  shortfall: shortfall,
  noRouteReasons: noRouteReasons,
  providerRequestId: providerRequestId,
);

/// A routed swap handle whose progress the test pushes, replaying the latest
/// snapshot to every listener as the SDK's does.
class FakeRoutedHandle implements RoutedSwapHandle {
  FakeRoutedHandle(this._latest);

  RoutedSwapProgress _latest;
  final StreamController<RoutedSwapProgress> _updates =
      StreamController<RoutedSwapProgress>.broadcast();
  Object? cancelError;
  int cancelCalls = 0;

  void push(RoutedSwapProgress progress) {
    _latest = progress;
    _updates.add(progress);
  }

  Future<void> end() => _updates.close();

  bool get hasListener => _updates.hasListener;

  @override
  String get uuid => _latest.uuid;

  @override
  RoutedSwapProgress get latest => _latest;

  @override
  Stream<RoutedSwapProgress> get progress => Stream.multi((out) {
    out.add(_latest);
    if (_updates.isClosed) {
      unawaited(out.close());
      return;
    }
    final subscription = _updates.stream.listen(
      out.add,
      onError: out.addError,
      onDone: out.close,
    );
    out.onCancel = subscription.cancel;
  });

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final error = cancelError;
    if (error != null) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A routed swap manager that starts and re-attaches [FakeRoutedHandle]s.
class FakeRoutedManager implements RoutedSwapManager {
  final List<RoutedSwapOffer> started = [];
  final Map<String, FakeRoutedHandle> live = {};
  Object? startError;
  Object? watchError;
  Completer<void>? watchGate;
  int watchCalls = 0;

  /// The first snapshot of a started swap, when not the default.
  RoutedSwapProgress Function(RoutedSwapOffer offer)? seed;

  @override
  Future<RoutedSwapHandle> start(RoutedSwapOffer offer) async {
    started.add(offer);
    final error = startError;
    if (error != null) throw error;
    final handle = FakeRoutedHandle(
      seed?.call(offer) ??
          progressOf(
            uuid: 'r-${started.length}',
            offer: offer,
            canCancel: true,
          ),
    );
    live[handle.uuid] = handle;
    return handle;
  }

  @override
  Future<RoutedSwapHandle> watch(String uuid) async {
    watchCalls++;
    await watchGate?.future;
    final error = watchError;
    if (error != null) throw error;
    final handle = live[uuid];
    if (handle == null) throw RoutedSwapNotFoundException(uuid);
    return handle;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
