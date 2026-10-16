import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/analytics/events/transaction_events.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/shared/swap/swap_analytics.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_test_fixtures.dart';

/// Covers what the unified swap reports on the existing swap events: route
/// and outcome categories, steps and duration, for swaps run this session —
/// never an address, a hash or a raw payload.
void main() {
  final start = DateTime.utc(2026, 9, 24, 12);
  late _Executor routed;
  late _Executor atomic;
  late List<SwapExecutionRef> inFlight;
  late SwapExecutionRegistry registry;
  late List<AnalyticsEventData> events;
  late String walletType;
  late SwapAnalyticsReporter reporter;

  setUp(() {
    routed = _Executor(SwapLiquiditySource.routed);
    atomic = _Executor(SwapLiquiditySource.atomic);
    inFlight = [];
    registry = SwapExecutionRegistry(
      executors: [routed, atomic],
      inFlight: () async => inFlight,
    );
    events = [];
    walletType = 'hd';
    reporter = SwapAnalyticsReporter(
      registry: registry,
      log: events.add,
      walletType: () => walletType,
    );
  });

  tearDown(() async {
    await reporter.dispose();
    await registry.dispose();
  });

  /// Starts [snapshot] as a new swap and lets its events arrive.
  Future<FakeHandle> begin(SwapExecutionSnapshot snapshot) async {
    final executor = snapshot.source == SwapLiquiditySource.atomic
        ? atomic
        : routed;
    executor.next = snapshot;
    await registry.start(quoteOf(source: snapshot.source));
    await pumpEventQueue();
    return executor.last!;
  }

  Future<void> finish(FakeHandle handle, SwapExecutionSnapshot snapshot) async {
    handle.push(snapshot);
    await pumpEventQueue();
  }

  group('a swap started here', () {
    test('reports its pair, networks, route and steps', () async {
      await begin(
        _snapshot(
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          from: btc,
          to: eth,
          stageCount: 4,
        ),
      );

      expect(events.single.name, 'swap_initiated');
      expect(events.single.parameters, {
        'asset': 'BTC',
        'secondary_asset': 'ETH',
        'network': 'Native',
        'secondary_network': 'Ethereum',
        'hd_type': 'hd',
        'route_category': 'atomic',
        'stage_count': 4,
      });
    });

    test('a route without steps reports no step count', () async {
      await begin(
        _snapshot(routeKind: SwapRouteKind.crossChain, stageCount: 0),
      );

      expect(events.single.parameters['route_category'], 'cross_chain');
      expect(events.single.parameters, isNot(contains('stage_count')));
    });

    test('assets the wallet cannot map report an unknown network', () async {
      await begin(_snapshot(unmapped: true));

      expect(events.single.parameters['network'], 'unknown');
      expect(events.single.parameters['secondary_network'], 'unknown');
      expect(events.single.parameters['asset'], 'SOLD');
    });
  });

  group('how it ends', () {
    test(
      'a completed swap reports what it sold, its gas and its time',
      () async {
        final handle = await begin(_snapshot(createdAt: start));
        walletType = 'iguana';

        await finish(
          handle,
          _snapshot(
            outcome: completed(),
            createdAt: start,
            updatedAt: start.add(const Duration(seconds: 95)),
            finishedAt: start.add(const Duration(seconds: 90)),
            gas: [
              SwapGasSpent(ticker: 'ETH', amount: d('0.0004')),
              SwapGasSpent(ticker: 'ETH', amount: d('0.0001')),
            ],
          ),
        );

        expect(events.map((e) => e.name), ['swap_initiated', 'swap_success']);
        expect(events.first.parameters['hd_type'], 'hd');
        expect(events.last.parameters, {
          'asset': 'ETH',
          'secondary_asset': 'USDC-ERC20',
          'network': 'Ethereum',
          'secondary_network': 'Ethereum',
          'amount': 1.0,
          'fee': 0.0005,
          'hd_type': 'iguana',
          'duration_ms': 90000,
          'route_category': 'same_chain',
          'stage_count': 3,
        });
      },
    );

    test('gas in several coins does not add up, so it reports none', () async {
      final handle = await begin(_snapshot());

      await finish(
        handle,
        _snapshot(
          outcome: completed(),
          sell: null,
          gas: [
            SwapGasSpent(ticker: 'ETH', amount: d('0.0004')),
            SwapGasSpent(ticker: 'BNB', amount: d('0.001')),
          ],
        ),
      );

      expect(events.last.parameters['fee'], 0.0);
      expect(events.last.parameters['amount'], 0.0);
    });

    test('without a finish time the last update ends it', () async {
      final handle = await begin(_snapshot(createdAt: start));

      await finish(
        handle,
        _snapshot(
          outcome: completed(),
          createdAt: start,
          updatedAt: start.add(const Duration(seconds: 30)),
        ),
      );

      expect(events.last.parameters['duration_ms'], 30000);
      expect(events.last.parameters['fee'], 0.0);
    });

    test('an unknown start leaves the duration out', () async {
      final handle = await begin(_snapshot());

      await finish(handle, _snapshot(outcome: completed(), finishedAt: start));

      expect(events.last.parameters, isNot(contains('duration_ms')));
    });

    test('a failed swap reports its stage, reason and outcome', () async {
      final handle = await begin(_snapshot(createdAt: start));

      await finish(
        handle,
        _snapshot(
          outcome: failed(SwapFailureReason.insufficientBalance),
          createdAt: start,
          finishedAt: start.add(const Duration(seconds: 12)),
        ),
      );

      expect(events.last.name, 'swap_failure');
      expect(events.last.parameters, {
        'asset': 'ETH',
        'secondary_asset': 'USDC-ERC20',
        'network': 'Ethereum',
        'secondary_network': 'Ethereum',
        'failure_reason': 'stage:routed_execution|reason:insufficient_funds',
        'hd_type': 'hd',
        'duration_ms': 12000,
        'route_category': 'same_chain',
        'outcome_category': 'failed',
        'stage_count': 3,
      });
    });

    test('a refund reports its own outcome, with no reason', () async {
      final handle = await begin(_snapshot(source: SwapLiquiditySource.atomic));

      await finish(
        handle,
        _snapshot(
          source: SwapLiquiditySource.atomic,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
        ),
      );

      expect(
        events.last.parameters['failure_reason'],
        'stage:atomic_execution',
      );
      expect(events.last.parameters['outcome_category'], 'refunded');
    });

    test('a failure names why it failed', () async {
      final handle = await begin(_snapshot());

      await finish(
        handle,
        _snapshot(outcome: failed(SwapFailureReason.priceMoved)),
      );

      expect(
        events.last.parameters['failure_reason'],
        'stage:routed_execution|reason:price_moved',
      );
    });

    test('a swap that says it finished twice is reported once', () async {
      final handle = await begin(_snapshot());

      await finish(handle, _snapshot(outcome: completed()));
      await finish(handle, _snapshot(outcome: completed(amount: '3002')));

      expect(events.map((e) => e.name), ['swap_initiated', 'swap_success']);
    });
  });

  group('swaps not started here', () {
    test('an old swap opened again is never reported', () async {
      atomic.resumable['old'] = FakeHandle(
        _snapshot(
          id: 'old',
          source: SwapLiquiditySource.atomic,
          outcome: completed(),
        ),
      );
      inFlight = [(id: 'old', source: SwapLiquiditySource.atomic)];

      await registry.resumeInFlight();
      await pumpEventQueue();

      expect(registry.snapshotOf('old'), isNotNull);
      expect(events, isEmpty);
    });

    test('a swap resumed while running reports how it ends only', () async {
      final handle = FakeHandle(_snapshot(id: 'resumed'));
      routed.resumable['resumed'] = handle;
      inFlight = [(id: 'resumed', source: SwapLiquiditySource.routed)];
      await registry.resumeInFlight();
      await pumpEventQueue();

      await finish(handle, _snapshot(id: 'resumed', outcome: completed()));

      expect(events.map((e) => e.name), ['swap_success']);
    });
  });

  test('after dispose, nothing is reported', () async {
    await reporter.dispose();

    await begin(_snapshot());

    expect(events, isEmpty);
  });

  test('every route, outcome and failure reason has an analytics name', () {
    expect(SwapRouteKind.values.map(_routeName), [
      'atomic',
      'same_chain',
      'cross_chain',
    ]);
    expect(SwapOutcomeKind.values.map(SwapAnalyticsReporter.outcomeCategory), [
      'completed',
      'partial_below_minimum',
      'partial_other_token',
      'refunded',
      'cancelled',
      'no_match',
      'failed',
    ]);
    expect(
      SwapFailureReason.values.map(SwapAnalyticsReporter.failureCategory),
      [
        'price_moved',
        'insufficient_funds',
        'approval_failed',
        'reverted',
        'not_confirmed',
        'wallet_rejected',
        'route_failed',
        'safety_check',
        'quote_unavailable',
        'restarted',
        'exchange_failed',
        'internal',
        'unknown',
      ],
    );
  });

  test('legacy swap events leave the unified-flow fields out', () {
    const initiated = SwapInitiatedEventData(
      asset: 'KMD',
      secondaryAsset: 'BTC',
      network: 'utxo',
      secondaryNetwork: 'utxo',
      hdType: 'iguana',
    );
    const succeeded = SwapSucceededEventData(
      asset: 'KMD',
      secondaryAsset: 'BTC',
      network: 'utxo',
      secondaryNetwork: 'utxo',
      amount: 1,
      fee: 0,
      hdType: 'iguana',
    );
    const failure = SwapFailedEventData(
      asset: 'KMD',
      secondaryAsset: 'BTC',
      network: 'utxo',
      secondaryNetwork: 'utxo',
      failureStage: 'matching',
      hdType: 'iguana',
    );

    for (final event in [initiated, succeeded, failure]) {
      expect(
        event.parameters.keys,
        isNot(anyOf(contains('route_category'), contains('stage_count'))),
      );
    }
    expect(failure.parameters, isNot(contains('outcome_category')));
  });
}

