import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_execution/swap_execution_bloc.dart';
import 'package:web_dex/mm2/mm2_api/rpc/order_status/cancellation_reason.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_atomic_fakes.dart';

/// Covers the atomic executor when KDF does not answer a re-attach or a
/// cancel, and which answers prove it does not know a swap.
void main() {
  const paid = [
    'Started',
    'Negotiated',
    'TakerFeeSent',
    'MakerPaymentReceived',
    'TakerPaymentSent',
  ];
  const timeout = Duration(seconds: 15);
  const tick = Duration(milliseconds: 1);
  final cannotRead = TextError(error: 'something went wrong');

  group('re-attaching', () {
    test('gives up after 15 seconds when KDF answers no read', () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-9'] = atomicSwapOf('a-9', paid);
        rig.dex.statusGate = Completer<void>();
        rig.orders.statusGate = Completer<void>();
        rig.resume('a-9');
        rig.async.elapse(timeout - tick);
        expect(rig.error, isNull);

        rig.async.elapse(tick);
        expect(rig.error, isA<TimeoutException>());
        expect(rig.handle, isNull);
      });
    });

    test('an order read that never returns gives up after 15 seconds, when '
        'KDF has no swap under the id', () async {
      await onFakeClock((rig) {
        rig.orders.statusGate = Completer<void>();
        rig.resume('a-9');
        rig.async.elapse(timeout - tick);
        expect(rig.error, isNull);

        rig.async.elapse(tick);
        expect(rig.error, isA<TimeoutException>());
      });
    });

    for (final (name, arrange) in <(String, void Function(AtomicRig))>[
      ('a swap read that failed', (rig) => rig.dex.statusError = cannotRead),
      (
        'no swap, and an order read that failed',
        (rig) => rig.orders.statusError = cannotRead,
      ),
    ]) {
      test('$name proves nothing, so re-attaching throws', () async {
        await onFakeClock((rig) {
          arrange(rig);
          rig.resume('a-9');

          expect(rig.error, same(cannotRead));
          expect(rig.handle, isNull);
        });
      });
    }

    test('a swap row with no event yet is a swap KDF knows, though it has no '
        'order', () async {
      await onFakeClock((rig) {
        rig.dex.unrecorded.add('a-9');
        rig.resume('a-9');
        rig.firstPoll();

        expect(rig.handle!.id, 'a-9');
        expect(rig.latest.stage, SwapProgressStage.preparing);
      });
    });

    for (final (name, arrange) in <(String, void Function(AtomicRig))>[
      ('no swap and no order', (_) {}),
      ('no swap, and a maker order', (rig) => rig.orders.makers.add('a-9')),
    ]) {
      test('$name is a swap it does not know', () async {
        await onFakeClock((rig) {
          arrange(rig);
          rig.resume('a-9');

          expect(rig.handle, isNull);
          expect(rig.error, isNull);
        });
      });
    }

    test('a swap screen opened while KDF is not answering shows the status '
        'delayed, and follows the swap once KDF answers', () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-9'] = atomicSwapOf('a-9', paid);
        rig.dex.statusGate = Completer<void>();
        rig.orders.statusGate = Completer<void>();
        final registry = SwapExecutionRegistry(
          executors: [rig.executor],
          inFlight: () async => const [],
        );
        final bloc = SwapExecutionBloc(registry: registry)
          ..add(
            const SwapExecutionWatched(
              'a-9',
              source: SwapLiquiditySource.atomic,
            ),
          );
        rig.async.elapse(timeout);
        expect(bloc.state.unanswered, isTrue);
        expect(bloc.state.notFound, isFalse);

        rig.dex.statusGate!.complete();
        rig.dex.statusGate = null;
        rig.orders.statusGate!.complete();
        rig.orders.statusGate = null;
        rig.async.elapse(const Duration(seconds: 10));
        expect(bloc.state.unanswered, isFalse);
        expect(bloc.state.snapshot!.stage, SwapProgressStage.exchanging);

        unawaited(bloc.close());
        unawaited(registry.dispose());
        rig.async.flushMicrotasks();
      });
    });

    test('a swap whose read hangs at sign-in delays those after it only until '
        'it times out, and is picked up once KDF answers for it', () async {
      await onFakeClock((rig) {
        rig.dex.swaps['a-1'] = atomicSwapOf('a-1', paid);
        rig.dex.swaps['a-2'] = atomicSwapOf('a-2', paid);
        rig.dex.gates['a-1'] = Completer<void>();
        final registry = SwapExecutionRegistry(
          executors: [rig.executor],
          inFlight: () async => [
            (id: 'a-1', source: SwapLiquiditySource.atomic),
            (id: 'a-2', source: SwapLiquiditySource.atomic),
          ],
        );
        unawaited(registry.resumeInFlight());
        rig.async.elapse(timeout);
        expect(registry.snapshotOf('a-1'), isNull);
        expect(registry.snapshotOf('a-2'), isNotNull);

        rig.dex.gates.remove('a-1')!.complete();
        rig.async.elapse(const Duration(seconds: 10));
        expect(registry.snapshotOf('a-1'), isNotNull);

        unawaited(registry.dispose());
        rig.async.flushMicrotasks();
      });
    });
  });

  group('cancelling', () {
    test('a cancel that never returns is unconfirmed after 15 seconds, and '
        'the swap goes on reporting the truth', () async {
      final rig = await onFakeClock((rig) {
        rig.orders.takers['a-1'] = TakerOrderCancellationReason.none;
        rig.start();
        rig.firstPoll();
        rig.orders.cancelGate = Completer<void>();
        Object? error;
        rig.handle!.cancel().catchError((Object e) => error = e);
        rig.async.elapse(timeout - tick);
        expect(error, isNull);

        rig.async.elapse(tick);
        expect(
          error,
          isA<SwapCancelUnconfirmedException>().having(
            (e) => e.cause,
            'cause',
            isA<TimeoutException>(),
          ),
        );
        expect(rig.orders.cancelled, ['a-1']);
        expect(rig.latest.isTerminal, isFalse);
        expect(rig.latest.canCancel, isTrue);

        rig.orders.takers['a-1'] = TakerOrderCancellationReason.cancelled;
        rig.polls();
      });

      expect(rig.latest.outcome!.kind, SwapOutcomeKind.cancelled);
      expect(rig.done, isTrue);
    });
  });
}
