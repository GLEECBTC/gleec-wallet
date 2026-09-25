import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the registry's bookkeeping beyond starting and notices: ordering,
/// the per-change feed, and never following one swap twice.
void main() {
  late FakeExecutor routed;
  late List<SwapExecutionRef> inFlight;
  late SwapExecutionRegistry registry;

  setUp(() {
    routed = FakeExecutor(SwapLiquiditySource.routed);
    inFlight = [];
    registry = SwapExecutionRegistry(
      executors: [routed],
      inFlight: () async => inFlight,
    );
  });

  tearDown(() => registry.dispose());

  void resumable(String id, {DateTime? createdAt}) {
    routed.resumable[id] = FakeHandle(snapshotOf(id: id, createdAt: createdAt));
    inFlight.add((id: id, source: SwapLiquiditySource.routed));
  }

  test('lists followed swaps newest first', () async {
    resumable('older', createdAt: DateTime(2026, 9, 1));
    resumable('newer', createdAt: DateTime(2026, 9, 2));
    resumable('middle', createdAt: DateTime(2026, 9, 1, 12));

    await registry.resumeInFlight();

    expect(registry.current.map((s) => s.id), ['newer', 'middle', 'older']);
  });

  test('lists a swap without a start time alongside dated ones', () async {
    resumable('dated', createdAt: DateTime(2026, 9, 1));
    resumable('undated');

    await registry.resumeInFlight();

    expect(
      registry.current.map((s) => s.id),
      unorderedEquals(['dated', 'undated']),
    );
    expect(() => registry.current.add(snapshotOf()), throwsUnsupportedError);
  });

  test('feeds every change of every followed swap, one at a time', () async {
    final changes = <SwapExecutionSnapshot>[];
    final subscription = registry.updates.listen(changes.add);
    await registry.start(quoteOf());
    final first = routed.lastStarted!;
    await registry.start(quoteOf());
    final second = routed.lastStarted!;
    await pumpEventQueue();
    final (firstStart, secondStart) = (first.latest, second.latest);
    final sending = snapshotOf(id: first.id, stage: SwapProgressStage.sending);
    final done = snapshotOf(id: second.id, outcome: completed());

    first.push(sending);
    second.push(done);
    await pumpEventQueue();
    await subscription.cancel();

    expect(changes, [firstStart, secondStart, sending, done]);
  });

  test('keeps following a swap whose feed reports an error', () async {
    final engine = StreamController<SwapExecutionSnapshot>.broadcast();
    final errors = SwapExecutionRegistry(
      executors: [_StreamExecutor(engine)],
      inFlight: () async => const [],
    );
    await errors.watch('s-1').first;

    engine
      ..addError(StateError('status read failed'))
      ..add(snapshotOf(id: 's-1', stage: SwapProgressStage.sending));
    await pumpEventQueue();

    expect(errors.snapshotOf('s-1')!.stage, SwapProgressStage.sending);
    await errors.dispose();
  });

  test('a second handle for a swap already followed is let go', () async {
    final twin = _TwinExecutor();
    final twins = SwapExecutionRegistry(
      executors: [twin],
      inFlight: () async => const [],
    );

    await twins.start(quoteOf());
    await twins.start(quoteOf());
    await pumpEventQueue();

    expect(twins.current, hasLength(1));
    expect(twin.handles.first.closed, isFalse);
    expect(twin.handles.last.closed, isTrue);

    twin.handles.first.push(snapshotOf(id: 'twin', outcome: completed()));
    await pumpEventQueue();
    expect(twins.snapshotOf('twin')!.isSuccess, isTrue);
    await twins.dispose();
  });

  test(
    'two screens opening the same swap at once both follow it to the end',
    () async {
      final manager = FakeRoutedManager()..watchGate = Completer<void>();
      final engine = manager.live['r-1'] = FakeRoutedHandle(
        progressOf(uuid: 'r-1', phase: RoutedSwapPhase.bridging),
      );
      final shared = SwapExecutionRegistry(
        executors: [RoutedSwapExecutor(manager, networks: () => execNetworks)],
        inFlight: () async => const [],
      );
      final first = <SwapExecutionSnapshot>[];
      final second = <SwapExecutionSnapshot>[];
      shared.watch('r-1').listen(first.add);
      shared.watch('r-1').listen(second.add);
      await pumpEventQueue();
      manager.watchGate!.complete();
      await pumpEventQueue();

      engine.push(
        progressOf(
          uuid: 'r-1',
          phase: RoutedSwapPhase.finished,
          receipt: RoutedSwapReceipt(
            outcome: RoutedSwapOutcome.completed,
            amount: d('1'),
            assetId: usdc,
          ),
        ),
      );
      await pumpEventQueue();

      expect(manager.watchCalls, 2);
      expect(first.last.isSuccess, isTrue);
      expect(second.last.isSuccess, isTrue);
      await shared.dispose();
    },
  );

  test('a sign-out while a swap is being re-attached never leaks it', () async {
    final manager = FakeRoutedManager()..watchGate = Completer<void>();
    manager.live['r-1'] = FakeRoutedHandle(progressOf(uuid: 'r-1'));
    final shared = SwapExecutionRegistry(
      executors: [RoutedSwapExecutor(manager, networks: () => execNetworks)],
      inFlight: () async => [(id: 'r-1', source: SwapLiquiditySource.routed)],
    );

    final resuming = shared.resumeInFlight();
    await pumpEventQueue();
    await shared.reset();
    manager.watchGate!.complete();
    await resuming;

    expect(shared.current, isEmpty);
    await shared.dispose();
  });
}

/// Re-attaches one swap over a feed the test controls.
class _StreamExecutor implements SwapExecutor {
  _StreamExecutor(this.engine);

  final StreamController<SwapExecutionSnapshot> engine;

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle?> resume(String id) async =>
      StreamSwapExecutionHandle(
        initial: snapshotOf(id: id),
        source: engine.stream,
        cancel: () async {},
      );

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) =>
      throw UnimplementedError();
}

/// Hands out a fresh handle for the same swap on every start.
class _TwinExecutor implements SwapExecutor {
  final List<FakeHandle> handles = [];

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    final handle = FakeHandle(snapshotOf(id: 'twin'));
    handles.add(handle);
    return handle;
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async => null;
}
