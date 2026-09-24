import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Executes atomic swaps by placing a fill-or-kill taker order, and follows
/// them to a terminal outcome.
///
/// Fill-or-kill is the right order type for a quoted swap: the user was shown
/// a price for a specific size, and a resting or partially filled order is a
/// different trade from the one they agreed to.
class AtomicSwapExecutor implements SwapExecutor {
  /// Creates an executor over the DEX repository and order service.
  AtomicSwapExecutor({
    required DexRepository dexRepository,
    required MyOrdersService orders,
    required SwapNetworks Function() networks,
    required AssetId? Function(String ticker) resolveAsset,
    Duration pollInterval = const Duration(seconds: 3),
    int missesBeforeNoMatch = 3,
  }) : _dex = dexRepository,
       _orders = orders,
       _networks = networks,
       _resolveAsset = resolveAsset,
       _pollInterval = pollInterval,
       _missesBeforeNoMatch = missesBeforeNoMatch;

  final DexRepository _dex;
  final MyOrdersService _orders;
  final SwapNetworks Function() _networks;
  final AssetId? Function(String ticker) _resolveAsset;
  final Duration _pollInterval;
  final int _missesBeforeNoMatch;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.atomic;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    final plan = quote.payload;
    if (plan is! AtomicSwapPlan) {
      throw const SwapStartRejectedException(SwapStartRejection.quoteStale);
    }

    final response = await _dex
        .sell(
          SellRequest(
            base: plan.base.id,
            rel: plan.rel.id,
            volume: Rational.parse(plan.volume.toString()),
            price: Rational.parse(plan.price.toString()),
            orderType: SellBuyOrderType.fillOrKill,
          ),
        )
        .catchError(
          (Object error) => throw SwapStartUnconfirmedException(error),
        );

    final error = response.error;
    if (error != null) {
      // KDF answered, so nothing was placed.
      throw SwapStartRejectedException(
        SwapStartRejection.unknown,
        detail: error.message,
      );
    }
    final uuid = response.result?.uuid;
    if (uuid == null) {
      throw SwapStartUnconfirmedException(
        StateError('The order was accepted but returned no reference.'),
      );
    }

    return _track(uuid, accepted: quote, placed: true);
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async {
    try {
      await _dex.getSwapStatus(id);
    } on Object {
      final status = await _orders.getStatus(id);
      if (status?.takerOrderStatus == null) return null;
    }
    return _track(id);
  }

  SwapExecutionHandle _track(
    String uuid, {
    SwapQuote? accepted,
    bool placed = false,
  }) {
    final tracker = _AtomicSwapTracker(
      uuid: uuid,
      executor: this,
      accepted: accepted,
    );
    final handle = StreamSwapExecutionHandle(
      initial: tracker.initial(placed: placed),
      source: tracker.stream,
      cancel: tracker.cancel,
      onClose: tracker.dispose,
    );
    tracker.start();
    return handle;
  }
}

/// Follows one atomic swap: its taker order until matched, then the swap.
class _AtomicSwapTracker {
  _AtomicSwapTracker({
    required this.uuid,
    required AtomicSwapExecutor executor,
    this.accepted,
  }) : _executor = executor;

  final String uuid;
  final AtomicSwapExecutor _executor;
  final SwapQuote? accepted;

  final StreamController<SwapExecutionSnapshot> _controller =
      StreamController<SwapExecutionSnapshot>.broadcast();
  Timer? _timer;
  var _misses = 0;
  var _matched = false;
  var _disposed = false;
  SwapExecutionSnapshot? _last;

  Stream<SwapExecutionSnapshot> get stream => _controller.stream;

  SwapExecutionSnapshot initial({required bool placed}) => _last = _snapshot(
    stage: placed ? SwapProgressStage.matching : SwapProgressStage.preparing,
    canCancel: placed,
  );

  void start() => _schedule(Duration.zero);

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(delay, () => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (_disposed) return;
    try {
      final swap = await _executor._dex.getSwapStatus(uuid);
      _matched = true;
      _misses = 0;
      _emit(_fromSwap(swap));
    } on Object {
      // No swap yet: the taker order is still looking for its counterparty,
      // or it expired without one.
      if (!_matched) await _checkOrder();
    }
    if (!(_last?.isTerminal ?? false)) _schedule(_executor._pollInterval);
  }

