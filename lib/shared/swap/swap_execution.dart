import 'dart:async';

import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// A running or finished swap the caller can follow and possibly stop.
abstract interface class SwapExecutionHandle {
  /// The durable id.
  String get id;

  /// The most recent snapshot.
  SwapExecutionSnapshot get latest;

  /// Snapshots until terminal. Each access replays [latest] first.
  Stream<SwapExecutionSnapshot> get updates;

  /// Stops the swap if that is still possible.
  ///
  /// Throws [SwapCancelRefusedException] when it is not, and
  /// [SwapCancelUnconfirmedException] when the answer could not be read.
  Future<void> cancel();

  /// Stops following the swap. The swap itself keeps running in the engine.
  Future<void> close();
}

/// Starts and resumes swaps for one liquidity source.
abstract interface class SwapExecutor {
  /// Which source this executes for.
  SwapLiquiditySource get source;

  /// Begins executing [quote].
  ///
  /// Throws [SwapStartRejectedException] when the engine refused before
  /// anything started, and [SwapStartUnconfirmedException] when the swap may
  /// have started but could not be confirmed.
  Future<SwapExecutionHandle> start(SwapQuote quote);

  /// Re-attaches to a swap by its durable id, or null when this source does
  /// not know it.
  Future<SwapExecutionHandle?> resume(String id);
}

/// The engine refused to start a swap. Nothing started.
class SwapStartRejectedException implements Exception {
  const SwapStartRejectedException(this.reason, {this.detail});

  /// Why, in terms the entry form already explains.
  final SwapStartRejection reason;

  /// Diagnostic text.
  final String? detail;

  @override
  String toString() => 'SwapStartRejectedException(${reason.name}): $detail';
}

/// Why a start was refused.
enum SwapStartRejection {
  /// The quote went stale; price again.
  quoteStale,

  /// Not enough balance for the swap and its fees.
  insufficientBalance,

  /// The pair or amount is no longer accepted.
  notAvailable,

  /// Something else; retrying may work.
  unknown,
}

/// The swap may have started, but the engine's answer was lost.
///
/// Never re-arm a start button on this: the engine may already be running the
/// swap, and a second tap is a second real swap. Point the user at Activity.
class SwapStartUnconfirmedException implements Exception {
  const SwapStartUnconfirmedException(this.cause);

  /// What went wrong.
  final Object cause;

  @override
  String toString() => 'Could not confirm whether the swap started: $cause';
}

/// A cancel request was refused.
class SwapCancelRefusedException implements Exception {
  const SwapCancelRefusedException(this.reason);

  /// Why.
  final SwapCancelRefusal reason;

  @override
  String toString() => 'SwapCancelRefusedException(${reason.name})';
}

/// Why a cancel was refused.
enum SwapCancelRefusal {
  /// Already handed to the network.
  alreadySent,

  /// Already finished.
  alreadyFinished,

  /// This kind of swap cannot be stopped once it has begun.
  notSupported,
}

/// A cancel request's answer could not be read. The swap may or may not
/// have stopped; its updates keep reporting the truth.
class SwapCancelUnconfirmedException implements Exception {
  const SwapCancelUnconfirmedException(this.cause);

  /// What went wrong.
  final Object cause;

  @override
  String toString() => 'Could not confirm cancelling the swap: $cause';
}

/// A handle over a stream of snapshots, shared by both executors.
class StreamSwapExecutionHandle implements SwapExecutionHandle {
  StreamSwapExecutionHandle({
    required SwapExecutionSnapshot initial,
    required Stream<SwapExecutionSnapshot> source,
    required Future<void> Function() cancel,
    Future<void> Function()? onClose,
  }) : _latest = initial,
       _cancel = cancel,
       _onClose = onClose {
    _subscription = source.listen(
      _add,
      onError: (Object error, StackTrace trace) {
        if (!_controller.isClosed) _controller.addError(error, trace);
      },
      onDone: () => unawaited(_controller.close()),
    );
  }

  SwapExecutionSnapshot _latest;
  final Future<void> Function() _cancel;
  final Future<void> Function()? _onClose;
  final StreamController<SwapExecutionSnapshot> _controller =
      StreamController<SwapExecutionSnapshot>.broadcast();
  late final StreamSubscription<SwapExecutionSnapshot> _subscription;

  void _add(SwapExecutionSnapshot snapshot) {
    if (snapshot == _latest) return;
    _latest = snapshot;
    if (!_controller.isClosed) _controller.add(snapshot);
  }

  @override
  String get id => _latest.id;

  @override
  SwapExecutionSnapshot get latest => _latest;

  @override
  Stream<SwapExecutionSnapshot> get updates => Stream.multi((out) {
    out.add(_latest);
    if (_controller.isClosed) {
      unawaited(out.close());
      return;
    }
    final subscription = _controller.stream.listen(
      out.add,
      onError: out.addError,
      onDone: out.close,
    );
    out.onCancel = subscription.cancel;
  });

  @override
  Future<void> cancel() => _cancel();

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _onClose?.call();
    if (!_controller.isClosed) await _controller.close();
  }
}
