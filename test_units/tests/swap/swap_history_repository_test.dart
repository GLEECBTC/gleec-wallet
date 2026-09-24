import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers merging two swap histories KDF keeps entirely apart.
void main() {
  AssetId? resolve(String ticker) => switch (ticker) {
    'ETH' => eth,
    'USDC-ERC20' => usdc,
    'BTC' => btc,
    'GLEEC' => gleec,
    _ => null,
  };

  RoutedSwapProgress routed({
    required String uuid,
    RoutedSwapPhase phase = RoutedSwapPhase.finished,
    rpc.RoutedSwapOutcome? outcome,
    RoutedSwapFailure? failure,
    DateTime? createdAt,
  }) => RoutedSwapProgress(
    uuid: uuid,
    phase: phase,
    canCancel: false,
    failure: failure,
    createdAt: createdAt,
    requested: RoutedSwapRequest(
      fromTicker: 'ETH',
      toTicker: 'USDC-ERC20',
      from: eth,
      to: usdc,
      amount: Decimal.one,
    ),
    receipt: outcome == null
        ? null
        : RoutedSwapReceipt(
            outcome: outcome,
            amount: Decimal.parse('10'),
            assetId: usdc,
          ),
  );

  SwapHistoryRepository repoOf({
    _FakeRouted? routedSwaps,
    List<Swap> atomic = const [],
    bool atomicFails = false,
    bool atomicHasMore = false,
  }) => SwapHistoryRepository(
    routedSwaps: routedSwaps ?? _FakeRouted(),
    atomicHistory: ({required int limit, required int page}) async {
      if (atomicFails) throw StateError('my_recent_swaps down');
      return AtomicSwapHistoryPage(swaps: atomic, hasMore: atomicHasMore);
    },
    networks: () => SwapNetworks([eth, usdc, btc, gleec]),
    resolveAsset: resolve,
  );

  test('merges both sources, newest first', () async {
    final repo = repoOf(
      routedSwaps: _FakeRouted(
        historyEntries: [
          routed(
            uuid: 'r1',
            outcome: rpc.RoutedSwapOutcome.completed,
            createdAt: DateTime.utc(2026, 9, 2),
          ),
        ],
      ),
      atomic: [
        _atomicSwap('a1', [
          'Started',
          'Finished',
        ], at: DateTime.utc(2026, 9, 3)),
      ],
    );

    final page = await repo.load(filter: SwapActivityFilter.completed);

    expect(page.entries.map((e) => e.id), ['a1', 'r1']);
    expect(page.isPartial, isFalse);
  });

  test(
    'keeps the other source when one fails, and says the list is partial',
    () async {
      final repo = repoOf(
        routedSwaps: _FakeRouted(throwOnHistory: true),
        atomic: [
          _atomicSwap('a1', ['Started', 'Finished'], at: DateTime.utc(2026)),
        ],
      );

      final page = await repo.load(filter: SwapActivityFilter.completed);

      expect(page.entries.map((e) => e.id), ['a1']);
      expect(page.failedSources, {SwapLiquiditySource.routed});
    },
  );

  test('Active reads routed swaps from the in-flight list', () async {
    final routedSwaps = _FakeRouted(
      inFlightEntries: [
        routed(uuid: 'r-live', phase: RoutedSwapPhase.bridging),
      ],
    );
    final repo = repoOf(
      routedSwaps: routedSwaps,
      atomic: [
        _atomicSwap('a-live', ['Started', 'Negotiated', 'TakerFeeSent']),
      ],
    );

    final page = await repo.load(filter: SwapActivityFilter.active);

    expect(page.entries.map((e) => e.id), containsAll(['r-live', 'a-live']));
    expect(routedSwaps.historyCalls, 0);
  });

  test('puts a failure after funds moved under Needs attention', () async {
    final repo = repoOf(
      atomic: [
        _atomicSwap('a-failed', [
          'Started',
          'Negotiated',
          'TakerFeeSent',
          'TakerPaymentSent',
          'TakerPaymentWaitForSpendFailed',
          'Finished',
        ]),
        _atomicSwap('a-ok', ['Started', 'Finished']),
      ],
    );

    final attention = await repo.load(filter: SwapActivityFilter.attention);
    final done = await repo.load(filter: SwapActivityFilter.completed);

    expect(attention.entries.map((e) => e.id), ['a-failed']);
    expect(done.entries.map((e) => e.id), ['a-ok']);
  });

  test('a refund is an ordinary completion, not an alarm', () {
    final refunded = snapshotOf(
      outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
    );
    expect(
      SwapHistoryRepository.matches(refunded, SwapActivityFilter.completed),
      isTrue,
    );
  });

  test('reports older swaps when either source has more', () async {
    final repo = repoOf(
      routedSwaps: _FakeRouted(hasMore: true),
      atomic: const [],
    );
    final page = await repo.load(filter: SwapActivityFilter.completed);
    expect(page.hasMore, isTrue);
  });

  group('atomic mapping', () {
    final networks = SwapNetworks([eth, usdc, btc, gleec]);

    test('a finished swap without error events completed', () {
      final snapshot = atomicFromSwap(
        _atomicSwap('a', ['Started', 'Negotiated', 'Finished']),
        networks,
        resolve,
      );
      expect(snapshot.outcome!.kind, SwapOutcomeKind.completed);
      expect(snapshot.isSuccess, isTrue);
    });

    test('a failure before the payment left is safe to retry', () {
      final snapshot = atomicFromSwap(
        _atomicSwap('a', ['Started', 'NegotiateFailed', 'Finished']),
        networks,
        resolve,
      );
      expect(snapshot.outcome!.kind, SwapOutcomeKind.failed);
      expect(snapshot.fundsMovement, SwapFundsMovement.none);
      expect(snapshot.needsAttention, isFalse);
    });

    test('a refund is recognised as a refund', () {
      final snapshot = atomicFromSwap(
        _atomicSwap('a', [
          'Started',
          'TakerFeeSent',
          'TakerPaymentSent',
          'TakerPaymentWaitForSpendFailed',
          'TakerPaymentRefundStarted',
          'TakerPaymentRefunded',
          'Finished',
        ]),
        networks,
        resolve,
      );
      expect(snapshot.outcome!.kind, SwapOutcomeKind.refunded);
    });

    test('a failure after the payment left is never "nothing moved"', () {
      final snapshot = atomicFromSwap(
        _atomicSwap('a', [
          'Started',
          'TakerFeeSent',
          'TakerPaymentSent',
          'TakerPaymentWaitForSpendFailed',
          'Finished',
        ]),
        networks,
        resolve,
      );
      expect(snapshot.fundsMovement, SwapFundsMovement.uncertain);
      expect(snapshot.needsAttention, isTrue);
    });
  });
}