  Future<void> _checkOrder() async {
    final status = await _executor._orders.getStatus(uuid);
    final taker = status?.takerOrderStatus;
    if (taker == null) {
      // Neither an order nor a swap. A fill-or-kill order that never matched
      // is removed; give the engine a few polls before concluding that.
      if (++_misses >= _executor._missesBeforeNoMatch) {
        _emit(_terminal(SwapOutcomeKind.noMatch));
      }
      return;
    }
    _misses = 0;
    switch (taker.cancellationReason) {
      case TakerOrderCancellationReason.timedOut:
        _emit(_terminal(SwapOutcomeKind.noMatch));
      case TakerOrderCancellationReason.cancelled:
        _emit(_terminal(SwapOutcomeKind.cancelled));
      case TakerOrderCancellationReason.fulfilled:
      case TakerOrderCancellationReason.toMaker:
      case TakerOrderCancellationReason.none:
        _emit(_snapshot(stage: SwapProgressStage.matching, canCancel: true));
    }
  }

  Future<void> cancel() async {
    final last = _last;
    if (last != null && last.isTerminal) {
      throw const SwapCancelRefusedException(SwapCancelRefusal.alreadyFinished);
    }
    if (_matched || !(last?.canCancel ?? false)) {
      // A matched atomic swap cannot be recalled; its own refund machinery
      // takes over if the counterparty does not complete.
      throw const SwapCancelRefusedException(SwapCancelRefusal.notSupported);
    }
    final error = await _executor._orders.cancelOrder(uuid);
    if (error != null) {
      throw SwapCancelUnconfirmedException(error);
    }
    _emit(_terminal(SwapOutcomeKind.cancelled));
  }

