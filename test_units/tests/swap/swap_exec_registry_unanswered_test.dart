import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers the registry when a source cannot tell whether it has a swap: the
/// swap is reported unconfirmed and asked about again, never taken for one no
/// source has.
void main() {
  const retryDelay = Duration(seconds: 10);
  const tick = Duration(milliseconds: 1);
  final noAnswer = TimeoutException('no answer from KDF');

  late FakeExecutor routed;
  late FakeExecutor atomic;

  setUp(() {
    routed = FakeExecutor(SwapLiquiditySource.routed);
    atomic = FakeExecutor(SwapLiquiditySource.atomic);
  });

  void run(
    void Function(FakeAsync async, SwapExecutionRegistry registry) body, {
    List<SwapExecutionRef> inFlight = const [],
  }) => fakeAsync((async) {
    final registry = SwapExecutionRegistry(
      executors: [routed, atomic],
      inFlight: () async => inFlight,
      retryDelay: retryDelay,
    );
    body(async, registry);
    unawaited(registry.dispose());
    async.flushMicrotasks();
  });

  group('watching a swap', () {
    test('its source cannot tell about is reported unconfirmed with the '
        'cause, and the watch stays open', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        final watch = _Watch(registry.watch('r-1'));
        async.flushMicrotasks();

        expect(
          watch.errors.single,
          isA<SwapResumeUnconfirmedException>().having(
            (e) => e.cause,
            'cause',
            same(noAnswer),
          ),
        );
        expect(watch.snapshots, isEmpty);
        expect(watch.done, isFalse);
      });
    });

    test('is asked about again after the retry delay, and followed once its '
        'source answers', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        final watch = _Watch(
          registry.watch('r-1', source: SwapLiquiditySource.routed),
        );
        async.flushMicrotasks();
        routed.resumeError = null;
        routed.resumable['r-1'] = FakeHandle(snapshotOf(id: 'r-1'));
        async.elapse(retryDelay - tick);
        expect(routed.resumeCalls, 1);

        async.elapse(tick);
        expect(routed.resumeCalls, 2);
        expect(watch.snapshots.single.id, 'r-1');
        expect(watch.errors, hasLength(1));
        expect(registry.snapshotOf('r-1'), isNotNull);
      });
    });

    test('ends once its source says it does not know the swap', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        final watch = _Watch(
          registry.watch('r-1', source: SwapLiquiditySource.routed),
        );
        async.flushMicrotasks();
        routed.resumeError = null;
        async.elapse(retryDelay);

        expect(watch.done, isTrue);
        expect(watch.snapshots, isEmpty);
      });
    });

    test('with no source named, one that cannot tell keeps it from ending '
        'when the other does not have it', () {
      run((async, registry) {
        atomic.resumeError = noAnswer;
        final watch = _Watch(registry.watch('x-1'));
        async.flushMicrotasks();

        expect(watch.errors.single, isA<SwapResumeUnconfirmedException>());
        expect(watch.done, isFalse);
      });
    });

    test('with no source named, a source that has it wins over one that '
        'cannot tell', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        atomic.resumable['a-1'] = FakeHandle(
          snapshotOf(id: 'a-1', source: SwapLiquiditySource.atomic),
        );
        final watch = _Watch(registry.watch('a-1'));
        async.flushMicrotasks();

        expect(watch.snapshots.single.id, 'a-1');
        expect(watch.errors, isEmpty);
      });
    });

    test('stops asking once no longer listened to', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        final watch = _Watch(registry.watch('r-1'));
        async.flushMicrotasks();
        unawaited(watch.subscription.cancel());
        async.flushMicrotasks();

        expect(async.pendingTimers, isEmpty);
        async.elapse(retryDelay * 3);
        expect(routed.resumeCalls, 1);
      });
    });

    test('a sign-out while waiting to ask again ends the watch without '
        'asking', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        final watch = _Watch(registry.watch('r-1'));
        async.flushMicrotasks();
        unawaited(registry.reset());
        routed.resumeError = null;
        routed.resumable['r-1'] = FakeHandle(snapshotOf(id: 'r-1'));
        async.elapse(retryDelay);

        expect(watch.done, isTrue);
        expect(routed.resumeCalls, 1);
        expect(registry.current, isEmpty);
      });
    });
  });

  group('picking up swaps at sign-in', () {
    const inFlight = [
      (id: 'r-1', source: SwapLiquiditySource.routed),
      (id: 'a-2', source: SwapLiquiditySource.atomic),
    ];

    test('one a source cannot tell about is passed over, and asked about '
        'again until it is picked up', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        atomic.resumable['a-2'] = FakeHandle(
          snapshotOf(id: 'a-2', source: SwapLiquiditySource.atomic),
        );
        unawaited(registry.resumeInFlight());
        async.flushMicrotasks();
        expect(registry.snapshotOf('a-2'), isNotNull);
        expect(registry.snapshotOf('r-1'), isNull);

        async.elapse(retryDelay);
        expect(routed.resumeCalls, 2);
        expect(atomic.resumeCalls, 1);

        routed.resumeError = null;
        routed.resumable['r-1'] = FakeHandle(snapshotOf(id: 'r-1'));
        async.elapse(retryDelay);
        expect(registry.snapshotOf('r-1'), isNotNull);

        async.elapse(retryDelay * 3);
        expect(routed.resumeCalls, 3);
      }, inFlight: inFlight);
    });

    test('one a screen picked up meanwhile is not asked about again', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        unawaited(registry.resumeInFlight());
        async.flushMicrotasks();
        routed.resumeError = null;
        routed.resumable['r-1'] = FakeHandle(snapshotOf(id: 'r-1'));
        _Watch(registry.watch('r-1'));
        async.flushMicrotasks();
        expect(routed.resumeCalls, 2);

        async.elapse(retryDelay);
        expect(routed.resumeCalls, 2);
      }, inFlight: inFlight);
    });

    test('a sign-out stops the asking', () {
      run((async, registry) {
        routed.resumeError = noAnswer;
        unawaited(registry.resumeInFlight());
        async.flushMicrotasks();
        unawaited(registry.reset());
        async.flushMicrotasks();

        expect(async.pendingTimers, isEmpty);
        async.elapse(retryDelay * 2);
        expect(routed.resumeCalls, 1);
      }, inFlight: inFlight);
    });
  });
}

/// Records what a watch reports.
class _Watch {
  _Watch(Stream<SwapExecutionSnapshot> stream) {
    subscription = stream.listen(
      snapshots.add,
      onError: errors.add,
      onDone: () => done = true,
    );
  }

  final List<SwapExecutionSnapshot> snapshots = [];
  final List<Object> errors = [];
  var done = false;
  late final StreamSubscription<SwapExecutionSnapshot> subscription;
}
