import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/swap_execution/swap_execution_bloc.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers the two blocs that watch swaps without owning them: the progress
/// screen's and Activity's.
void main() {
  late FakeExecutor routed;
  late SwapExecutionRegistry registry;

  setUp(() {
    routed = FakeExecutor(SwapLiquiditySource.routed);
    registry = SwapExecutionRegistry(
      executors: [routed],
      inFlight: () async => const [],
    );
  });

  tearDown(() => registry.dispose());

  group('SwapExecutionBloc', () {
    test('follows the swap and marks it seen', () async {
      final started = await registry.start(quoteOf());
      final bloc = SwapExecutionBloc(registry: registry)
        ..add(SwapExecutionWatched(started.id));
      await pumpEventQueue();

      routed.lastStarted!.push(
        snapshotOf(
          id: started.id,
          outcome: failed(SwapFailureReason.routeFailed),
        ),
      );
      await pumpEventQueue();

      expect(bloc.state.snapshot!.isTerminal, isTrue);
      expect(registry.unacknowledgedAttentionCount, 0);
      await bloc.close();
    });

    test('shows a history snapshot at once for an old swap', () async {
      routed.resumable['old'] = FakeHandle(
        snapshotOf(id: 'old', outcome: completed()),
      );
      final bloc = SwapExecutionBloc(registry: registry)
        ..add(
          SwapExecutionWatched(
            'old',
            source: SwapLiquiditySource.routed,
            initial: snapshotOf(id: 'old', outcome: completed()),
          ),
        );
      await pumpEventQueue(times: 1);

      expect(bloc.state.loading, isFalse);
      expect(bloc.state.snapshot, isNotNull);
      await bloc.close();
    });

    test('reports a swap no source knows', () async {
      final bloc = SwapExecutionBloc(registry: registry)
        ..add(const SwapExecutionWatched('ghost'));
      await pumpEventQueue();

      expect(bloc.state.notFound, isTrue);
      await bloc.close();
    });

    test('an already-sent swap refuses to cancel, gently', () async {
      final started = await registry.start(quoteOf());
      routed.lastStarted!.cancelError = const SwapCancelRefusedException(
        SwapCancelRefusal.alreadySent,
      );
      final bloc = SwapExecutionBloc(registry: registry)
        ..add(SwapExecutionWatched(started.id))
        ..add(const SwapExecutionCancelRequested());
      await pumpEventQueue();

      expect(bloc.state.cancelStatus, SwapCancelStatus.refusedAlreadySent);
      await bloc.close();
    });

    test('a lost cancel answer is reported as unconfirmed', () async {
      final started = await registry.start(quoteOf());
      routed.lastStarted!.cancelError = StateError('socket closed');
      final bloc = SwapExecutionBloc(registry: registry)
        ..add(SwapExecutionWatched(started.id))
        ..add(const SwapExecutionCancelRequested());
      await pumpEventQueue();

      expect(bloc.state.cancelStatus, SwapCancelStatus.unconfirmed);
      await bloc.close();
    });
  });

  group('SwapActivityBloc', () {
    SwapHistoryRepository historyOf(List<SwapExecutionSnapshot> entries) =>
        _FakeHistory(entries);

    test('shows live swaps history has not caught up with', () async {
      final bloc = SwapActivityBloc(
        history: historyOf(const []),
        registry: registry,
      )..add(const SwapActivityStarted());
      await pumpEventQueue();

      await registry.start(quoteOf());
      await pumpEventQueue();

      expect(bloc.state.entries, hasLength(1));
      expect(bloc.state.status, SwapActivityStatus.ready);
      await bloc.close();
    });

    test('a swap that finishes moves out of Active', () async {
      final bloc = SwapActivityBloc(
        history: historyOf(const []),
        registry: registry,
      )..add(const SwapActivityStarted());
      final started = await registry.start(quoteOf());
      await pumpEventQueue();
      expect(bloc.state.entries, hasLength(1));

      routed.lastStarted!.push(
        snapshotOf(id: started.id, outcome: completed()),
      );
      await pumpEventQueue();

      expect(bloc.state.entries, isEmpty);
      await bloc.close();
    });

    test('an unreadable history is an error, not an empty list', () async {
      final bloc = SwapActivityBloc(
        history: _FakeHistory(const [], failAll: true),
        registry: registry,
      )..add(const SwapActivityStarted());
      await pumpEventQueue();

      expect(bloc.state.status, SwapActivityStatus.error);
      await bloc.close();
    });
  });
}

class _FakeHistory implements SwapHistoryRepository {
  _FakeHistory(this.entries, {this.failAll = false});

  final List<SwapExecutionSnapshot> entries;
  final bool failAll;

  @override
  Future<SwapActivityPage> load({
    required SwapActivityFilter filter,
    int limit = 25,
  }) async => SwapActivityPage(
    entries: [
      for (final entry in entries)
        if (SwapHistoryRepository.matches(entry, filter)) entry,
    ],
    failedSources: failAll ? SwapLiquiditySource.values.toSet() : const {},
    hasMore: false,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
