import 'dart:async';

import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Something about a followed swap worth telling the user wherever they are
/// in the app.
class SwapExecutionNotice {
  const SwapExecutionNotice({required this.kind, required this.snapshot});

  /// What happened.
  final SwapExecutionNoticeKind kind;

  /// The swap, as of the notice.
  final SwapExecutionSnapshot snapshot;
}

/// The kind of a [SwapExecutionNotice].
enum SwapExecutionNoticeKind {
  /// It delivered what was asked for.
  completed,

  /// It turned back and returned the funds; nothing is needed of the user.
  refunded,

  /// It finished, but needs the user to look at it.
  needsAttention,

  /// It needs the user to act before it can continue.
  actionRequired,
}

/// A swap the registry knows how to find again.
typedef SwapExecutionRef = ({String id, SwapLiquiditySource source});

/// Owns every swap the app follows, for the whole session.
///
/// A swap outlives the screen that started it — a cross-chain move can run for
/// half an hour — so the handles live here rather than in a page's bloc.
/// Leaving the swap form, switching to Activity or opening another part of
/// the app never loses the live view of a running swap, and swaps still
/// running when the wallet was last closed are picked back up at sign-in.
class SwapExecutionRegistry {
  /// Creates the registry over one executor per source. A lookup that ends in
  /// a [SwapResumeUnconfirmedException] is tried again after [retryDelay].
  SwapExecutionRegistry({
    required List<SwapExecutor> executors,
    required Future<List<SwapExecutionRef>> Function() inFlight,
    Duration retryDelay = const Duration(seconds: 10),
  }) : _executors = {for (final e in executors) e.source: e},
       _inFlight = inFlight,
       _retryDelay = retryDelay;

  final Map<SwapLiquiditySource, SwapExecutor> _executors;
  final Future<List<SwapExecutionRef>> Function() _inFlight;
  final Duration _retryDelay;
  Timer? _inFlightRetry;

  final Map<String, SwapExecutionHandle> _handles = {};
  final Map<String, StreamSubscription<SwapExecutionSnapshot>> _subscriptions =
      {};
  final Map<String, StreamSubscription<DateTime>> _checkSubscriptions = {};
  final Map<String, SwapExecutionSnapshot> _latest = {};
  final Set<String> _acknowledged = {};
  final StreamController<List<SwapExecutionSnapshot>> _executions =
      StreamController<List<SwapExecutionSnapshot>>.broadcast();
  final StreamController<SwapExecutionNotice> _notices =
      StreamController<SwapExecutionNotice>.broadcast();
  final StreamController<SwapExecutionSnapshot> _started =
      StreamController<SwapExecutionSnapshot>.broadcast();
  final StreamController<SwapExecutionSnapshot> _updates =
      StreamController<SwapExecutionSnapshot>.broadcast();
  final StreamController<({String id, DateTime at})> _checks =
      StreamController<({String id, DateTime at})>.broadcast();
  var _generation = 0;

