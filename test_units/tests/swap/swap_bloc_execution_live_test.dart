import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_execution/swap_execution_bloc.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers what the progress screen opens on, and which of its changes are
/// live: the screen animates only those, so reopening a swap never replays.
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

  SwapExecutionBloc watching(String id, {SwapExecutionSnapshot? seed}) {
    final bloc = SwapExecutionBloc(registry: registry, seed: seed)
      ..add(SwapExecutionWatched(id, initial: seed));
    addTearDown(bloc.close);
    return bloc;
  }

  test('a seeded screen starts on its seed, with nothing to load', () {
    final seed = snapshotOf(id: 'known');
    final bloc = SwapExecutionBloc(registry: registry, seed: seed);
    addTearDown(bloc.close);

    expect(bloc.state.snapshot, same(seed));
    expect(bloc.state.loading, isFalse);
    expect(bloc.state.live, isFalse);
  });

  test('without a seed it starts loading, as before', () {
    final bloc = SwapExecutionBloc(registry: registry);
    addTearDown(bloc.close);

    expect(bloc.state, const SwapExecutionState());
  });

  test(
    'the snapshot the watch opens with is not live; later ones are',
    () async {
      final started = await registry.start(quoteOf());
      final handle = executor.lastStarted!;
      final bloc = watching(started.id, seed: registry.snapshotOf(started.id));
      await pumpEventQueue();
      expect(bloc.state.live, isFalse);

      handle.push(snapshotOf(id: started.id, stage: SwapProgressStage.sending));
      await pumpEventQueue();
      expect(bloc.state.live, isTrue);
      expect(bloc.state.snapshot!.stage, SwapProgressStage.sending);

      handle.push(snapshotOf(id: started.id, outcome: completed()));
      await pumpEventQueue();
      expect(bloc.state.live, isTrue);
      expect(bloc.state.snapshot!.isTerminal, isTrue);
    },
  );

  test('a stale snapshot from history that the engine answers as finished '
      'is not live', () async {
    executor.resumable['old'] = FakeHandle(
      snapshotOf(id: 'old', outcome: completed()),
    );
    final bloc = watching('old', seed: snapshotOf(id: 'old'));
    await pumpEventQueue();

    expect(bloc.state.snapshot!.isTerminal, isTrue);
    expect(bloc.state.live, isFalse);
  });

  test('following another swap starts again from not live', () async {
    final first = await registry.start(quoteOf());
    final firstHandle = executor.lastStarted!;
    final second = await registry.start(quoteOf());
    final secondHandle = executor.lastStarted!;
    final bloc = watching(first.id);
    await pumpEventQueue();
    firstHandle.push(snapshotOf(id: first.id));
    await pumpEventQueue();
    expect(bloc.state.live, isTrue);

    bloc.add(SwapExecutionWatched(second.id));
    await pumpEventQueue();
    expect(bloc.state.snapshot!.id, second.id);
    expect(bloc.state.live, isFalse);

    secondHandle.push(snapshotOf(id: second.id));
    await pumpEventQueue();
    expect(bloc.state.live, isTrue);
  });

  test('a cancel answer keeps whether the snapshot was live', () async {
    final started = await registry.start(quoteOf());
    final handle = executor.lastStarted!;
    final bloc = watching(started.id);
    await pumpEventQueue();
    handle.push(snapshotOf(id: started.id, canCancel: true));
    await pumpEventQueue();

    bloc.add(const SwapExecutionCancelRequested());
    await pumpEventQueue();

    expect(bloc.state.cancelStatus, SwapCancelStatus.idle);
    expect(bloc.state.live, isTrue);
  });

  test('the first answer after the engine was silent is not live', () {
    fakeAsync((async) {
      const retryDelay = Duration(seconds: 10);
      executor.resumeError = TimeoutException('no answer');
      final slow = SwapExecutionRegistry(
        executors: [executor],
        inFlight: () async => const [],
        retryDelay: retryDelay,
      );
      final bloc = SwapExecutionBloc(registry: slow)
        ..add(const SwapExecutionWatched('slow'));
      async.flushMicrotasks();
      expect(bloc.state.unanswered, isTrue);

      executor.resumeError = null;
      executor.resumable['slow'] = FakeHandle(snapshotOf(id: 'slow'));
      async.elapse(retryDelay);

      expect(bloc.state.snapshot!.id, 'slow');
      expect(bloc.state.live, isFalse);
      unawaited(bloc.close());
      unawaited(slow.dispose());
      async.flushMicrotasks();
    });
  });
}
