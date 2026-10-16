import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the times a swap's screen can show: when it started, when it
/// finished, and when an atomic swap's refund unlocks. The engine's own
/// record wins; this session's times stand in only where it has none.
void main() {
  group('atomic', () {
    test(
      'a placed order is dated from its placement until it matches',
      () async {
        await onFakeClock((rig) {
          rig.start();
          expect(rig.latest.stage, SwapProgressStage.matching);
          expect(rig.latest.createdAt, AtomicRig.startedAt);
        });
      },
    );

    test('an order that never matches is dated to when it gave up', () async {
      await onFakeClock((rig) {
        rig.start();
        rig
          ..firstPoll()
          ..polls(2);
        expect(rig.latest.outcome!.kind, SwapOutcomeKind.noMatch);
        expect(rig.latest.createdAt, AtomicRig.startedAt);
        expect(rig.latest.finishedAt, rig.now);
      });
    });

    test('once matched, the log dates the swap', () {
      final placed = DateTime.utc(2026, 8, 31);
      final snapshot = atomicSnapshotFromSwap(
        atomicSwapOf('a-1', ['Started', 'Negotiated']),
        networks: execNetworks,
        resolveAsset: resolveTicker,
        placedAt: placed,
      );
      expect(snapshot.createdAt, DateTime.utc(2026, 9).toLocal());
    });

    SwapExecutionSnapshot refunding({
      bool maker = false,
      Map<String, Object?> started = const {},
      List<String>? events,
    }) => atomicSnapshotFromSwap(
      atomicSwapOf(
        'a-1',
        events ??
            (maker
                ? [
                    'Started',
                    'Negotiated',
                    'TakerFeeValidated',
                    'MakerPaymentSent',
                    'TakerPaymentValidateFailed',
                    'MakerPaymentWaitRefundStarted',
                  ]
                : [
                    'Started',
                    'Negotiated',
                    'TakerFeeSent',
                    'MakerPaymentReceived',
                    'TakerPaymentSent',
                    'TakerPaymentWaitForSpendFailed',
                    'TakerPaymentWaitRefundStarted',
                  ]),
        maker: maker,
        data: {'Started': started},
      ),
      networks: execNetworks,
      resolveAsset: resolveTicker,
    );

    final lock = DateTime.utc(2026, 9, 1, 2, 10);
    final lockSeconds = lock.millisecondsSinceEpoch ~/ 1000;

    test("a taker's refund unlocks at its payment lock", () {
      final snapshot = refunding(started: {'taker_payment_lock': lockSeconds});
      expect(snapshot.stage, SwapProgressStage.refunding);
      expect(snapshot.refundUnlocksAt, lock.toLocal());
    });

    test("a maker's refund unlocks at the maker's payment lock", () {
      final snapshot = refunding(
        maker: true,
        started: {
          'maker_payment_lock': lockSeconds,
          'taker_payment_lock': lockSeconds + 3600,
        },
      );
      expect(snapshot.stage, SwapProgressStage.refunding);
      expect(snapshot.refundUnlocksAt, lock.toLocal());
    });

    test('no lock is shown outside a refund, or without one recorded', () {
      expect(
        refunding(
          started: {'taker_payment_lock': lockSeconds},
          events: ['Started', 'Negotiated', 'TakerFeeSent'],
        ).refundUnlocksAt,
        isNull,
      );
      expect(refunding().refundUnlocksAt, isNull);
      expect(
        refunding(
          started: {'taker_payment_lock': lockSeconds},
          events: [
            'Started',
            'TakerPaymentSent',
            'TakerPaymentWaitRefundStarted',
            'TakerPaymentRefunded',
            'Finished',
          ],
        ).refundUnlocksAt,
        isNull,
      );
    });

    test("a maker's payment lock is read, and written back only when "
        'known', () {
      final data = SwapEventData.fromJson({'maker_payment_lock': 1700000000});
      expect(data.makerPaymentLock, 1700000000);
      expect(data.toJson()['maker_payment_lock'], 1700000000);
      expect(
        SwapEventData.fromJson(
          const {},
        ).toJson().containsKey('maker_payment_lock'),
        isFalse,
      );
    });
  });

  group('routed', () {
    late FakeRoutedManager manager;
    late RoutedSwapExecutor executor;
    late DateTime now;

    setUp(() {
      manager = FakeRoutedManager();
      now = DateTime.utc(2026, 9, 30, 14, 2);
      executor = RoutedSwapExecutor(
        manager,
        networks: () => execNetworks,
        now: () => now,
      );
    });

    RoutedSwapProgress finished({DateTime? at, String uuid = 'r-1'}) =>
        RoutedSwapProgress(
          uuid: uuid,
          phase: RoutedSwapPhase.finished,
          canCancel: false,
          receipt: RoutedSwapReceipt(
            outcome: RoutedSwapOutcome.completed,
            amount: d('2990'),
            assetId: usdc,
          ),
          finishedAt: at,
        );

    test('a swap started here is dated from its start until the record '
        'is read', () async {
      final handle = await executor.start(quoteOf(payload: offerOf()));
      expect(handle.latest.createdAt, now);

      final recorded = DateTime.utc(2026, 9, 30, 14, 1);
      manager.live['r-1']!.push(
        progressOf(offer: offerOf()).copyWith(createdAt: recorded),
      );
      await pumpEventQueue();
      expect(handle.latest.createdAt, recorded);
    });

    test('a finish seen here is dated when it was seen', () async {
      final handle = await executor.start(quoteOf(payload: offerOf()));
      now = now.add(const Duration(minutes: 4));
      manager.live['r-1']!.push(finished());
      await pumpEventQueue();
      expect(handle.latest.finishedAt, now);
    });

    test("the record's finish time wins", () async {
      final handle = await executor.start(quoteOf(payload: offerOf()));
      final recorded = DateTime.utc(2026, 9, 30, 14, 5);
      manager.live['r-1']!.push(finished(at: recorded));
      await pumpEventQueue();
      expect(handle.latest.finishedAt, recorded);
    });

    test('a swap found already finished is never dated now', () async {
      manager.live['r-9'] = FakeRoutedHandle(finished(uuid: 'r-9'));
      final handle = await executor.resume('r-9');
      expect(handle!.latest.isTerminal, isTrue);
      expect(handle.latest.finishedAt, isNull);
      expect(handle.latest.createdAt, isNull);
    });
  });
}
