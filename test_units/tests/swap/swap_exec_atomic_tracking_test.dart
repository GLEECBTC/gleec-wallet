import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how the atomic executor follows a swap on its own: the taker order
/// until it matches or is gone, then the swap's event log until it ends.
void main() {
  const matched = ['Started', 'Negotiated'];
  const feePaid = [...matched, 'TakerFeeSent'];
  const makerPaid = [...feePaid, 'MakerPaymentReceived'];
  const paid = [...makerPaid, 'TakerPaymentSent'];
  const done = [...paid, 'MakerPaymentSpent', 'Finished'];

  Object stateOf(SwapExecutionSnapshot s) => s.outcome?.kind ?? s.stage!;

  test(
    'follows the order until it matches, then the swap to the end',
    () async {
      final rig = await onFakeClock((rig) {
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.none;
        rig.start();
        rig.firstPoll();

        for (final log in [matched, feePaid, makerPaid, paid, done]) {
          rig.dex.swaps['a-1'] = atomicSwapOf('a-1', log);
          rig.polls();
        }
      });

      expect(rig.seen.map(stateOf), [
        SwapProgressStage.matching,
        SwapProgressStage.preparing,
        SwapProgressStage.sending,
        SwapProgressStage.confirming,
        SwapProgressStage.exchanging,
        SwapOutcomeKind.completed,
      ]);
      expect(rig.seen.map((s) => s.fundsMovement), [
        SwapFundsMovement.none,
        SwapFundsMovement.none,
        SwapFundsMovement.feesOnly,
        SwapFundsMovement.feesOnly,
        SwapFundsMovement.sent,
        SwapFundsMovement.sent,
      ]);
      expect(rig.seen.skip(1).every((s) => !s.canCancel), isTrue);
      expect(rig.done, isTrue);
    },
  );

  test('stops reading once the swap has ended', () async {
    await onFakeClock((rig) {
      rig.dex.swaps['a-1'] = atomicSwapOf('a-1', done);
      rig.start();
      rig.firstPoll();
      final reads = rig.dex.statusCalls;
      rig.polls(5);

      expect(rig.latest.isSuccess, isTrue);
      expect(rig.dex.statusCalls, reads);
    });
  });

  test('an unchanged read is not reported again', () async {
    final rig = await onFakeClock((rig) {
      rig.dex.swaps['a-1'] = atomicSwapOf('a-1', feePaid);
      rig.start();
      rig.firstPoll();
      rig.polls(3);
    });

    expect(rig.seen.map(stateOf), [
      SwapProgressStage.matching,
      SwapProgressStage.sending,
    ]);
    expect(rig.dex.statusCalls, 4);
  });

  group('before a match', () {
    test('an order gone without a swap never matched, after the set number '
        'of misses', () async {
      final rig = await onFakeClock((rig) {
        rig.start();
        rig.firstPoll();
        rig.polls();
        expect(rig.latest.isTerminal, isFalse);

        rig.polls();
        expect(rig.latest.outcome!.kind, SwapOutcomeKind.noMatch);
        expect(rig.latest.fundsMovement, SwapFundsMovement.none);
        expect(rig.latest.needsAttention, isFalse);

        final reads = rig.orders.statusCalls;
        rig.polls(3);
        expect(rig.orders.statusCalls, reads);
      });
      expect(rig.done, isTrue);
    });

    test('the number of misses is configurable', () async {
      await onFakeClock((rig) {
        rig.start();
        rig.firstPoll();
        expect(rig.latest.outcome!.kind, SwapOutcomeKind.noMatch);
      }, misses: 1);
    });

    test('seeing the order again starts the count of misses over', () async {
      await onFakeClock((rig) {
        rig.start();
        rig.firstPoll();
        rig.polls();
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.none;
        rig.polls();
        rig.orders.takers.clear();
        rig.polls(2);
        expect(rig.latest.isTerminal, isFalse);

        rig.polls();
        expect(rig.latest.outcome!.kind, SwapOutcomeKind.noMatch);
      });
    });

    test('an order the engine timed out never matched', () async {
      await onFakeClock((rig) {
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.timedOut;
        rig.start();
        rig.firstPoll();

        expect(rig.latest.outcome!.kind, SwapOutcomeKind.noMatch);
        expect(rig.latest.stage, isNull);
        expect(rig.latest.canCancel, isFalse);
      });
    });

    test(
      'an order cancelled elsewhere ends as cancelled, nothing moved',
      () async {
        await onFakeClock((rig) {
          rig.orders.takers['a-1'] = TakerOrderCancellationReason.cancelled;
          rig.start();
          rig.firstPoll();

          expect(rig.latest.outcome!.kind, SwapOutcomeKind.cancelled);
          expect(rig.latest.fundsMovement, SwapFundsMovement.none);
        });
      },
    );

    test('an open order, or one handed on as a maker order, keeps '
        'matching and stays cancellable', () async {
      for (final reason in [
        TakerOrderCancellationReason.none,
        TakerOrderCancellationReason.toMaker,
      ]) {
        await onFakeClock((rig) {
          rig.orders.takers['a-1'] = reason;
          rig.start();
          rig.firstPoll();
          rig.polls(4);

          expect(
            rig.latest.stage,
            SwapProgressStage.matching,
            reason: '$reason',
          );
          expect(rig.latest.canCancel, isTrue, reason: '$reason');
          expect(rig.latest.isTerminal, isFalse, reason: '$reason');
        });
      }
    });

    test('a filled order is waited on, not offered for cancelling', () async {
      await onFakeClock((rig) {
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.fulfilled;
        rig.start();
        rig.firstPoll();

        expect(rig.latest.isTerminal, isFalse);
        expect(rig.latest.canCancel, isFalse);
      });
    });
  });

  test(
    'once matched, an unreadable swap is waited for, never written off',
    () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', paid);
        rig.start();
        rig.firstPoll();
        rig.dex.swaps.clear();
        rig.polls(5);

        expect(rig.latest.stage, SwapProgressStage.exchanging);
        expect(rig.latest.fundsMovement, SwapFundsMovement.sent);
        expect(rig.orders.statusCalls, 0);

        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', done);
        rig.polls();
        expect(rig.latest.isSuccess, isTrue);
      });
    },
  );

  group('closing', () {
    // Closing awaits a subscription cancel that completes through the real
    // event loop, so each test hands control to it between fake-clock turns.
    test(
      'stops reading and ends the updates, leaving the swap running',
      () async {
        final clock = FakeAsync();
        late AtomicRig rig;
        clock.run((async) {
          rig = AtomicRig(async)
            ..dex.swaps['a-1'] = atomicSwapOf('a-1', matched);
          rig.start();
          rig.firstPoll();
          unawaited(rig.handle!.close());
        });
        await pumpEventQueue();
        clock.run((async) {
          final reads = rig.dex.statusCalls;
          rig.polls(3);
          expect(rig.dex.statusCalls, reads);
        });
        await pumpEventQueue();

        expect(rig.done, isTrue);
        expect(rig.orders.cancelled, isEmpty);
      },
    );

    test('a read that lands after closing schedules no more', () async {
      final clock = FakeAsync();
      late AtomicRig rig;
      clock.run((async) {
        rig = AtomicRig(async)..start();
        rig.dex
          ..statusGate = Completer<void>()
          ..swaps['a-1'] = atomicSwapOf('a-1', feePaid);
        rig.firstPoll();
        unawaited(rig.handle!.close());
      });
      await pumpEventQueue();
      clock.run((async) {
        rig.dex.statusGate!.complete();
        rig.polls(2);
        expect(rig.dex.statusCalls, 1);
      });
    });
  });

  group('a swap picked up again after a restart', () {
    test('is described from its own record', () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-7'] = atomicSwapOf(
          'a-7',
          feePaid,
          sell: 'BTC',
          buy: 'GLEEC',
        );
        rig.resume('a-7');
        rig.firstPoll();

        expect(rig.latest.from, btc);
        expect(rig.latest.to, gleec);
        expect(rig.latest.sellAmount, d('1'));
        expect(rig.latest.expectedReceive, d('3000'));
        expect(rig.latest.stage, SwapProgressStage.sending);
      });
    });

    test(
      'starts from the record it was found by, not from "nothing moved"',
      () async {
        await onFakeClock((rig) {
          rig.dex.swaps['a-9'] = atomicSwapOf('a-9', paid);
          rig.resume('a-9');

          expect(rig.latest.fundsMovement, SwapFundsMovement.sent);
        });
      },
    );

    test(
      'is never written off as unmatched when its reads start failing',
      () async {
        await onFakeClock((rig) {
          rig.dex.swaps['a-9'] = atomicSwapOf('a-9', paid);
          rig.resume('a-9');
          rig.dex.swaps.clear();
          rig.firstPoll();
          rig.polls(5);

          expect(rig.latest.isTerminal, isFalse);
          expect(rig.latest.fundsMovement, isNot(SwapFundsMovement.none));
        });
      },
    );
  });
}
