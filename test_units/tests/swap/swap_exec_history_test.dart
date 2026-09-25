import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the merged Activity list where one source cannot be read, what each
/// source is asked for, and the order swaps are listed in.
void main() {
  late _HistoryManager routed;
  late List<({int limit, int page})> atomicReads;
  var atomicFails = false;

  SwapHistoryRepository repo() => SwapHistoryRepository(
    routedSwaps: routed,
    atomicHistory: ({required int limit, required int page}) async {
      atomicReads.add((limit: limit, page: page));
      if (atomicFails) throw StateError('my_recent_swaps down');
      return AtomicSwapHistoryPage(
        swaps: [
          atomicSwapOf('a-1', ['Started', 'Finished']),
        ],
        hasMore: false,
      );
    },
    networks: () => execNetworks,
    resolveAsset: resolveTicker,
  );

  RoutedSwapProgress routedDone(String uuid) => progressOf(
    uuid: uuid,
    phase: RoutedSwapPhase.finished,
    receipt: RoutedSwapReceipt(
      outcome: RoutedSwapOutcome.completed,
      amount: d('1'),
      assetId: usdc,
    ),
  );

  setUp(() {
    routed = _HistoryManager();
    atomicReads = [];
    atomicFails = false;
  });

  test('an unreadable atomic history keeps the routed swaps, marked '
      'partial', () async {
    routed.terminal = [routedDone('r-1')];
    atomicFails = true;

    final page = await repo().load(filter: SwapActivityFilter.completed);

    expect(page.entries.map((e) => e.id), ['r-1']);
    expect(page.failedSources, {SwapLiquiditySource.atomic});
    expect(page.isPartial, isTrue);
  });

  test('asks each source for the same number of its newest swaps', () async {
    await repo().load(filter: SwapActivityFilter.attention, limit: 7);

    expect(routed.requests.single, (
      limit: 7,
      filter: RoutedSwapHistoryFilter.terminal,
    ));
    expect(atomicReads.single, (limit: 7, page: 1));
  });

  test('a page equals another with the same entries and gaps', () {
    SwapActivityPage page({bool more = false}) => SwapActivityPage(
      entries: [snapshotOf(id: 'x')],
      failedSources: const {SwapLiquiditySource.routed},
      hasMore: more,
    );

    expect(page(), page());
    expect(page(), isNot(page(more: true)));
  });

  group('newest first', () {
    SwapExecutionSnapshot at(String id, [DateTime? createdAt]) =>
        snapshotOf(id: id, createdAt: createdAt);

    test('orders dated swaps by start time, then by id', () {
      final list = [
        at('b', DateTime(2026, 9, 1)),
        at('c', DateTime(2026, 9, 2)),
        at('a', DateTime(2026, 9, 1)),
      ]..sort(SwapHistoryRepository.byNewest);
      expect(list.map((s) => s.id), ['c', 'a', 'b']);
    });

    test('puts a swap without a start time first, as just started', () {
      final list = [at('dated', DateTime(2026, 9, 1)), at('z'), at('y')]
        ..sort(SwapHistoryRepository.byNewest);
      expect(list.map((s) => s.id), ['y', 'z', 'dated']);
    });
  });
}

/// Routed history with a terminal page, recording what was asked for.
class _HistoryManager implements RoutedSwapManager {
  List<RoutedSwapProgress> terminal = const [];
  final List<({int limit, RoutedSwapHistoryFilter? filter})> requests = [];

  @override
  Future<RoutedSwapHistoryPage> history({
    int pageNumber = 1,
    int limit = 20,
    RoutedSwapHistoryFilter? filter,
    AssetId? from,
    AssetId? to,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async {
    requests.add((limit: limit, filter: filter));
    return RoutedSwapHistoryPage(
      entries: terminal,
      total: terminal.length,
      pageNumber: 1,
      totalPages: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
