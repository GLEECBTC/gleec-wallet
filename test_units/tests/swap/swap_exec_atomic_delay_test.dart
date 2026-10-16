import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';

/// Covers when an atomic swap's status reads as delayed.
void main() {
  const confirming = [
    'Started',
    'Negotiated',
    'TakerFeeSent',
    'MakerPaymentReceived',
    'MakerPaymentWaitConfirmStarted',
  ];
  const paid = [
    ...confirming,
    'MakerPaymentValidatedAndConfirmed',
    'TakerPaymentSent',
  ];
  final t0 = AtomicRig.startedAt;
  // Deadlines are read as local times, and DateTime == compares isUtc.
  final makerPaymentWait = t0.add(const Duration(minutes: 40)).toLocal();
  final takerPaymentLock = t0.add(const Duration(hours: 2)).toLocal();
  int seconds(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;
  Map<String, Map<String, Object?>> deadlines({
    Duration shift = Duration.zero,
  }) => {
    'Started': {
      'maker_payment_wait': seconds(makerPaymentWait.add(shift)),
      'taker_payment_lock': seconds(takerPaymentLock.add(shift)),
    },
  };
  final noAnswer = TimeoutException('no answer from KDF');

  group('when KDF stops answering', () {
    test('a matched swap is delayed from the first unanswered poll, once '
        'three in a row go unanswered', () async {
      final rig = await onFakeClock((rig) {
        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', paid);
        rig.start();
        rig.firstPoll();
        rig.dex.statusError = noAnswer;
        rig.polls(2);
        expect(rig.latest.delayedSince, isNull);

        rig.polls();
        expect(rig.latest.delayedSince, t0.add(AtomicRig.pollInterval));
        expect(rig.latest.stage, SwapProgressStage.exchanging);
        expect(rig.latest.fundsMovement, SwapFundsMovement.sent);
        expect(rig.latest.isTerminal, isFalse);

        rig.dex.statusError = null;
        rig.polls();
      });

      expect(rig.seen.map((s) => s.delayedSince), [
        null,
        null,
        t0.add(AtomicRig.pollInterval),
        null,
      ]);
    });

    test(
      'an unmatched order is delayed too, and can still be cancelled',
      () async {
        await onFakeClock((rig) {
          rig.orders.statusError = noAnswer;
          rig.start();
          rig.firstPoll();
          rig.polls(2);
          expect(rig.latest.delayedSince, t0);
          expect(rig.latest.stage, SwapProgressStage.matching);
          expect(rig.latest.canCancel, isTrue);

          rig.orders.statusError = null;
          rig.orders.takers['a-1'] = TakerOrderCancellationReason.none;
          rig.polls();
          expect(rig.latest.delayedSince, isNull);
          expect(rig.latest.canCancel, isTrue);
        });
      },
    );

    test('an answer between unanswered polls starts the count over', () async {
      await onFakeClock((rig) {
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.none;
        rig.start();
        rig.orders.statusError = noAnswer;
        rig.firstPoll();
        rig.polls();
        rig.orders.statusError = null;
        rig.polls();
        rig.orders.statusError = noAnswer;
        rig.polls(2);
        expect(rig.latest.delayedSince, isNull);

        rig.polls();
        expect(rig.latest.delayedSince, t0.add(AtomicRig.pollInterval * 3));
      });
    });

    test('an answer that changes nothing still ends the delay', () async {
      await onFakeClock((rig) {
        rig.orders.statusError = noAnswer;
        rig.start();
        rig.firstPoll();
        rig.polls(2);
        expect(rig.latest.delayedSince, t0);

        rig.orders.statusError = null;
        rig.polls();
        expect(rig.latest.delayedSince, isNull);
        expect(rig.latest.stage, SwapProgressStage.matching);
      }, misses: 10);
    });

    test('a delay that ends with a fill reports only the fill', () async {
      final rig = await onFakeClock((rig) {
        rig.orders.statusError = noAnswer;
        rig.start();
        rig.firstPoll();
        rig.polls(2);
        rig.orders.statusError = null;
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.fulfilled;
        rig.polls();
      });

      expect(rig.seen.map((s) => (s.stage, s.delayedSince)), [
        (SwapProgressStage.matching, null),
        (SwapProgressStage.matching, t0),
        (SwapProgressStage.preparing, null),
      ]);
    });

    test('an order read that never returns counts as unanswered', () async {
      await onFakeClock((rig) {
        rig.orders.statusGate = Completer<void>();
        rig.start();
        rig.firstPoll();
        rig.async.elapse(const Duration(seconds: 50));
        expect(rig.latest.delayedSince, isNull);

        rig.async.elapse(const Duration(seconds: 1));
        expect(rig.latest.delayedSince, t0);
        expect(rig.latest.canCancel, isTrue);
      });
    });

    test('the number of unanswered polls is configurable', () async {
      await onFakeClock((rig) {
        rig.orders.statusError = noAnswer;
        rig.start();
        rig.firstPoll();
        expect(rig.latest.delayedSince, t0);
      }, delayedAfter: 1);
    });

    for (final (name, arrange) in <(String, void Function(AtomicRig))>[
      ('an order it no longer has, counting towards no match', (_) {}),
      (
        'an open order',
        (rig) => rig.orders.takers['a-1'] = TakerOrderCancellationReason.none,
      ),
      (
        'a filled order whose swap it has no row for yet',
        (rig) =>
            rig.orders.takers['a-1'] = TakerOrderCancellationReason.fulfilled,
      ),
      (
        'a filled order whose swap it has yet to log',
        (rig) {
          rig.orders.takers['a-1'] = TakerOrderCancellationReason.fulfilled;
          rig.dex.unrecorded.add('a-1');
        },
      ),
      ('a maker order under the id', (rig) => rig.orders.makers.add('a-1')),
    ]) {
      test('KDF answering about $name is no delay', () async {
        final rig = await onFakeClock((rig) {
          arrange(rig);
          rig.start();
          rig.firstPoll();
          rig.polls(5);
        }, misses: 10);

        expect(rig.latest.isTerminal, isFalse);
        expect(rig.seen.map((s) => s.delayedSince), everyElement(isNull));
      });
    }

    test('a swap KDF has yet to log proves the order matched, even when the '
        'order cannot be read', () async {
      await onFakeClock((rig) {
        rig.dex.unrecorded.add('a-1');
        rig.orders.statusError = noAnswer;
        rig.start();
        rig.firstPoll();
        rig.polls(5);

        expect(rig.latest.stage, SwapProgressStage.preparing);
        expect(rig.latest.canCancel, isFalse);
        expect(rig.latest.delayedSince, isNull);
      });
    });

    test('a matched swap KDF never logs is delayed five minutes on', () async {
      await onFakeClock((rig) {
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.fulfilled;
        rig.dex.unrecorded.add('a-1');
        rig.start();
        rig.firstPoll();
        rig.async.elapse(const Duration(minutes: 5));
        expect(rig.latest.delayedSince, isNull);

        rig.polls(3);
        expect(
          rig.latest.delayedSince,
          t0.add(const Duration(minutes: 5, seconds: 3)),
        );
        expect(rig.latest.stage, SwapProgressStage.preparing);

        rig.dex.unrecorded.clear();
        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', ['Started']);
        rig.polls();
        expect(rig.latest.delayedSince, isNull);
      });
    });

    test('a read that never returns counts as unanswered', () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', paid);
        rig.start();
        rig.firstPoll();
        rig.dex.statusGate = Completer<void>();
        rig.async.elapse(const Duration(seconds: 53));
        expect(rig.latest.delayedSince, isNull);

        rig.async.elapse(const Duration(seconds: 1));
        expect(rig.latest.delayedSince, t0.add(AtomicRig.pollInterval));
        expect(rig.latest.stage, SwapProgressStage.exchanging);

        rig.dex.statusGate!.complete();
        rig.dex.statusGate = null;
        rig.polls();
        expect(rig.latest.delayedSince, isNull);
      });
    });
  });

  group('when the log is past a deadline KDF wrote into it', () {
    test('a taker still waiting on the maker payment is delayed since '
        'maker_payment_wait, once KDF has had ten minutes to log it', () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-1'] = atomicSwapOf(
          'a-1',
          confirming,
          data: deadlines(),
        );
        rig.start();
        rig.firstPoll();
        rig.async.elapse(const Duration(minutes: 50));
        expect(rig.latest.delayedSince, isNull);

        rig.polls();
        expect(rig.latest.delayedSince, makerPaymentWait);
        expect(rig.latest.stage, SwapProgressStage.confirming);

        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', [
          ...confirming,
          'MakerPaymentValidatedAndConfirmed',
        ], data: deadlines());
        rig.polls();
        expect(rig.latest.delayedSince, isNull);
      });
    });

    test('a taker whose payment is still unspent is delayed since '
        'taker_payment_lock', () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', paid, data: deadlines());
        rig.start();
        rig.firstPoll();
        rig.async.elapse(const Duration(hours: 2, minutes: 10));
        expect(rig.latest.delayedSince, isNull);

        rig.polls();
        expect(rig.latest.delayedSince, takerPaymentLock);
        expect(rig.latest.fundsMovement, SwapFundsMovement.sent);
      });
    });

    test(
      'a swap picked up after a restart is delayed from the start',
      () async {
        await onFakeClock((rig) {
          const dayBefore = Duration(days: -1);
          rig.dex.swaps['a-9'] = atomicSwapOf(
            'a-9',
            paid,
            at: t0.add(dayBefore),
            data: deadlines(shift: dayBefore),
          );
          rig.resume('a-9');

          expect(rig.latest.delayedSince, takerPaymentLock.add(dayBefore));
        });
      },
    );

    test('reads failing later keep the earlier time', () async {
      final rig = await onFakeClock((rig) {
        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', paid, data: deadlines());
        rig.start();
        rig.firstPoll();
        rig.async.elapse(const Duration(hours: 3));
        rig.dex.statusError = noAnswer;
        rig.polls(5);
      });

      expect(rig.latest.delayedSince, takerPaymentLock);
      expect(rig.seen.map((s) => s.delayedSince), [
        null,
        null,
        takerPaymentLock,
      ]);
    });

    test('is judged only for a waiting taker whose log records it', () {
      final later = t0.add(const Duration(days: 30));
      DateTime? delayOf(List<String> events, {bool maker = false}) =>
          atomicSnapshotFromSwap(
            atomicSwapOf('a', events, maker: maker, data: deadlines()),
            networks: execNetworks,
            resolveAsset: resolveTicker,
            now: later,
          ).delayedSince;

      expect(delayOf(paid), takerPaymentLock);
      expect(
        atomicSnapshotFromSwap(
          atomicSwapOf('a', paid),
          networks: execNetworks,
          resolveAsset: resolveTicker,
          now: later,
        ).delayedSince,
        isNull,
        reason: 'no deadlines recorded',
      );
      for (final (name, events) in [
        ('its payment spent', [...paid, 'TakerPaymentSpent']),
        ('failed', [...confirming, 'MakerPaymentWaitConfirmFailed']),
        ('finished', [...paid, 'TakerPaymentSpent', 'Finished']),
      ]) {
        expect(delayOf(events), isNull, reason: name);
      }
      expect(
        delayOf([
          'Started',
          'Negotiated',
          'TakerFeeValidated',
          'MakerPaymentSent',
        ], maker: true),
        isNull,
        reason: 'a maker',
      );
    });
  });
}