  /// Every swap followed this session, newest first.
  List<SwapExecutionSnapshot> get current {
    final list = _latest.values.toList()
      ..sort((a, b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime);
      });
    return List.unmodifiable(list);
  }

  /// [current], replayed on listen and re-emitted on every change.
  Stream<List<SwapExecutionSnapshot>> get executions => Stream.multi((out) {
    out.add(current);
    final subscription = _executions.stream.listen(out.add);
    out.onCancel = subscription.cancel;
  });

  /// Completions and swaps needing attention, as they happen.
  Stream<SwapExecutionNotice> get notices => _notices.stream;

  /// Swaps started through [start] this session — not ones resumed.
  Stream<SwapExecutionSnapshot> get started => _started.stream;

  /// Every followed swap's changes, one snapshot at a time.
  Stream<SwapExecutionSnapshot> get updates => _updates.stream;

  /// How many followed swaps are still running.
  int get activeCount => _latest.values.where((s) => !s.isTerminal).length;

  /// How many followed swaps need attention and have not been looked at.
  int get unacknowledgedAttentionCount => _latest.values
      .where((s) => s.needsAttention && !_acknowledged.contains(s.id))
      .length;

  /// The latest snapshot of [id], when it is followed.
  SwapExecutionSnapshot? snapshotOf(String id) => _latest[id];

  /// When the engine last answered for [id], whether or not anything
  /// changed; null until it has, or while [id] is not followed.
  DateTime? checkedAt(String id) => _handles[id]?.checkedAt;

  /// [checkedAt] of [id], as each answer arrives, whichever handle follows it.
  Stream<DateTime> checksOf(String id) =>
      _checks.stream.where((check) => check.id == id).map((check) => check.at);

  /// Starts executing [quote] and follows it.
  ///
  /// Rethrows [SwapStartRejectedException] and
  /// [SwapStartUnconfirmedException] from the executor unchanged.
  Future<SwapExecutionSnapshot> start(SwapQuote quote) async {
    final executor = _executors[quote.source];
    if (executor == null) {
      throw const SwapStartRejectedException(SwapStartRejection.unknown);
    }
    final generation = _generation;
    final handle = await executor.start(quote);
    if (_follow(handle, generation) != null && !_started.isClosed) {
      _started.add(handle.latest);
    }
    return handle.latest;
  }

  /// Live snapshots of [id], replaying the latest first. Re-attaches through
  /// the executors when the swap is not followed yet; empty when no source
  /// knows it.
  ///
  /// While the lookup is unconfirmed, reports a
  /// [SwapResumeUnconfirmedException] and tries again, for as long as it is
  /// listened to in this session.
  Stream<SwapExecutionSnapshot> watch(
    String id, {
    SwapLiquiditySource? source,
  }) => Stream.multi((out) {
    final generation = _generation;
    StreamSubscription<SwapExecutionSnapshot>? updates;
    Timer? retry;
    var listening = true;

    Future<void> attach() async {
      if (generation != _generation) {
        unawaited(out.close());
        return;
      }
      var handle = _handles[id];
      if (handle == null) {
        try {
          handle = await _resume(id, source: source, generation: generation);
        } on SwapResumeUnconfirmedException catch (error, trace) {
          if (!listening) return;
          out.addError(error, trace);
          retry = Timer(_retryDelay, () => unawaited(attach()));
          return;
        }
      }
      if (!listening) return;
      if (handle == null) {
        unawaited(out.close());
        return;
      }
      updates = handle.updates.listen(
        out.add,
        onError: out.addError,
        onDone: out.close,
      );
    }

    out.onCancel = () {
      listening = false;
      retry?.cancel();
      return updates?.cancel();
    };
    unawaited(attach());
  });

  /// Stops [id] if that is still possible. See [SwapExecutionHandle.cancel].
  Future<void> cancel(String id) async {
    final handle = _handles[id];
    if (handle == null) {
      throw const SwapCancelRefusedException(SwapCancelRefusal.notSupported);
    }
    await handle.cancel();
  }

  /// Marks [id] as seen, so it no longer counts as needing attention.
  void acknowledge(String id) {
    if (_acknowledged.add(id)) _publish();
  }

  /// Picks up swaps still running from a previous session, trying again later
  /// for those whose lookup is unconfirmed.
  Future<void> resumeInFlight() async {
    final generation = _generation;
    final List<SwapExecutionRef> running;
    try {
      running = await _inFlight();
    } on Object {
      return;
    }
    await _resumeAll(running, generation);
  }

  Future<void> _resumeAll(List<SwapExecutionRef> refs, int generation) async {
    final unanswered = <SwapExecutionRef>[];
    for (final ref in refs) {
      if (generation != _generation) return;
      if (_handles.containsKey(ref.id)) continue;
      try {
        await _resume(ref.id, source: ref.source, generation: generation);
      } on SwapResumeUnconfirmedException {
        unanswered.add(ref);
      }
    }
    if (unanswered.isEmpty || generation != _generation) return;
    _inFlightRetry = Timer(
      _retryDelay,
      () => unawaited(_resumeAll(unanswered, generation)),
    );
  }

  /// Forgets everything — on sign-out, so one wallet's swaps never show in
  /// another's session. The swaps themselves keep running in the engine.
  Future<void> reset() async {
    _generation++;
    _inFlightRetry?.cancel();
    final handles = _handles.values.toList();
    final subscriptions = [
      ..._subscriptions.values,
      ..._checkSubscriptions.values,
    ];
    _handles.clear();
    _subscriptions.clear();
    _checkSubscriptions.clear();
    _latest.clear();
    _acknowledged.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final handle in handles) {
      await handle.close();
    }
    _publish();
  }

  /// Releases everything.
  Future<void> dispose() async {
    await reset();
    await _executions.close();
    await _notices.close();
    await _started.close();
    await _updates.close();
    await _checks.close();
  }

  /// Looks [id] up for session [generation]: the handle now followed, or null
  /// when no source has the swap or that session has ended. Throws
  /// [SwapResumeUnconfirmedException] when none has it and one could not
  /// tell.
  Future<SwapExecutionHandle?> _resume(
    String id, {
    required SwapLiquiditySource? source,
    required int generation,
  }) async {
    final candidates = source == null
        ? _executors.values
        : [?_executors[source]];
    Object? unanswered;
    for (final executor in candidates) {
      try {
        final handle = await executor.resume(id);
        if (handle != null) return _follow(handle, generation);
      } on Object catch (error) {
        unanswered ??= error;
      }
    }
    if (unanswered != null) throw SwapResumeUnconfirmedException(unanswered);
    return null;
  }

  /// Follows [handle], opened in session [generation]: the handle now followed
  /// for its swap, or null, with [handle] closed, once that session has ended.
  SwapExecutionHandle? _follow(SwapExecutionHandle handle, int generation) {
    if (generation != _generation) {
      unawaited(handle.close());
      return null;
    }
    final id = handle.id;
    final followed = _handles[id];
    if (followed != null) {
      if (!identical(followed, handle)) unawaited(handle.close());
      return followed;
    }
    _handles[id] = handle;
    _latest[id] = handle.latest;
    _subscriptions[id] = handle.updates.listen(
      (snapshot) => _update(id, snapshot),
      onError: (Object _) {},
    );
    _checkSubscriptions[id] = handle.checks.listen((at) {
      if (!_checks.isClosed) _checks.add((id: id, at: at));
    });
    _publish();
    return handle;
  }

  void _update(String id, SwapExecutionSnapshot snapshot) {
    final previous = _latest[id];
    _latest[id] = snapshot;
    _publish();
    if (!_updates.isClosed) _updates.add(snapshot);

    final becameTerminal =
        snapshot.isTerminal && !(previous?.isTerminal ?? false);
    final needsAction =
        snapshot.stage == SwapProgressStage.actionRequired &&
        previous?.stage != SwapProgressStage.actionRequired;
    if (_notices.isClosed) return;
    if (needsAction) {
      _notices.add(
        SwapExecutionNotice(
          kind: SwapExecutionNoticeKind.actionRequired,
          snapshot: snapshot,
        ),
      );
    } else if (becameTerminal) {
      // A cancellation the user asked for, or a swap that never matched with
      // nothing moved, is not news worth interrupting anyone for.
      final quiet = switch (snapshot.outcome?.kind) {
        SwapOutcomeKind.cancelled => !snapshot.needsAttention,
        SwapOutcomeKind.noMatch => true,
        _ => false,
      };
      if (!quiet) {
        _notices.add(
          SwapExecutionNotice(
            kind: switch (snapshot.outcome?.kind) {
              SwapOutcomeKind.completed => SwapExecutionNoticeKind.completed,
              SwapOutcomeKind.refunded => SwapExecutionNoticeKind.refunded,
              _ => SwapExecutionNoticeKind.needsAttention,
            },
            snapshot: snapshot,
          ),
        );
      }
    }
  }

  void _publish() {
    if (!_executions.isClosed) _executions.add(current);
  }
}
