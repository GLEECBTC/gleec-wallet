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

/// How long a call to KDF may take before it counts as unanswered; no
/// transport to KDF sets a limit of its own.
const _readTimeout = Duration(seconds: 15);

/// How long KDF may take to log a matched swap's first event, which waits on
/// fee and balance checks on both chains: seconds, normally.
const _unrecordedGrace = Duration(minutes: 5);

/// Whether [error] is KDF answering [words], not a read that failed.
bool _answered(Object error, String words) =>
    error is TextError && error.error.contains(words);

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
    int delayedAfterFailures = 3,
    DateTime Function()? now,
  }) : _dex = dexRepository,
       _orders = orders,
       _networks = networks,
       _resolveAsset = resolveAsset,
       _pollInterval = pollInterval,
       _missesBeforeNoMatch = missesBeforeNoMatch,
       _delayedAfterFailures = delayedAfterFailures,
       _now = now ?? DateTime.now;

  final DexRepository _dex;
  final MyOrdersService _orders;
  final SwapNetworks Function() _networks;
  final AssetId? Function(String ticker) _resolveAsset;
  final Duration _pollInterval;
  final int _missesBeforeNoMatch;
  final int _delayedAfterFailures;
  final DateTime Function() _now;

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

    return _track(uuid, accepted: quote, placedAt: _now());
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async {
    Swap? swap;
    try {
      swap = await _dex.getSwapStatus(id).timeout(_readTimeout);
    } on Object catch (swapError) {
      // KDF has the swap, but has yet to log its first event.
      if (_answered(swapError, 'swap data is not found')) return _track(id);
      // A read that failed or went unanswered proves nothing. Only KDF saying
      // it has no swap leaves a taker order that has yet to match.
      if (!_answered(swapError, 'No swap with uuid $id')) rethrow;
      final OrderStatus status;
      try {
        status = await _orders.getStatusOrThrow(id).timeout(_readTimeout);
      } on Object catch (orderError) {
        if (_answered(orderError, 'Order with uuid $id is not found')) {
          return null;
        }
        rethrow;
      }
      if (status.takerOrderStatus == null) return null;
    }
    return _track(id, swap: swap);
  }

  SwapExecutionHandle _track(
    String uuid, {
    SwapQuote? accepted,
    Swap? swap,
    DateTime? placedAt,
  }) {
    final tracker = _AtomicSwapTracker(
      uuid: uuid,
      executor: this,
      accepted: accepted,
      placedAt: placedAt,
    );
    final handle = StreamSwapExecutionHandle(
      initial: tracker.initial(placed: accepted != null, swap: swap),
      source: tracker.stream,
      cancel: tracker.cancel,
      onClose: tracker.dispose,
      checkedAt: tracker.checkedAt,
      checks: tracker.checks,
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
    this.placedAt,
  }) : _executor = executor,
       // Every tracker starts from a read KDF has just answered.
       checkedAt = executor._now();

  final String uuid;
  final AtomicSwapExecutor _executor;
  final SwapQuote? accepted;

  /// When this session placed the order; KDF's log dates the swap only once
  /// it has matched.
  final DateTime? placedAt;

  final StreamController<SwapExecutionSnapshot> _controller =
      StreamController<SwapExecutionSnapshot>.broadcast();
  final StreamController<DateTime> _checks =
      StreamController<DateTime>.broadcast();
  Timer? _timer;
  var _misses = 0;
  var _matched = false;
  var _disposed = false;
  SwapExecutionSnapshot? _last;

  Swap? _swap;

  /// Polls in a row that KDF left unanswered, and when the first ran.
  var _unanswered = 0;
  DateTime? _unansweredSince;

  /// When KDF first said the matched swap was not recorded yet.
  DateTime? _unrecordedSince;

  Stream<SwapExecutionSnapshot> get stream => _controller.stream;

  /// When KDF last answered for the swap, whether or not anything changed.
  DateTime checkedAt;

  /// [checkedAt], as each answer arrives.
  Stream<DateTime> get checks => _checks.stream;

  SwapExecutionSnapshot initial({required bool placed, Swap? swap}) {
    _matched = swap != null;
    _swap = swap;
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
    final polledAt = _executor._now();
    try {
      _swap = await _executor._dex.getSwapStatus(uuid).timeout(_readTimeout);
      _matched = true;
      _misses = 0;
      _heard();
    } on Object catch (error) {
      if (!_matched) {
        // No swap yet: the taker order is still looking for its counterparty,
        // or it expired without one.
        await _checkOrder(error, polledAt);
      } else if (_swap == null && _unrecorded(error)) {
        _awaitRecord(polledAt);
      } else {
        _unheard(polledAt);
      }
    }
    try {
      _emit(_current());
    } finally {
      if (!(_last?.isTerminal ?? false)) _schedule(_executor._pollInterval);
    }
  }

  Future<void> _checkOrder(Object swapError, DateTime polledAt) async {
    final OrderStatus status;
    try {
      status = await _executor._orders
          .getStatusOrThrow(uuid)
          .timeout(_readTimeout);
    } on Object catch (error) {
      if (_answered(swapError, 'swap data is not found')) {
        // KDF has the swap but has yet to log it, so the order matched.
        _matched = true;
        _awaitRecord(polledAt);
        _emit(_snapshot(stage: SwapProgressStage.preparing));
      } else if (_answered(swapError, 'No swap with uuid $uuid') &&
          _answered(error, 'Order with uuid $uuid is not found')) {
        // Neither an order nor a swap. A fill-or-kill order that never matched
        // is removed; give the engine a few polls before concluding that, and
        // count only KDF saying so: a read that failed proves nothing.
        _heard();
        if (++_misses >= _executor._missesBeforeNoMatch) {
          _emit(_terminal(SwapOutcomeKind.noMatch));
        }
      } else {
        _unheard(polledAt);
      }
      return;
    }
    _heard();
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

  /// Whether [error] is KDF saying it has yet to record this swap: no row at
  /// all, or a row whose first event is not saved yet.
  bool _unrecorded(Object error) =>
      _answered(error, 'No swap with uuid $uuid') ||
      _answered(error, 'swap data is not found');

  DateTime? get _delayedSince =>
      _unanswered >= _executor._delayedAfterFailures ? _unansweredSince : null;

  void _heard() {
    _unanswered = 0;
    _unansweredSince = null;
    checkedAt = _executor._now();
    if (!_checks.isClosed) _checks.add(checkedAt);
  }

  void _unheard(DateTime polledAt) {
    _unansweredSince ??= polledAt;
    _unanswered++;
  }

  /// Counts KDF saying the matched swap is not recorded yet as an answer,
  /// until [_unrecordedGrace] has passed.
  void _awaitRecord(DateTime polledAt) {
    _unrecordedSince ??= polledAt;
    polledAt.difference(_unrecordedSince!) < _unrecordedGrace
        ? _heard()
        : _unheard(polledAt);
  }

  /// [_last] rebuilt with the current delay.
  SwapExecutionSnapshot _current() {
    final last = _last!;
    final swap = _swap;
    if (last.isTerminal) return last;
    if (swap != null) return _fromSwap(swap);
    return _snapshot(stage: last.stage!, canCancel: last.canCancel);
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
    final String? error;
    try {
      error = await _executor._orders.cancelOrder(uuid).timeout(_readTimeout);
    } on Object catch (lost) {
      throw SwapCancelUnconfirmedException(lost);
    }
    if (error != null) {
      throw SwapCancelUnconfirmedException(error);
    }
    _emit(_terminal(SwapOutcomeKind.cancelled));
  }

  void _emit(SwapExecutionSnapshot snapshot) {
    // A swap reported finished stays finished, whatever a late read says.
    if (_disposed || snapshot == _last || (_last?.isTerminal ?? false)) return;
    _last = snapshot;
    if (!_controller.isClosed) _controller.add(snapshot);
    if (snapshot.isTerminal) {
      _timer?.cancel();
      unawaited(_controller.close());
      unawaited(_checks.close());
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    if (!_controller.isClosed) await _controller.close();
    if (!_checks.isClosed) await _checks.close();
  }

  SwapExecutionSnapshot _snapshot({
    required SwapProgressStage stage,
    bool canCancel = false,
    SwapFundsMovement movement = SwapFundsMovement.none,
    SwapExecutionOutcome? outcome,
    DateTime? finishedAt,
  }) => atomicSnapshot(
    uuid: uuid,
    stage: stage,
    canCancel: canCancel,
    movement: movement,
    outcome: outcome,
    accepted: accepted,
    networks: _executor._networks(),
    resolveAsset: _executor._resolveAsset,
    delayedSince: _delayedSince,
    placedAt: placedAt,
    finishedAt: finishedAt,
  );

  SwapExecutionSnapshot _terminal(SwapOutcomeKind kind) => _snapshot(
    stage: SwapProgressStage.matching,
    outcome: SwapExecutionOutcome(kind: kind),
    finishedAt: _executor._now(),
  );

  SwapExecutionSnapshot _fromSwap(Swap swap) => atomicSnapshotFromSwap(
    swap,
    accepted: accepted,
    networks: _executor._networks(),
    resolveAsset: _executor._resolveAsset,
    now: _executor._now(),
    delayedSince: _delayedSince,
    placedAt: placedAt,
  );
}
