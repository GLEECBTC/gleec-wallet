import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers when the engine last answered for a swap: every answer counts,
/// changed or not, and a failed read does not.
void main() {
  final t0 = AtomicRig.startedAt;
  const step = AtomicRig.pollInterval;

  test('an order-book swap counts each answer, and not a failed read', () {
    return onFakeClock((rig) {
      rig.dex.swaps['a-1'] = atomicSwapOf('a-1', const ['Started']);
      rig.start();
      final handle = rig.handle!;
      expect(handle.checkedAt, t0, reason: 'placing the order is an answer');
      final checks = <DateTime>[];
      handle.checks.listen(checks.add);

      rig.firstPoll();
      rig.polls(2);
      expect(checks, [t0, t0.add(step), t0.add(step * 2)]);
      expect(handle.checkedAt, t0.add(step * 2));
      expect(rig.seen.length, lessThan(checks.length));

      rig.dex.statusError = TimeoutException('no answer from KDF');
      rig.polls(2);
      expect(checks, hasLength(3));
      expect(handle.checkedAt, t0.add(step * 2));
    });
  });

  test("a routed swap passes on the SDK's answers", () async {
    final manager = FakeRoutedManager();
    final executor = RoutedSwapExecutor(manager, networks: () => execNetworks);
    final handle = await executor.start(quoteOf(payload: offerOf()));
    final checks = <DateTime>[];
    handle.checks.listen(checks.add);
    final at = DateTime.utc(2026, 10, 1, 12);

    manager.live['r-1']!.check(at);
    await pumpEventQueue();

    expect(checks, [at]);
    expect(handle.checkedAt, at);
    await handle.close();
  });

  group('the registry', () {
    late FakeExecutor routed;
    late SwapExecutionRegistry registry;
    final at = DateTime.utc(2026, 10, 1, 12);

    setUp(() {
      routed = FakeExecutor(SwapLiquiditySource.routed);
      registry = SwapExecutionRegistry(
        executors: [routed],
        inFlight: () async => const [],
      );
    });
    tearDown(() => registry.dispose());

    Future<FakeHandle> follow(String id) async {
      final handle = FakeHandle(snapshotOf(id: id));
      routed.resumable[id] = handle;
      final updates = registry.watch(id).listen((_) {});
      addTearDown(updates.cancel);
      await pumpEventQueue();
      return handle;
    }

    test("passes on each followed swap's answers, and only its own", () async {
      final one = await follow('one');
      final other = await follow('other');
      final heard = <DateTime>[];
      registry.checksOf('one').listen(heard.add);
      expect(registry.checkedAt('one'), isNull);

      one.check(at);
      other.check(at.add(const Duration(seconds: 1)));
      await pumpEventQueue();

      expect(heard, [at]);
      expect(registry.checkedAt('one'), at);
      expect(registry.checkedAt('unknown'), isNull);
    });

    test('forgets them with the session', () async {
      final one = await follow('one');
      final heard = <DateTime>[];
      registry.checksOf('one').listen(heard.add);

      await registry.reset();
      one.check(at);
      await pumpEventQueue();

      expect(one.closed, isTrue);
      expect(heard, isEmpty);
      expect(registry.checkedAt('one'), isNull);
    });
  });
}
