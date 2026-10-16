import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the registry when an engine answers late: after a sign-out, or
/// after another screen already opened the same swap.
void main() {
  group('an answer that lands after sign-out', () {
    late _SlowExecutor engine;
    late SwapExecutionRegistry registry;

    setUp(() {
      engine = _SlowExecutor();
      registry = SwapExecutionRegistry(
        executors: [engine],
        inFlight: () async => const [],
      );
    });

    tearDown(() => registry.dispose());

    test('to a start leaves the swap unfollowed and unannounced, though the '
        'caller learns it started', () async {
      final started = <SwapExecutionSnapshot>[];
      final subscription = registry.started.listen(started.add);

      final starting = registry.start(quoteOf());
      await registry.reset();
      engine.gate.complete();
      final snapshot = await starting;
      await pumpEventQueue();

      expect(snapshot.id, 'routed-1');
      expect(registry.current, isEmpty);
      expect(started, isEmpty);
      expect(engine.handle!.closed, isTrue);
      await subscription.cancel();
    });

    test('to a re-attach ends the watch without following the swap', () async {
      final seen = <SwapExecutionSnapshot>[];
      var ended = false;
      registry.watch('r-1').listen(seen.add, onDone: () => ended = true);
      await pumpEventQueue();

      await registry.reset();
      engine.gate.complete();
      await pumpEventQueue();

      expect(ended, isTrue);
      expect(seen, isEmpty);
      expect(registry.current, isEmpty);
      expect(engine.handle!.closed, isTrue);
    });
  });

  test('two watches handed the same handle both follow it, and it stays '
      'open', () async {
    final executor = FakeExecutor(SwapLiquiditySource.routed);
    final handle = executor.resumable['r-1'] = FakeHandle(
      snapshotOf(id: 'r-1'),
    );
    final registry = SwapExecutionRegistry(
      executors: [executor],
      inFlight: () async => const [],
    );
    final first = <SwapExecutionSnapshot>[];
    final second = <SwapExecutionSnapshot>[];
    registry.watch('r-1').listen(first.add);
    registry.watch('r-1').listen(second.add);
    await pumpEventQueue();

    handle.push(snapshotOf(id: 'r-1', outcome: completed()));
    await pumpEventQueue();

    expect(handle.closed, isFalse);
    expect(first.last.isSuccess, isTrue);
    expect(second.last.isSuccess, isTrue);
    await registry.dispose();
  });

  test('an atomic swap opened after it finished is not announced as newly '
      'finished', () async {
    final dex = FakeDex()
      ..swaps['a-9'] = atomicSwapOf('a-9', [
        'Started',
        'Negotiated',
        'TakerFeeSent',
        'MakerPaymentReceived',
        'TakerPaymentSent',
        'MakerPaymentSpent',
        'Finished',
      ]);
    final registry = SwapExecutionRegistry(
      executors: [
        AtomicSwapExecutor(
          dexRepository: dex,
          orders: FakeOrders(),
          networks: () => execNetworks,
          resolveAsset: resolveTicker,
        ),
      ],
      inFlight: () async => const [],
    );
    final notices = <SwapExecutionNotice>[];
    final subscription = registry.notices.listen(notices.add);

    final seen = await registry
        .watch('a-9', source: SwapLiquiditySource.atomic)
        .toList();
    await pumpEventQueue();

    expect(seen.map((s) => s.isSuccess), [isTrue]);
    expect(registry.snapshotOf('a-9')!.isSuccess, isTrue);
    expect(notices, isEmpty);
    await subscription.cancel();
    await registry.dispose();
  });
}

/// Opens a handle only once [gate] completes, as an engine slow to answer.
class _SlowExecutor implements SwapExecutor {
  final Completer<void> gate = Completer<void>();
  FakeHandle? handle;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) => _open('routed-1');

  @override
  Future<SwapExecutionHandle?> resume(String id) => _open(id);

  Future<FakeHandle> _open(String id) async {
    await gate.future;
    return handle = FakeHandle(snapshotOf(id: id));
  }
}
