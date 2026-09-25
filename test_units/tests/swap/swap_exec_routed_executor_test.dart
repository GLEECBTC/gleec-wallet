import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the routed executor: how the SDK's start, re-attach and cancel
/// answers become the app's, and how a running swap is followed.
void main() {
  late FakeRoutedManager manager;
  late RoutedSwapExecutor executor;
  final offer = offerOf();
  final quote = quoteOf(payload: offer);

  setUp(() {
    manager = FakeRoutedManager();
    executor = RoutedSwapExecutor(manager, networks: () => execNetworks);
  });

  test('executes routed quotes', () {
    expect(executor.source, SwapLiquiditySource.routed);
    expect(executor.manager, same(manager));
  });

  group('start', () {
    test('refuses a quote without a routed offer as stale, sending '
        'nothing', () async {
      await expectLater(
        executor.start(quoteOf(payload: 'not an offer')),
        throwsA(
          isA<SwapStartRejectedException>().having(
            (e) => e.reason,
            'reason',
            SwapStartRejection.quoteStale,
          ),
        ),
      );
      expect(manager.started, isEmpty);
    });

    test('starts the accepted offer and reports its first snapshot', () async {
      final handle = await executor.start(quote);

      expect(manager.started.single, same(offer));
      expect(handle.id, 'r-1');
      expect(handle.latest.source, SwapLiquiditySource.routed);
      expect(handle.latest.stage, SwapProgressStage.preparing);
      expect(handle.latest.fundsMovement, SwapFundsMovement.none);
      expect(handle.latest.canCancel, isTrue);
      expect(handle.latest.sellAmount, d('1'));
      expect(handle.latest.minimumReceive, d('2985'));
    });

    test('a lost start answer stays unconfirmed and keeps its cause', () async {
      final cause = StateError('socket closed');
      manager.startError = RoutedSwapStartUnconfirmedException(cause);

      await expectLater(
        executor.start(quote),
        throwsA(
          isA<SwapStartUnconfirmedException>().having(
            (e) => e.cause,
            'cause',
            same(cause),
          ),
        ),
      );
    });

    test('a refusal about the pair or amount reads as not available', () async {
      const refusals = <RoutedSwapRpcException>[
        RoutedSwapCoinNotActiveException(coin: 'ETH', message: 'inactive'),
        RoutedSwapPairNotSupportedException(
          from: 'ETH',
          to: 'USDC-ERC20',
          reason: 'no pair',
          message: 'unsupported',
        ),
        RoutedSwapAmountOutOfBoundsException(
          param: 'amount',
          value: '9',
          min: '1',
          max: '5',
          message: 'too much',
        ),
        RoutedSwapInvalidParamException(
          param: 'amount',
          reason: 'decimals',
          message: 'bad amount',
        ),
        RoutedSwapMyAddressException(
          coin: 'ETH',
          detail: 'hd',
          message: 'no address',
        ),
      ];
      for (final refusal in refusals) {
        manager.startError = refusal;
        await expectLater(
          executor.start(quote),
          throwsA(
            isA<SwapStartRejectedException>()
                .having(
                  (e) => e.reason,
                  'reason',
                  SwapStartRejection.notAvailable,
                )
                .having(
                  (e) => e.detail,
                  'detail',
                  '${refusal.errorType}: ${refusal.message}',
                ),
          ),
          reason: refusal.errorType,
        );
      }
    });

    test(
      'any other engine refusal reads as unknown, never as started',
      () async {
        const refusals = <RoutedSwapRpcException>[
          RoutedSwapNoRouteException(message: 'no route'),
          RoutedSwapRateLimitedException(message: 'slow down'),
          RoutedSwapProviderException(detail: 'x', message: 'provider'),
          RoutedSwapTransportException(detail: 'x', message: 'transport'),
          RoutedSwapInternalException(detail: 'x', message: 'internal'),
          RoutedSwapInvalidConfigException(detail: 'x', message: 'config'),
          RoutedSwapNoSuchTaskException(message: 'no task'),
          RoutedSwapTaskFinishedException(message: 'finished'),
          RoutedSwapTaskAlreadyBroadcastException(message: 'broadcast'),
          RoutedSwapUnknownRpcException(errorType: 'Newer', message: 'new'),
        ];
        for (final refusal in refusals) {
          manager.startError = refusal;
          await expectLater(
            executor.start(quote),
            throwsA(
              isA<SwapStartRejectedException>()
                  .having((e) => e.reason, 'reason', SwapStartRejection.unknown)
                  .having(
                    (e) => e.detail,
                    'detail',
                    '${refusal.errorType}: ${refusal.message}',
                  ),
            ),
            reason: refusal.errorType,
          );
        }
      },
    );

    test(
      'an unexpected start error passes through, never as a refusal',
      () async {
        manager.startError = const FormatException('bad record');

        await expectLater(
          executor.start(quote),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('describes a started swap from the accepted quote when the engine '
        'record carries no offer', () async {
      manager.seed = (_) => progressOf(uuid: 'r-bare', canCancel: true);
      final accepted = quoteOf(
        payload: offer,
        from: btc,
        to: gleec,
        sell: '0.5',
        expected: '100',
        guaranteed: '99',
      );

      final handle = await executor.start(accepted);

      expect(handle.latest.from, btc);
      expect(handle.latest.to, gleec);
      expect(handle.latest.fromTicker, 'BTC');
      expect(handle.latest.sellAmount, d('0.5'));
      expect(handle.latest.expectedReceive, d('100'));
      expect(handle.latest.minimumReceive, d('99'));
      expect(handle.latest.stages, accepted.stages);
    });
  });

  group('resume', () {
    test('re-attaches through the engine by durable id', () async {
      manager.live['r-7'] = FakeRoutedHandle(
        progressOf(
          uuid: 'r-7',
          phase: RoutedSwapPhase.bridging,
          offer: offerOf(kind: RoutedSwapRouteKind.crossChain, to: arbEth),
        ),
      );

      final handle = await executor.resume('r-7');

      expect(handle!.id, 'r-7');
      expect(handle.latest.stage, SwapProgressStage.bridging);
      expect(handle.latest.routeKind, SwapRouteKind.crossChain);
      expect(handle.latest.fundsMovement, SwapFundsMovement.sent);
    });

    test('answers null for a swap the engine does not know', () async {
      expect(await executor.resume('nobody'), isNull);
    });

    test('passes other failures on, so another source can be tried', () async {
      manager.watchError = StateError('history down');

      await expectLater(executor.resume('r-1'), throwsStateError);
    });
  });

  group('following', () {
    test('maps each engine snapshot until the swap finishes', () async {
      final handle = await executor.start(quote);
      final engine = manager.live['r-1']!;
      final seen = <SwapExecutionSnapshot>[];
      var done = false;
      handle.updates.listen(seen.add, onDone: () => done = true);
      await pumpEventQueue();

      engine.push(progressOf(offer: offer, phase: RoutedSwapPhase.sending));
      engine.push(progressOf(offer: offer, phase: RoutedSwapPhase.sending));
      engine.push(
        progressOf(
          offer: offer,
          phase: RoutedSwapPhase.finished,
          receipt: RoutedSwapReceipt(
            outcome: RoutedSwapOutcome.completed,
            amount: d('2990'),
            assetId: usdc,
          ),
        ),
      );
      await engine.end();
      await pumpEventQueue();

      expect(seen.map((s) => s.stage), [
        SwapProgressStage.preparing,
        SwapProgressStage.sending,
        null,
      ]);
      expect(seen.last.outcome!.kind, SwapOutcomeKind.completed);
      expect(handle.latest.isSuccess, isTrue);
      expect(done, isTrue);
    });

    test('closing stops following without touching the swap', () async {
      final handle = await executor.start(quote);
      final engine = manager.live['r-1']!;

      await handle.close();
      engine.push(progressOf(offer: offer, phase: RoutedSwapPhase.sending));
      await pumpEventQueue();

      expect(handle.latest.stage, SwapProgressStage.preparing);
      expect(engine.hasListener, isFalse);
      expect(engine.cancelCalls, 0);
    });
  });

  group('cancel', () {
    late SwapExecutionHandle handle;
    late FakeRoutedHandle engine;

    setUp(() async {
      handle = await executor.start(quote);
      engine = manager.live['r-1']!;
    });

    test('reaches the engine', () async {
      await handle.cancel();
      expect(engine.cancelCalls, 1);
    });

    test('each engine refusal keeps its meaning', () async {
      const expected = {
        RoutedSwapCancelRefusal.alreadyBroadcast: SwapCancelRefusal.alreadySent,
        RoutedSwapCancelRefusal.alreadyFinished:
            SwapCancelRefusal.alreadyFinished,
        RoutedSwapCancelRefusal.notAddressable: SwapCancelRefusal.notSupported,
      };
      for (final MapEntry(key: refusal, value: reason) in expected.entries) {
        engine.cancelError = RoutedSwapNotCancellableException(
          'r-1',
          RoutedSwapPhase.sending,
          refusal: refusal,
        );
        await expectLater(
          handle.cancel(),
          throwsA(
            isA<SwapCancelRefusedException>().having(
              (e) => e.reason,
              'reason',
              reason,
            ),
          ),
          reason: refusal.name,
        );
      }
    });

    test('a lost cancel answer is unconfirmed and keeps its cause', () async {
      final cause = StateError('timeout');
      engine.cancelError = RoutedSwapCancelUnconfirmedException('r-1', cause);

      await expectLater(
        handle.cancel(),
        throwsA(
          isA<SwapCancelUnconfirmedException>().having(
            (e) => e.cause,
            'cause',
            same(cause),
          ),
        ),
      );
    });

    test('an unexpected cancel error passes through unchanged', () async {
      engine.cancelError = ArgumentError('odd');

      await expectLater(handle.cancel(), throwsArgumentError);
    });
  });
}
