import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

/// Covers merging two swap histories that KDF keeps entirely apart.
void main() {
  RoutedSwapProgress routed({
    required String uuid,
    RoutedSwapPhase phase = RoutedSwapPhase.finished,
    rpc.RoutedSwapOutcome? outcome,
    RoutedSwapFailure? failure,
  }) => RoutedSwapProgress(
    uuid: uuid,
    phase: phase,
    canCancel: false,
    failure: failure,
    receipt: outcome == null
        ? null
        : RoutedSwapReceipt(outcome: outcome, amount: Decimal.parse('10')),
  );

  SwapHistoryEntry atomicEntry(String id, DateTime at) => SwapHistoryEntry(
    id: id,
    source: SwapLiquiditySource.atomic,
    isInFlight: false,
    updatedAt: at,
  );

  test('merges both sources into one list', () async {
    final repo = SwapHistoryRepository(
      routedSwaps: _FakeRouted(history_: [routed(uuid: 'r1')]),
      atomicHistory: ({int limit = 20}) async => [
        atomicEntry('a1', DateTime(2020)),
      ],
    );

    final page = await repo.recent();

    expect(page.entries.map((e) => e.id), containsAll(['r1', 'a1']));
    expect(page.isPartial, isFalse);
  });

  test(
    'keeps one source when the other fails, and says it is partial',
    () async {
      // A routed-history outage must not blank years of atomic swaps, and an
      // empty routed section must be distinguishable from "we could not check".
      final repo = SwapHistoryRepository(
        routedSwaps: _FakeRouted(throwOnHistory: true),
        atomicHistory: ({int limit = 20}) async => [
          atomicEntry('a1', DateTime(2020)),
        ],
      );

      final page = await repo.recent();

      expect(page.entries.map((e) => e.id), ['a1']);
      expect(page.isPartial, isTrue);
      expect(page.failedSources, {SwapLiquiditySource.routed});
    },
  );

  test('flags a refund as needing attention', () async {
    final repo = SwapHistoryRepository(
      routedSwaps: _FakeRouted(
        history_: [routed(uuid: 'r1', outcome: rpc.RoutedSwapOutcome.refunded)],
      ),
      atomicHistory: ({int limit = 20}) async => const [],
    );

    final page = await repo.recent();
    final entry = page.entries.single;

    // A refund is terminal but is not the swap the user asked for. Unmarked,
    // it sits in the list looking like an ordinary completion.
    expect(entry.needsAttention, isTrue);
    expect(entry.statusLabel, 'Refunded');
  });

  test('does not flag an ordinary completion', () async {
    final repo = SwapHistoryRepository(
      routedSwaps: _FakeRouted(
        history_: [
          routed(uuid: 'r1', outcome: rpc.RoutedSwapOutcome.completed),
        ],
      ),
      atomicHistory: ({int limit = 20}) async => const [],
    );

    final entry = (await repo.recent()).entries.single;

    expect(entry.needsAttention, isFalse);
    expect(entry.statusLabel, 'Completed');
  });

  test('does not nag about a swap the user cancelled themselves', () async {
    final repo = SwapHistoryRepository(
      routedSwaps: _FakeRouted(
        history_: [
          routed(
            uuid: 'r1',
            phase: RoutedSwapPhase.failed,
            failure: const RoutedSwapFailure(
              kind: RoutedSwapFailureKind.cancelled,
              message: 'Cancelled',
              fundsUntouched: true,
            ),
          ),
        ],
      ),
      atomicHistory: ({int limit = 20}) async => const [],
    );

    final entry = (await repo.recent()).entries.single;

    expect(entry.needsAttention, isFalse);
  });

  test('reports in-flight routed swaps for cold start', () async {
    final repo = SwapHistoryRepository(
      routedSwaps: _FakeRouted(
        inFlightSwaps: [routed(uuid: 'r1', phase: RoutedSwapPhase.bridging)],
      ),
      atomicHistory: ({int limit = 20}) async => const [],
    );

    final live = await repo.inFlight();

    expect(live.single.id, 'r1');
    expect(live.single.isInFlight, isTrue);
  });

  test(
    'an in-flight lookup failure yields an empty list, not a crash',
    () async {
      // This runs on app start. Throwing here would break the launch path over
      // a history call that is only ever an optimisation.
      final repo = SwapHistoryRepository(
        routedSwaps: _FakeRouted(throwOnInFlight: true),
        atomicHistory: ({int limit = 20}) async => const [],
      );

      expect(await repo.inFlight(), isEmpty);
    },
  );
}

class _FakeRouted implements RoutedSwapManager {
  _FakeRouted({
    this.history_ = const [],
    this.inFlightSwaps = const [],
    this.throwOnHistory = false,
    this.throwOnInFlight = false,
  });

  final List<RoutedSwapProgress> history_;
  final List<RoutedSwapProgress> inFlightSwaps;
  final bool throwOnHistory;
  final bool throwOnInFlight;

  @override
  Future<List<RoutedSwapProgress>> history({
    int limit = 20,
    int pageNumber = 1,
  }) async {
    if (throwOnHistory) throw StateError('history down');
    return history_;
  }

  @override
  Future<List<RoutedSwapProgress>> inFlight({int limit = 20}) async {
    if (throwOnInFlight) throw StateError('history down');
    return inFlightSwaps;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
