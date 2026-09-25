import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers Activity: its three views, paging, partial and failed reads, and
/// the live swaps that stand in for history until history catches up.
void main() {
  const activeView = SwapActivityFilter.active;
  const completedView = SwapActivityFilter.completed;
  const pageSize = SwapActivityBloc.pageSize;

  late FakeExecutor executor;
  late SwapExecutionRegistry registry;
  late _ScriptedHistory history;

  final running = snapshotOf(id: 'running', createdAt: DateTime(2026, 9, 1));
  final done = snapshotOf(
    id: 'done',
    outcome: completed(),
    createdAt: DateTime(2026, 9, 2),
  );

  setUp(() {
    executor = FakeExecutor(SwapLiquiditySource.routed);
    registry = SwapExecutionRegistry(
      executors: [executor],
      inFlight: () async => const [],
    );
    history = _ScriptedHistory();
  });

  tearDown(() => registry.dispose());

  SwapActivityBloc build() {
    final bloc = SwapActivityBloc(history: history, registry: registry);
    addTearDown(bloc.close);
    return bloc;
  }

  Future<SwapActivityBloc> started([
    SwapActivityFilter filter = activeView,
  ]) async {
    final bloc = build()..add(SwapActivityStarted(filter: filter));
    await pumpEventQueue();
    return bloc;
  }

  test('opens on the view asked for, one page of it', () async {
    history.entries[completedView] = [done];
    final bloc = await started(completedView);

    expect(history.calls, [(completedView, pageSize)]);
    expect(bloc.state.filter, completedView);
    expect(bloc.state.status, SwapActivityStatus.ready);
    expect(bloc.state.entries, [done]);
  });

  test(
    'another view loads from its first page, the same one does not',
    () async {
      history
        ..entries[activeView] = [running]
        ..entries[completedView] = [done]
        ..hasMore = true;
      final bloc = await started();
      bloc.add(const SwapActivityMoreRequested());
      await pumpEventQueue();
      expect(bloc.state.limit, pageSize * 2);

      final states = <SwapActivityState>[];
      final subscription = bloc.stream.listen(states.add);
      bloc.add(const SwapActivityFilterChanged(completedView));
      await pumpEventQueue();
      bloc.add(const SwapActivityFilterChanged(completedView));
      await pumpEventQueue();
      await subscription.cancel();

      expect(states.first.status, SwapActivityStatus.loading);
      expect(states.first.history, isEmpty);
      expect(history.calls.skip(2).toList(), [(completedView, pageSize)]);
      expect(bloc.state.limit, pageSize);
      expect(bloc.state.entries, [done]);
    },
  );

  test('more loads the next page, one at a time, until the end', () async {
    history.hasMore = true;
    final bloc = await started();
    history.gate = Completer<void>();
    bloc
      ..add(const SwapActivityMoreRequested())
      ..add(const SwapActivityMoreRequested());
    await pumpEventQueue();
    expect(bloc.state.loadingMore, isTrue);
    expect(history.calls, hasLength(2));

    history
      ..hasMore = false
      ..release();
    await pumpEventQueue();
    expect(history.calls.last, (activeView, pageSize * 2));
    expect(bloc.state.loadingMore, isFalse);
    expect(bloc.state.hasMore, isFalse);

    bloc.add(const SwapActivityMoreRequested());
    await pumpEventQueue();
    expect(history.calls, hasLength(2));
  });

  test('a refresh reloads as many swaps as are shown', () async {
    history.hasMore = true;
    final bloc = await started();
    bloc.add(const SwapActivityMoreRequested());
    await pumpEventQueue();

    bloc.add(const SwapActivityRefreshed());
    await pumpEventQueue();

    expect(history.calls.last, (activeView, pageSize * 2));
  });

  test(
    'a history that cannot be read is an error, not an empty list',
    () async {
      history.hasMore = true;
      final bloc = await started();
      history.errors[activeView] = StateError('offline');

      bloc.add(const SwapActivityMoreRequested());
      await pumpEventQueue();

      expect(bloc.state.status, SwapActivityStatus.error);
      expect(bloc.state.loadingMore, isFalse);
    },
  );

  test('a partial read shows what did load', () async {
    history
      ..entries[activeView] = [running]
      ..failedSources = {SwapLiquiditySource.atomic};
    final bloc = await started();
    expect(bloc.state.status, SwapActivityStatus.ready);
    expect(bloc.state.isPartial, isTrue);

    history.failedSources = SwapLiquiditySource.values.toSet();
    bloc.add(const SwapActivityRefreshed());
    await pumpEventQueue();

    expect(bloc.state.status, SwapActivityStatus.ready);
    expect(bloc.state.entries, [running]);
  });

  test('an answer for a view since left is dropped, even a failure', () async {
    history
      ..entries[completedView] = [done]
      ..errors[activeView] = StateError('offline')
      ..gate = Completer<void>();
    final bloc = build()..add(const SwapActivityStarted());
    await pumpEventQueue();
    final held = history.gate!;
    history.gate = null;
    bloc.add(const SwapActivityFilterChanged(completedView));
    await pumpEventQueue();

    held.complete();
    await pumpEventQueue();

    expect(bloc.state.filter, completedView);
    expect(bloc.state.status, SwapActivityStatus.ready);
    expect(bloc.state.entries, [done]);
  });

  test(
    'a live swap stands in for its entry until it leaves the view',
    () async {
      history.entries[activeView] = [snapshotOf(id: 'routed-1')];
      final bloc = await started();
      await registry.start(quoteOf());
      await pumpEventQueue();
      expect(bloc.state.entries.single.stage, SwapProgressStage.preparing);

      executor.lastStarted!.push(
        snapshotOf(id: 'routed-1', outcome: completed()),
      );
      await pumpEventQueue();

      expect(bloc.state.entries, isEmpty);
      expect(history.calls, [(activeView, pageSize), (activeView, pageSize)]);
    },
  );

  test('a swap first seen already finished does not reload', () async {
    executor.resumable['old'] = FakeHandle(
      snapshotOf(id: 'old', outcome: completed()),
    );
    final bloc = await started();

    await registry.watch('old').first;
    await pumpEventQueue();

    expect(bloc.state.live.single.id, 'old');
    expect(history.calls, hasLength(1));
  });
}

/// Activity pages from a script, holding each read while [gate] is set.
class _ScriptedHistory implements SwapHistoryRepository {
  final Map<SwapActivityFilter, List<SwapExecutionSnapshot>> entries = {};
  final Map<SwapActivityFilter, Object> errors = {};
  final List<(SwapActivityFilter, int)> calls = [];
  Set<SwapLiquiditySource> failedSources = const {};
  bool hasMore = false;
  Completer<void>? gate;

  void release() {
    gate?.complete();
    gate = null;
  }

  @override
  Future<SwapActivityPage> load({
    required SwapActivityFilter filter,
    int limit = 25,
  }) async {
    calls.add((filter, limit));
    await gate?.future;
    final error = errors[filter];
    if (error != null) throw error;
    return SwapActivityPage(
      entries: entries[filter] ?? const [],
      failedSources: failedSources,
      hasMore: hasMore,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
