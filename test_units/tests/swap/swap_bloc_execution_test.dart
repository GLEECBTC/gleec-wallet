import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_execution/swap_execution_bloc.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers the progress screen's bloc: which swap it follows, how it reads a
/// swap it cannot follow, and every answer a cancel can get.
void main() {
  late FakeExecutor executor;
  late SwapExecutionRegistry registry;

  setUp(() {
    executor = FakeExecutor(SwapLiquiditySource.routed);
    registry = SwapExecutionRegistry(
      executors: [executor],
      inFlight: () async => const [],
    );
  });

  tearDown(() => registry.dispose());

  SwapExecutionBloc watching(String id) {
    final bloc = SwapExecutionBloc(registry: registry)
      ..add(SwapExecutionWatched(id));
    addTearDown(bloc.close);
    return bloc;
  }

  test('watching the swap already watched changes nothing', () async {
    final started = await registry.start(quoteOf());
    final bloc = watching(started.id);
    await pumpEventQueue();
    final states = <SwapExecutionState>[];
    final subscription = bloc.stream.listen(states.add);

    bloc.add(SwapExecutionWatched(started.id));
    await pumpEventQueue();
    await subscription.cancel();

    expect(states, isEmpty);
    expect(bloc.state.snapshot!.id, started.id);
  });

  test('watching another swap follows it instead', () async {
    final first = await registry.start(quoteOf());
    final firstHandle = executor.lastStarted!;
    final second = await registry.start(quoteOf());
    final bloc = watching(first.id);
    await pumpEventQueue();

    bloc.add(SwapExecutionWatched(second.id));
    await pumpEventQueue();
    firstHandle.push(snapshotOf(id: first.id, outcome: completed()));
    await pumpEventQueue();

    expect(bloc.state.snapshot!.id, second.id);
    expect(bloc.state.snapshot!.isTerminal, isFalse);
  });

  test('a swap whose updates fail before any arrive is not found', () async {
    executor.resumable['lost'] = _FailingHandle(snapshotOf(id: 'lost'));
    final bloc = watching('lost');
    await pumpEventQueue();

    expect(bloc.state.notFound, isTrue);
    expect(bloc.state.loading, isFalse);
    expect(bloc.state.snapshot, isNull);
  });

  group('cancelling', () {
    Future<(SwapExecutionBloc, FakeHandle)> running() async {
      final started = await registry.start(quoteOf());
      final bloc = watching(started.id);
      await pumpEventQueue();
      return (bloc, executor.lastStarted!);
    }

    test('an accepted cancel settles back to idle', () async {
      final (bloc, handle) = await running();
      final states = <SwapExecutionState>[];
      final subscription = bloc.stream.listen(states.add);

      bloc.add(const SwapExecutionCancelRequested());
      await pumpEventQueue();
      await subscription.cancel();

      expect(handle.cancelCalls, 1);
      expect(states.map((s) => s.cancelStatus), [
        SwapCancelStatus.cancelling,
        SwapCancelStatus.idle,
      ]);
    });

    test('each refusal says whether stopping is still possible', () async {
      final expected = {
        SwapCancelRefusal.alreadySent: SwapCancelStatus.refusedAlreadySent,
        SwapCancelRefusal.alreadyFinished: SwapCancelStatus.idle,
        SwapCancelRefusal.notSupported: SwapCancelStatus.refusedNotSupported,
      };
      for (final MapEntry(key: refusal, value: status) in expected.entries) {
        final (bloc, handle) = await running();
        handle.cancelError = SwapCancelRefusedException(refusal);

        bloc.add(const SwapExecutionCancelRequested());
        await pumpEventQueue();

        expect(bloc.state.cancelStatus, status, reason: refusal.name);
      }
    });

    test('nothing is cancelled before a swap is watched', () async {
      final bloc = SwapExecutionBloc(registry: registry)
        ..add(const SwapExecutionCancelRequested());
      addTearDown(bloc.close);
      await pumpEventQueue();

      expect(bloc.state, const SwapExecutionState());
    });

    test('a second cancel while one is pending is not sent', () async {
      final handle = _SlowCancelHandle(snapshotOf(id: 'slow', canCancel: true));
      executor.resumable['slow'] = handle;
      final bloc = watching('slow');
      await pumpEventQueue();

      bloc
        ..add(const SwapExecutionCancelRequested())
        ..add(const SwapExecutionCancelRequested());
      await pumpEventQueue();
      expect(bloc.state.cancelStatus, SwapCancelStatus.cancelling);

      handle.gate.complete();
      await pumpEventQueue();

      expect(handle.cancelCalls, 1);
      expect(bloc.state.cancelStatus, SwapCancelStatus.idle);
    });
  });
}

/// A handle whose updates fail before replaying anything.
class _FailingHandle extends FakeHandle {
  _FailingHandle(super.latest);

  @override
  Stream<SwapExecutionSnapshot> get updates =>
      Stream.error(StateError('status unavailable'));
}

/// A handle whose cancel waits for [gate].
class _SlowCancelHandle extends FakeHandle {
  _SlowCancelHandle(super.latest);

  final gate = Completer<void>();

  @override
  Future<void> cancel() async {
    await gate.future;
    return super.cancel();
  }
}