SwapExecutionSnapshot atomicFromSwap(
  Swap swap,
  SwapNetworks networks,
  AssetId? Function(String) resolve,
) => atomicSnapshotFromSwap(swap, networks: networks, resolveAsset: resolve);

const _takerSuccess = [
  'Started',
  'Negotiated',
  'TakerFeeSent',
  'TakerPaymentInstructionsReceived',
  'MakerPaymentReceived',
  'MakerPaymentWaitConfirmStarted',
  'MakerPaymentValidatedAndConfirmed',
  'TakerPaymentSent',
  'TakerPaymentSpent',
  'MakerPaymentSpent',
  'Finished',
];

const _takerErrors = [
  'StartFailed',
  'NegotiateFailed',
  'TakerFeeSendFailed',
  'MakerPaymentValidateFailed',
  'MakerPaymentWaitConfirmFailed',
  'TakerPaymentTransactionFailed',
  'TakerPaymentWaitConfirmFailed',
  'TakerPaymentDataSendFailed',
  'TakerPaymentWaitForSpendFailed',
  'MakerPaymentSpendFailed',
  'TakerPaymentWaitRefundStarted',
  'TakerPaymentRefundStarted',
  'TakerPaymentRefunded',
  'TakerPaymentRefundFailed',
  'TakerPaymentRefundFinished',
];

Swap _atomicSwap(String uuid, List<String> events, {DateTime? at}) {
  final start = (at ?? DateTime.utc(2026, 9)).millisecondsSinceEpoch;
  return Swap.fromJson({
    'type': 'Taker',
    'uuid': uuid,
    'my_order_uuid': 'order-$uuid',
    'events': [
      for (final (index, type) in events.indexed)
        {
          'timestamp': start + index * 1000,
          'event': {'type': type},
        },
    ],
    'maker_amount': '3000',
    'maker_coin': 'USDC-ERC20',
    'taker_amount': '1',
    'taker_coin': 'ETH',
    'success_events': _takerSuccess,
    'error_events': _takerErrors,
  });
}

class _FakeRouted implements RoutedSwapManager {
  _FakeRouted({
    this.historyEntries = const [],
    this.inFlightEntries = const [],
    this.throwOnHistory = false,
    this.hasMore = false,
  });

  final List<RoutedSwapProgress> historyEntries;
  final List<RoutedSwapProgress> inFlightEntries;
  final bool throwOnHistory;
  final bool hasMore;
  int historyCalls = 0;

  @override
  Future<RoutedSwapHistoryPage> history({
    int pageNumber = 1,
    int limit = 20,
    rpc.RoutedSwapHistoryFilter? filter,
    AssetId? from,
    AssetId? to,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async {
    historyCalls++;
    if (throwOnHistory) throw StateError('history down');
    return RoutedSwapHistoryPage(
      entries: historyEntries,
      total: historyEntries.length,
      pageNumber: pageNumber,
      totalPages: hasMore ? pageNumber + 1 : pageNumber,
    );
  }

  @override
  Future<List<RoutedSwapProgress>> inFlight({int pageSize = 50}) async {
    if (throwOnHistory) throw StateError('history down');
    return inFlightEntries;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
