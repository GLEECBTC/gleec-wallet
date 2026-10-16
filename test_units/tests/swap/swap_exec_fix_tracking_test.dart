import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';

import 'swap_exec_atomic_fakes.dart';

/// Covers what the atomic executor may conclude from a status read: a read
/// that failed proves nothing, a filled order has matched, and a record found
/// on re-attaching is where the swap stands.
void main() {
  group('before a match', () {
    test('an unreadable swap proves nothing, even beside KDF having no such '
        'order', () async {
      await onFakeClock((rig) {
        rig.dex.statusError = TextError(error: 'something went wrong');
        rig.start();
        rig.firstPoll();
        rig.polls(10);

        expect(rig.latest.isTerminal, isFalse);
        expect(rig.latest.stage, SwapProgressStage.matching);
        expect(rig.orders.statusCalls, 11);
      });
    });

    test('an unreadable order proves nothing, even beside KDF having no such '
        'swap', () async {
      await onFakeClock((rig) {
        rig.orders.statusError = TimeoutException('no answer from KDF');
        rig.start();
        rig.firstPoll();
        rig.polls(10);

        expect(rig.latest.isTerminal, isFalse);
        expect(rig.latest.canCancel, isTrue);
      });
    });

    test('a failed read between misses neither counts nor starts the count '
        'over', () async {
      await onFakeClock((rig) {
        rig.start();
        rig.firstPoll();
        rig.polls();
        rig.orders.statusError = TimeoutException('no answer from KDF');
        rig.polls(5);
        expect(rig.latest.isTerminal, isFalse);

        rig.orders.statusError = null;
        rig.polls();
        expect(rig.latest.outcome!.kind, SwapOutcomeKind.noMatch);
        expect(rig.latest.fundsMovement, SwapFundsMovement.none);
      });
    });

    test('a maker order under its id is neither a match nor a miss', () async {
      await onFakeClock((rig) {
        rig.orders.makers.add('a-1');
        rig.start();
        rig.firstPoll();
        rig.polls(5);

        expect(rig.latest.isTerminal, isFalse);
        expect(rig.latest.stage, SwapProgressStage.matching);
      });
    });
  });

  group('a filled order', () {
    test('has matched: nothing moved yet, and cancelling it is refused '
        'without asking the engine', () async {
      await onFakeClock((rig) {
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.fulfilled;
        rig.start();
        rig.firstPoll();
        Object? error;
        rig.handle!.cancel().catchError((Object e) => error = e);
        rig.async.flushMicrotasks();

        expect(rig.latest.stage, SwapProgressStage.preparing);
        expect(rig.latest.fundsMovement, SwapFundsMovement.none);
        expect(
          error,
          isA<SwapCancelRefusedException>().having(
            (e) => e.reason,
            'reason',
            SwapCancelRefusal.notSupported,
          ),
        );
        expect(rig.orders.cancelled, isEmpty);
      });
    });

    test('is followed into its swap, however long the record takes', () async {
      await onFakeClock((rig) {
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.fulfilled;
        rig.start();
        rig.firstPoll();
        rig.polls(10);

        expect(rig.latest.isTerminal, isFalse);
        expect(rig.orders.statusCalls, 1);

        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', [
          'Started',
          'Negotiated',
          'TakerFeeSent',
        ]);
        rig.polls();
        expect(rig.latest.stage, SwapProgressStage.sending);
      });
    });
  });

  test('a record found already ended is final: its feed ends and nothing '
      'more is read', () async {
    final rig = await onFakeClock((rig) {
      rig.dex.swaps['a-9'] = atomicSwapOf('a-9', [
        'Started',
        'Negotiated',
        'TakerFeeSent',
        'MakerPaymentReceived',
        'TakerPaymentSent',
        'MakerPaymentSpent',
        'Finished',
      ]);
      rig.resume('a-9');
      rig.firstPoll();
      rig.polls(3);

      expect(rig.latest.isSuccess, isTrue);
      expect(rig.dex.statusCalls, 1);
    });

    expect(rig.seen.map((s) => s.isSuccess), [isTrue]);
    expect(rig.done, isTrue);
  });
}
