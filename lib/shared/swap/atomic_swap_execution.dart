import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

part 'atomic_swap_snapshot.dart';

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
        .sellOrThrow(
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

    return _track(uuid, accepted: quote);
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async {
    Swap? swap;
    try {
      swap = await _dex.getSwapStatus(id);
    } on Object {
      final status = await _orders.getStatus(id);
      if (status?.takerOrderStatus == null) return null;
    }
    return _track(id, swap: swap);
  }

  SwapExecutionHandle _track(String uuid, {SwapQuote? accepted, Swap? swap}) {
    final tracker = _AtomicSwapTracker(
      uuid: uuid,
      executor: this,
      accepted: accepted,
    );
    final handle = StreamSwapExecutionHandle(
      initial: tracker.initial(placed: accepted != null, swap: swap),
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

  SwapExecutionSnapshot initial({required bool placed, Swap? swap}) {
    _matched = swap != null;
    if (swap != null) return _last = _fromSwap(swap);
    return _last = _snapshot(
      stage: placed ? SwapProgressStage.matching : SwapProgressStage.preparing,
      canCancel: placed,
    );
  }

  /// Polls until the swap ends; a record found already ended is final.
  void start() => _last?.isTerminal ?? false
      ? unawaited(_controller.close())
      : _schedule(Duration.zero);

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
    } on Object catch (error) {
      // No swap yet: the taker order is still looking for its counterparty,
      // or it expired without one.
      if (!_matched) await _checkOrder(error);
    }
    if (!(_last?.isTerminal ?? false)) _schedule(_executor._pollInterval);
  }

  Future<void> _checkOrder(Object swapError) async {
    final OrderStatus status;
    try {
      status = await _executor._orders.getStatusOrThrow(uuid);
    } on Object catch (error) {
      // Neither an order nor a swap. A fill-or-kill order that never matched
      // is removed; give the engine a few polls before concluding that, and
      // count only KDF saying so: a read that failed proves nothing.
      if (_answered(swapError, 'No swap with uuid $uuid') &&
          _answered(error, 'Order with uuid $uuid is not found') &&
          ++_misses >= _executor._missesBeforeNoMatch) {
        _emit(_terminal(SwapOutcomeKind.noMatch));
      }
      return;
    }
    final taker = status.takerOrderStatus;
    if (taker == null) return;
    _misses = 0;
    switch (taker.cancellationReason) {
      case TakerOrderCancellationReason.timedOut:
        _emit(_terminal(SwapOutcomeKind.noMatch));
      case TakerOrderCancellationReason.cancelled:
        _emit(_terminal(SwapOutcomeKind.cancelled));
      case TakerOrderCancellationReason.fulfilled:
        // Matched: the swap is being set up and can no longer be recalled.
        _matched = true;
        _emit(_snapshot(stage: SwapProgressStage.preparing));
      case TakerOrderCancellationReason.toMaker:
      case TakerOrderCancellationReason.none:
        _emit(_snapshot(stage: SwapProgressStage.matching, canCancel: true));
    }
  }

  /// Whether [error] is KDF answering [words], not a read that failed.
  static bool _answered(Object error, String words) =>
      error is TextError && error.error.contains(words);

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
