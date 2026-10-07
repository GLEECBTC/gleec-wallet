import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers the app-wide owner of running swaps.
///
/// A swap outlives the screen that started it, so the registry — not a page
/// bloc — holds it: leaving the form must never lose the live view of a swap,
/// and a swap still running at the last sign-out is picked back up.
void main() {
  late FakeExecutor routed;
  late FakeExecutor atomic;
  late List<SwapExecutionRef> inFlight;
  late SwapExecutionRegistry registry;

  setUp(() {
    routed = FakeExecutor(SwapLiquiditySource.routed);
    atomic = FakeExecutor(SwapLiquiditySource.atomic);
    inFlight = [];
    registry = SwapExecutionRegistry(
      executors: [routed, atomic],
      inFlight: () async => inFlight,
    );
  });

  tearDown(() => registry.dispose());

  test('starts on the quote\'s own source and follows the swap', () async {
    final started = <SwapExecutionSnapshot>[];
    final sub = registry.started.listen(started.add);

    final snapshot = await registry.start(
      quoteOf(source: SwapLiquiditySource.atomic),
    );
    await pumpEventQueue();

    expect(atomic.started, hasLength(1));
    expect(routed.started, isEmpty);
    expect(registry.snapshotOf(snapshot.id), isNotNull);
    expect(registry.activeCount, 1);
    expect(started.single.id, snapshot.id);
    await sub.cancel();
  });

  test('passes a lost start answer through untouched', () async {
    routed.startError = const SwapStartUnconfirmedException('timeout');

    await expectLater(
      registry.start(quoteOf()),
      throwsA(isA<SwapStartUnconfirmedException>()),
    );
    expect(registry.current, isEmpty);
  });

  group('notices', () {
    Future<List<SwapExecutionNotice>> run(SwapExecutionSnapshot end) async {
      final notices = <SwapExecutionNotice>[];
      final sub = registry.notices.listen(notices.add);
      await registry.start(quoteOf());
      routed.lastStarted!.push(end);
      await pumpEventQueue();
      await sub.cancel();
      return notices;
    }

    test('announces a completion', () async {
      final notices = await run(
        snapshotOf(id: 'routed-1', outcome: completed()),
      );
      expect(notices.single.kind, SwapExecutionNoticeKind.completed);
    });

    test('flags a failure after funds moved', () async {
      final notices = await run(
        snapshotOf(
          id: 'routed-1',
          outcome: failed(SwapFailureReason.routeFailed),
        ),
      );
      expect(notices.single.kind, SwapExecutionNoticeKind.needsAttention);
      expect(registry.unacknowledgedAttentionCount, 1);
    });

    test('stays quiet about a cancellation the user asked for', () async {
      final notices = await run(
        snapshotOf(
          id: 'routed-1',
          fundsMovement: SwapFundsMovement.none,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        ),
      );
      expect(notices, isEmpty);
    });

    test('flags a cancellation that left a permission behind', () async {
      final notices = await run(
        snapshotOf(
          id: 'routed-1',
          fundsMovement: SwapFundsMovement.feesOnly,
          approvalRemains: true,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        ),
      );
      expect(notices.single.kind, SwapExecutionNoticeKind.needsAttention);
    });

    test('asks for action once when the route needs it', () async {
      final notices = <SwapExecutionNotice>[];
      final sub = registry.notices.listen(notices.add);
      await registry.start(quoteOf());
      final action = snapshotOf(
        id: 'routed-1',
        stage: SwapProgressStage.actionRequired,
      );
      routed.lastStarted!
        ..push(action)
        ..push(action);
      await pumpEventQueue();
      await sub.cancel();

      expect(notices.map((n) => n.kind), [
        SwapExecutionNoticeKind.actionRequired,
      ]);
    });

    test('acknowledging clears the attention count', () async {
      await run(
        snapshotOf(
          id: 'routed-1',
          outcome: failed(SwapFailureReason.routeFailed),
        ),
      );
      registry.acknowledge('routed-1');
      expect(registry.unacknowledgedAttentionCount, 0);
    });
  });

  group('resume', () {
    test('picks up swaps still running at sign-in', () async {
      atomic.resumable['a-1'] = FakeHandle(
        snapshotOf(id: 'a-1', source: SwapLiquiditySource.atomic),
      );
      inFlight = [(id: 'a-1', source: SwapLiquiditySource.atomic)];

      await registry.resumeInFlight();

      expect(registry.snapshotOf('a-1'), isNotNull);
      expect(registry.activeCount, 1);
    });

    test(
      'watching an unfollowed swap re-attaches through its source',
      () async {
        routed.resumable['r-9'] = FakeHandle(snapshotOf(id: 'r-9'));

        final first = await registry.watch('r-9').first;

        expect(first.id, 'r-9');
        expect(registry.snapshotOf('r-9'), isNotNull);
      },
    );

    test('watching a swap nobody knows ends quietly', () async {
      final snapshots = await registry.watch('nope').toList();
      expect(snapshots, isEmpty);
    });

    test('a reset during resume never leaks the old wallet\'s swaps', () async {
      final gate = Completer<List<SwapExecutionRef>>();
      final slow = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () => gate.future,
      );
      routed.resumable['r-1'] = FakeHandle(snapshotOf(id: 'r-1'));

      final resuming = slow.resumeInFlight();
      await slow.reset();
      gate.complete([(id: 'r-1', source: SwapLiquiditySource.routed)]);
      await resuming;

      expect(slow.current, isEmpty);
      await slow.dispose();
    });
  });

  test('cancel without a followed swap is refused, not ignored', () async {
    await expectLater(
      registry.cancel('unknown'),
      throwsA(
        isA<SwapCancelRefusedException>().having(
          (e) => e.reason,
          'reason',
          SwapCancelRefusal.notSupported,
        ),
      ),
    );
  });

  test('reset forgets swaps and releases their handles', () async {
    await registry.start(quoteOf());
    final handle = routed.lastStarted!;

    await registry.reset();

    expect(registry.current, isEmpty);
    expect(handle.closed, isTrue);
  });
}