  void _emit(SwapExecutionSnapshot snapshot) {
    if (_disposed || snapshot == _last) return;
    _last = snapshot;
    if (!_controller.isClosed) _controller.add(snapshot);
    if (snapshot.isTerminal) {
      _timer?.cancel();
      unawaited(_controller.close());
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    if (!_controller.isClosed) await _controller.close();
  }

  SwapExecutionSnapshot _snapshot({
    required SwapProgressStage stage,
    bool canCancel = false,
    SwapFundsMovement movement = SwapFundsMovement.none,
    SwapExecutionOutcome? outcome,
  }) => atomicSnapshot(
    uuid: uuid,
    stage: stage,
    canCancel: canCancel,
    movement: movement,
    outcome: outcome,
    accepted: accepted,
    networks: _executor._networks(),
    resolveAsset: _executor._resolveAsset,
  );

  SwapExecutionSnapshot _terminal(SwapOutcomeKind kind) => _snapshot(
    stage: SwapProgressStage.matching,
    outcome: SwapExecutionOutcome(kind: kind),
  );

  SwapExecutionSnapshot _fromSwap(Swap swap) => atomicSnapshotFromSwap(
    swap,
    accepted: accepted,
    networks: _executor._networks(),
    resolveAsset: _executor._resolveAsset,
  );
}

/// Describes an atomic swap at [stage], before or without its event log.
SwapExecutionSnapshot atomicSnapshot({
  required String uuid,
  required SwapProgressStage stage,
  required SwapNetworks networks,
  required AssetId? Function(String ticker) resolveAsset,
  bool canCancel = false,
  SwapFundsMovement movement = SwapFundsMovement.none,
  SwapExecutionOutcome? outcome,
  SwapQuote? accepted,
  Swap? swap,
}) {
  final from =
      accepted?.from ?? (swap == null ? null : resolveAsset(swap.sellCoin));
  final to = accepted?.to ?? (swap == null ? null : resolveAsset(swap.buyCoin));
  String? hashOf(String type) => swap?.events
      .where((e) => e.event.type == type)
      .map((e) => e.event.data?.txHash)
      .whereType<String>()
      .firstOrNull;
  final events = swap?.events ?? const <SwapEventItem>[];
  DateTime? at(int? millis) => millis == null || millis == 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(millis);

  return SwapExecutionSnapshot(
    id: uuid,
    source: SwapLiquiditySource.atomic,
    routeKind: SwapRouteKind.direct,
    from: from,
    fromTicker: from?.id ?? swap?.sellCoin ?? '',
    to: to,
    toTicker: to?.id ?? swap?.buyCoin ?? '',
    sellAmount:
        accepted?.sellAmount ??
        (swap == null ? null : _decimalOf(swap.sellAmount)),
    expectedReceive:
        accepted?.expectedReceive ??
        (swap == null ? null : _decimalOf(swap.buyAmount)),
    minimumReceive:
        accepted?.guaranteedReceive ??
        (swap == null ? null : _decimalOf(swap.buyAmount)),
    fromAddress: accepted?.fromAddress,
    toAddress: accepted?.toAddress,
    stage: outcome == null ? stage : null,
    outcome: outcome,
    fundsMovement: movement,
    canCancel: outcome == null && canCancel,
    stages:
        accepted?.stages ??
        [
          const SwapRouteStage(kind: SwapRouteStageKind.prepare),
          if (from != null)
            SwapRouteStage(
              kind: SwapRouteStageKind.send,
              network: networks.networkOf(from),
              asset: from,
            ),
          if (to != null) ...[
            SwapRouteStage(
              kind: SwapRouteStageKind.exchange,
              network: networks.networkOf(to),
              asset: to,
            ),
            SwapRouteStage(
              kind: SwapRouteStageKind.receive,
              network: networks.networkOf(to),
              asset: to,
            ),
          ],
        ],
    createdAt: at(events.firstOrNull?.timestamp),
    updatedAt: at(events.lastOrNull?.timestamp),
    finishedAt: outcome == null ? null : at(events.lastOrNull?.timestamp),
    evidence: SwapEvidence(
      executionId: uuid,
      sourceTxHash: hashOf('TakerPaymentSent'),
      destinationTxHash: hashOf('MakerPaymentSpent'),
      rawState: events.lastOrNull?.event.type,
      errorType: events
          .map((e) => e.event.type)
          .where((type) => swap?.errorEvents.contains(type) ?? false)
          .firstOrNull,
    ),
  );
}

/// Describes an atomic [swap] from its event log.
///
/// A taker's log runs Started, Negotiated, TakerFeeSent, MakerPaymentReceived
/// (then its confirmation), TakerPaymentSent, MakerPaymentSpent, Finished; a
/// failure adds error events and, once the payment has left, the refund
/// events. KDF closes every swap, successful or not, with Finished.
SwapExecutionSnapshot atomicSnapshotFromSwap(
  Swap swap, {
  required SwapNetworks networks,
  required AssetId? Function(String ticker) resolveAsset,
  SwapQuote? accepted,
}) {
  final types = swap.events.map((e) => e.event.type).toList();
  bool has(String type) => types.contains(type);
  final failed = types.any(swap.errorEvents.contains);
  final paid = has('TakerPaymentSent');
  final refunded =
      has('TakerPaymentRefunded') ||
      has('TakerPaymentRefundedByWatcher') ||
      has('TakerPaymentRefundFinished');
  final refunding =
      has('TakerPaymentWaitRefundStarted') || has('TakerPaymentRefundStarted');

  final movement = paid
      ? SwapFundsMovement.sent
      : has('TakerFeeSent')
      ? SwapFundsMovement.feesOnly
      : SwapFundsMovement.none;

  SwapExecutionSnapshot snapshot(
    SwapProgressStage stage, {
    SwapFundsMovement? movementOverride,
    SwapExecutionOutcome? outcome,
  }) => atomicSnapshot(
    uuid: swap.uuid,
    stage: stage,
    movement: movementOverride ?? movement,
    outcome: outcome,
    accepted: accepted,
    swap: swap,
    networks: networks,
    resolveAsset: resolveAsset,
  );

  if (has('Finished')) {
    if (!failed) {
      return snapshot(
        SwapProgressStage.exchanging,
        movementOverride: SwapFundsMovement.sent,
        outcome: SwapExecutionOutcome(
          kind: SwapOutcomeKind.completed,
          receivedAmount: _decimalOf(swap.buyAmount),
          receivedAsset: accepted?.to ?? resolveAsset(swap.buyCoin),
        ),
      );
    }
    if (refunded) {
      return snapshot(
        SwapProgressStage.refunding,
        movementOverride: SwapFundsMovement.sent,
        outcome: SwapExecutionOutcome(
          kind: SwapOutcomeKind.refunded,
          receivedAsset: accepted?.from ?? resolveAsset(swap.sellCoin),
        ),
      );
    }
    return snapshot(
      SwapProgressStage.exchanging,
      movementOverride: paid ? SwapFundsMovement.uncertain : movement,
      outcome: SwapExecutionOutcome(
        kind: SwapOutcomeKind.failed,
        failure: SwapExecutionFailure(
          reason: SwapFailureReason.exchangeFailed,
          // Before the payment left, trying again is safe; after it, the
          // swap's own recovery in Advanced is the way to the funds.
          nextStep: paid ? SwapNextStep.contactSupport : SwapNextStep.retry,
          retryable: !paid,
          detail: types.where(swap.errorEvents.contains).join(', '),
        ),
      ),
    );
  }

  final stage = refunding
      ? SwapProgressStage.refunding
      : has('MakerPaymentSpent') || paid
      ? SwapProgressStage.exchanging
      : has('MakerPaymentReceived') ||
            has('MakerPaymentWaitConfirmStarted') ||
            has('MakerPaymentValidatedAndConfirmed')
      ? SwapProgressStage.confirming
      : has('TakerFeeSent')
      ? SwapProgressStage.sending
      : SwapProgressStage.preparing;
  return snapshot(stage);
}

Decimal _decimalOf(Rational value) =>
    value.toDecimal(scaleOnInfinitePrecision: 18);
