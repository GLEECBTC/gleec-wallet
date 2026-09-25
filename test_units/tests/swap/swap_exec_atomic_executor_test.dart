import 'package:flutter_test/flutter_test.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_response.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the atomic executor's start, re-attach and cancel: one fill-or-kill
/// taker order per swap, and never a second tap's worth of doubt about
/// whether it was placed.
void main() {
  group('start', () {
    test('executes atomic quotes', () async {
      await onFakeClock((rig) {
        expect(rig.executor.source, SwapLiquiditySource.atomic);
      });
    });

    test('refuses a quote without an order plan as stale, placing '
        'nothing', () async {
      await onFakeClock((rig) {
        rig.start(quoteOf(source: SwapLiquiditySource.atomic, payload: 'x'));

        expect(
          rig.error,
          isA<SwapStartRejectedException>().having(
            (e) => e.reason,
            'reason',
            SwapStartRejection.quoteStale,
          ),
        );
        expect(rig.dex.sells, isEmpty);
      });
    });

    test('places one fill-or-kill order for exactly the quoted size and '
        'price', () async {
      await onFakeClock((rig) {
        rig.start(atomicQuoteOf(volume: '1.5', price: '2999.25'));

        final order = rig.dex.sells.single;
        expect(order.base, 'ETH');
        expect(order.rel, 'USDC-ERC20');
        expect(order.volume, Rational.parse('1.5'));
        expect(order.price, Rational.parse('2999.25'));
        expect(order.orderType, SellBuyOrderType.fillOrKill);
      });
    });

    test(
      'a placed order is matching, cancellable, and has moved nothing',
      () async {
        await onFakeClock((rig) {
          final quote = atomicQuoteOf();
          rig.start(quote);

          final snapshot = rig.latest;
          expect(rig.handle!.id, 'a-1');
          expect(snapshot.source, SwapLiquiditySource.atomic);
          expect(snapshot.routeKind, SwapRouteKind.direct);
          expect(snapshot.stage, SwapProgressStage.matching);
          expect(snapshot.canCancel, isTrue);
          expect(snapshot.fundsMovement, SwapFundsMovement.none);
          expect(snapshot.from, eth);
          expect(snapshot.to, usdc);
          expect(snapshot.sellAmount, d('1'));
          expect(snapshot.minimumReceive, d('2990'));
          expect(snapshot.stages, quote.stages);
        });
      },
    );

    test(
      'a request that got no answer is unconfirmed, keeping its cause',
      () async {
        await onFakeClock((rig) {
          final cause = StateError('connection reset');
          rig.dex.sellError = cause;
          rig.start();

          expect(
            rig.error,
            isA<SwapStartUnconfirmedException>().having(
              (e) => e.cause,
              'cause',
              same(cause),
            ),
          );
          expect(rig.handle, isNull);
        });
      },
    );

    test(
      'an error answer from the engine is a refusal with its message',
      () async {
        await onFakeClock((rig) {
          rig.dex.sellResponse = SellResponse(
            error: TextError(error: 'Not enough ETH'),
          );
          rig.start();

          expect(
            rig.error,
            isA<SwapStartRejectedException>()
                .having((e) => e.reason, 'reason', SwapStartRejection.unknown)
                .having((e) => e.detail, 'detail', 'Not enough ETH'),
          );
        });
      },
    );

    test('an order accepted without a reference is unconfirmed', () async {
      await onFakeClock((rig) {
        rig.dex.sellResponse = SellResponse();
        rig.start();

        expect(
          rig.error,
          isA<SwapStartUnconfirmedException>().having(
            (e) => e.cause,
            'cause',
            isStateError,
          ),
        );
      });
    });
  });

  group('resume', () {
    test('re-attaches to a swap the engine has a record of', () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-9'] = atomicSwapOf('a-9', ['Started', 'TakerFeeSent']);
        rig.resume('a-9');

        expect(rig.handle!.id, 'a-9');
        expect(rig.latest.canCancel, isFalse);

        rig.firstPoll();
        expect(rig.latest.stage, SwapProgressStage.sending);
        expect(rig.latest.fundsMovement, SwapFundsMovement.feesOnly);
        expect(rig.latest.from, eth);
      });
    });

    test('re-attaches to a taker order that has not matched yet', () async {
      await onFakeClock((rig) {
        rig.orders.takers['a-9'] = TakerOrderCancellationReason.none;
        rig.resume('a-9');

        expect(rig.handle!.id, 'a-9');
        rig.firstPoll();
        expect(rig.latest.stage, SwapProgressStage.matching);
        expect(rig.latest.canCancel, isTrue);
      });
    });

    test(
      'knows nothing of an id with neither a swap nor a taker order',
      () async {
        await onFakeClock((rig) {
          rig.orders.makers.add('m-1');
          rig.resume('m-1');
          rig.resume('ghost');

          expect(rig.handle, isNull);
          expect(rig.error, isNull);
          expect(rig.orders.statusCalls, 2);
        });
      },
    );
  });

  group('cancel', () {
    test('cancels an unmatched order, which ends with nothing moved', () async {
      final rig = await onFakeClock((rig) {
        rig.start();
        rig.handle!.cancel();
        rig.async.flushMicrotasks();

        expect(rig.orders.cancelled, ['a-1']);
        expect(rig.latest.outcome!.kind, SwapOutcomeKind.cancelled);
        expect(rig.latest.fundsMovement, SwapFundsMovement.none);
        expect(rig.latest.canCancel, isFalse);
      });
      expect(rig.done, isTrue);
    });

    test('an unanswered cancel is unconfirmed and ends nothing', () async {
      final rig = await onFakeClock((rig) {
        rig.orders.cancelError = 'timeout';
        rig.start();
        Object? error;
        rig.handle!.cancel().catchError((Object e) => error = e);
        rig.async.flushMicrotasks();

        expect(
          error,
          isA<SwapCancelUnconfirmedException>().having(
            (e) => e.cause,
            'cause',
            'timeout',
          ),
        );
        expect(rig.latest.isTerminal, isFalse);
      });
      expect(rig.done, isFalse);
    });

    Object? cancelError(AtomicRig rig) {
      Object? error;
      rig.handle!.cancel().catchError((Object e) => error = e);
      rig.async.flushMicrotasks();
      return error;
    }

    Matcher refused(SwapCancelRefusal reason) =>
        isA<SwapCancelRefusedException>().having(
          (e) => e.reason,
          'reason',
          reason,
        );

    test('a matched swap cannot be recalled', () async {
      await onFakeClock((rig) {
        rig.start();
        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', ['Started']);
        rig.firstPoll();

        expect(cancelError(rig), refused(SwapCancelRefusal.notSupported));
        expect(rig.orders.cancelled, isEmpty);
      });
    });

    test('a finished swap refuses as already finished', () async {
      await onFakeClock((rig) {
        rig.start();
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.timedOut;
        rig.firstPoll();

        expect(cancelError(rig), refused(SwapCancelRefusal.alreadyFinished));
        expect(rig.orders.cancelled, isEmpty);
      });
    });

    test(
      'a re-attached swap is not cancellable before its first read',
      () async {
        await onFakeClock((rig) {
          rig.dex.swaps['a-9'] = atomicSwapOf('a-9', ['Started']);
          rig.resume('a-9');

          expect(cancelError(rig), refused(SwapCancelRefusal.notSupported));
        });
      },
    );
  });
}