String _routeName(SwapRouteKind kind) =>
    SwapAnalyticsReporter.routeCategory(_snapshot(routeKind: kind));

SwapExecutionSnapshot _snapshot({
  String id = 'swap-1',
  SwapLiquiditySource source = SwapLiquiditySource.routed,
  SwapRouteKind routeKind = SwapRouteKind.sameChain,
  AssetId? from,
  AssetId? to,
  bool unmapped = false,
  int stageCount = 3,
  SwapExecutionOutcome? outcome,
  String? sell = '1',
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? finishedAt,
  List<SwapGasSpent> gas = const [],
}) {
  final sold = unmapped ? null : from ?? eth;
  final bought = unmapped ? null : to ?? usdc;
  return SwapExecutionSnapshot(
    id: id,
    source: source,
    routeKind: routeKind,
    from: sold,
    fromTicker: sold?.id ?? 'SOLD',
    to: bought,
    toTicker: bought?.id ?? 'BOUGHT',
    sellAmount: sell == null ? null : d(sell),
    stage: outcome == null ? SwapProgressStage.confirming : null,
    outcome: outcome,
    fundsMovement: SwapFundsMovement.sent,
    canCancel: false,
    stages: [
      for (var i = 0; i < stageCount; i++)
        const SwapRouteStage(kind: SwapRouteStageKind.send),
    ],
    createdAt: createdAt,
    updatedAt: updatedAt,
    finishedAt: finishedAt,
    evidence: SwapEvidence(executionId: id, gasSpent: gas),
  );
}

/// Starts each swap from [next], and resumes the handles in [resumable].
class _Executor implements SwapExecutor {
  _Executor(this.source);

  @override
  final SwapLiquiditySource source;
  final Map<String, FakeHandle> resumable = {};
  SwapExecutionSnapshot? next;
  FakeHandle? last;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async =>
      last = FakeHandle(next!);

  @override
  Future<SwapExecutionHandle?> resume(String id) async => resumable[id];
}
