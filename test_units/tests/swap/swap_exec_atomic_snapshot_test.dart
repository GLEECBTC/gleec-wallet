import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how an atomic swap's event log becomes a snapshot: its stage, its
/// outcome, and above all whether the funds moved.
void main() {
  SwapExecutionSnapshot fromLog(
    List<String> events, {
    Map<String, String> txHashes = const {},
    SwapQuote? accepted,
  }) => atomicSnapshotFromSwap(
    atomicSwapOf('a-1', events, txHashes: txHashes),
    networks: execNetworks,
    resolveAsset: resolveTicker,
    accepted: accepted,
  );

  const feePaid = ['Started', 'Negotiated', 'TakerFeeSent'];
  const paid = [...feePaid, 'MakerPaymentReceived', 'TakerPaymentSent'];

  group('running', () {
    test('each step of the log has its stage and funds movement', () {
      final expected = <List<String>, (SwapProgressStage, SwapFundsMovement)>{
        ['Started']: (SwapProgressStage.preparing, SwapFundsMovement.none),
        feePaid: (SwapProgressStage.sending, SwapFundsMovement.feesOnly),
        [...feePaid, 'MakerPaymentReceived']: (
          SwapProgressStage.confirming,
          SwapFundsMovement.feesOnly,
        ),
        [...feePaid, 'MakerPaymentWaitConfirmStarted']: (
          SwapProgressStage.confirming,
          SwapFundsMovement.feesOnly,
        ),
        [...feePaid, 'MakerPaymentValidatedAndConfirmed']: (
          SwapProgressStage.confirming,
          SwapFundsMovement.feesOnly,
        ),
        paid: (SwapProgressStage.exchanging, SwapFundsMovement.sent),
        [...feePaid, 'MakerPaymentSpent']: (
          SwapProgressStage.exchanging,
          SwapFundsMovement.feesOnly,
        ),
        [...paid, 'TakerPaymentWaitRefundStarted']: (
          SwapProgressStage.refunding,
          SwapFundsMovement.sent,
        ),
        [...paid, 'TakerPaymentRefundStarted']: (
          SwapProgressStage.refunding,
          SwapFundsMovement.sent,
        ),
      };
      for (final MapEntry(key: log, value: (stage, movement))
          in expected.entries) {
        final snapshot = fromLog(log);
        expect(snapshot.stage, stage, reason: log.last);
        expect(snapshot.fundsMovement, movement, reason: log.last);
        expect(snapshot.isTerminal, isFalse, reason: log.last);
        expect(snapshot.canCancel, isFalse, reason: log.last);
      }
    });
  });

  group('finished', () {
    test('a log without errors completed, delivering the bought amount', () {
      final snapshot = fromLog([...paid, 'MakerPaymentSpent', 'Finished']);

      expect(snapshot.outcome!.kind, SwapOutcomeKind.completed);
      expect(snapshot.outcome!.receivedAmount, d('3000'));
      expect(snapshot.outcome!.receivedAsset, usdc);
      expect(snapshot.fundsMovement, SwapFundsMovement.sent);
      expect(snapshot.stage, isNull);
      expect(snapshot.isSuccess, isTrue);
    });

    test('a refund by any route brings the sold asset back', () {
      for (final refund in [
        'TakerPaymentRefunded',
        'TakerPaymentRefundedByWatcher',
        'TakerPaymentRefundFinished',
      ]) {
        final snapshot = fromLog([
          ...paid,
          'TakerPaymentWaitForSpendFailed',
          refund,
          'Finished',
        ]);
        expect(
          snapshot.outcome!.kind,
          SwapOutcomeKind.refunded,
          reason: refund,
        );
        expect(snapshot.outcome!.receivedAsset, eth, reason: refund);
        expect(snapshot.fundsMovement, SwapFundsMovement.sent, reason: refund);
        expect(snapshot.needsAttention, isFalse, reason: refund);
      }
    });

    test('a failure before anything was sent is safe to retry', () {
      final snapshot = fromLog(['Started', 'NegotiateFailed', 'Finished']);
      final failure = snapshot.outcome!.failure!;

      expect(snapshot.outcome!.kind, SwapOutcomeKind.failed);
      expect(failure.reason, SwapFailureReason.exchangeFailed);
      expect(failure.nextStep, SwapNextStep.retry);
      expect(failure.retryable, isTrue);
      expect(failure.detail, 'NegotiateFailed');
      expect(snapshot.fundsMovement, SwapFundsMovement.none);
      expect(snapshot.needsAttention, isFalse);
    });

    test('a failure after the fee was paid spent fees only', () {
      final snapshot = fromLog([
        ...feePaid,
        'MakerPaymentValidateFailed',
        'Finished',
      ]);
      expect(snapshot.fundsMovement, SwapFundsMovement.feesOnly);
      expect(snapshot.outcome!.failure!.nextStep, SwapNextStep.retry);
      expect(snapshot.needsAttention, isTrue);
    });

    test('a failure after the payment left is never "nothing moved"', () {
      final snapshot = fromLog([
        ...paid,
        'TakerPaymentWaitForSpendFailed',
        'TakerPaymentRefundFailed',
        'Finished',
      ]);
      final failure = snapshot.outcome!.failure!;

      expect(snapshot.fundsMovement, SwapFundsMovement.uncertain);
      expect(failure.nextStep, SwapNextStep.contactSupport);
      expect(failure.retryable, isFalse);
      expect(
        failure.detail,
        'TakerPaymentWaitForSpendFailed, TakerPaymentRefundFailed',
      );
      expect(snapshot.needsAttention, isTrue);
    });

    test('the accepted quote names what came back or arrived', () {
      final accepted = quoteOf(
        source: SwapLiquiditySource.atomic,
        from: btc,
        to: gleec,
      );
      final completed = fromLog(['Started', 'Finished'], accepted: accepted);
      final refunded = fromLog([
        ...paid,
        'TakerPaymentRefunded',
        'Finished',
      ], accepted: accepted);

      expect(completed.outcome!.receivedAsset, gleec);
      expect(refunded.outcome!.receivedAsset, btc);
    });
  });

  group('evidence', () {
    test('keeps the payment hashes, the last state and the first error', () {
      final snapshot = fromLog(
        [...paid, 'TakerPaymentWaitForSpendFailed', 'MakerPaymentSpent'],
        txHashes: {'TakerPaymentSent': '0xpay', 'MakerPaymentSpent': '0xspend'},
      );
      final evidence = snapshot.evidence;

      expect(evidence.executionId, 'a-1');
      expect(evidence.sourceTxHash, '0xpay');
      expect(evidence.destinationTxHash, '0xspend');
      expect(evidence.rawState, 'MakerPaymentSpent');
      expect(evidence.errorType, 'TakerPaymentWaitForSpendFailed');
    });

    test('an event without a hash leaves the hash unknown', () {
      final evidence = fromLog(paid).evidence;
      expect(evidence.sourceTxHash, isNull);
      expect(evidence.destinationTxHash, isNull);
      expect(evidence.errorType, isNull);
    });

    test('dates the swap by its first and last events', () {
      final start = DateTime.utc(2026, 9).millisecondsSinceEpoch;
      final running = fromLog(feePaid);
      final done = fromLog(['Started', 'Negotiated', 'Finished']);

      expect(running.createdAt!.millisecondsSinceEpoch, start);
      expect(running.updatedAt!.millisecondsSinceEpoch, start + 2000);
      expect(running.finishedAt, isNull);
      expect(done.finishedAt!.millisecondsSinceEpoch, start + 2000);
    });
  });

  group('described without a log', () {
    SwapExecutionSnapshot describe({SwapQuote? accepted, Swap? swap}) =>
        atomicSnapshot(
          uuid: 'a-1',
          stage: SwapProgressStage.matching,
          networks: execNetworks,
          resolveAsset: resolveTicker,
          canCancel: true,
          accepted: accepted,
          swap: swap,
        );

    test('knows only its id before anything is read', () {
      final snapshot = describe();

      expect(snapshot.source, SwapLiquiditySource.atomic);
      expect(snapshot.routeKind, SwapRouteKind.direct);
      expect(snapshot.from, isNull);
      expect(snapshot.fromTicker, '');
      expect(snapshot.toTicker, '');
      expect(snapshot.sellAmount, isNull);
      expect(snapshot.expectedReceive, isNull);
      expect(snapshot.minimumReceive, isNull);
      expect(snapshot.stages, [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
      ]);
      expect(snapshot.createdAt, isNull);
      expect(snapshot.evidence, const SwapEvidence(executionId: 'a-1'));
      expect(snapshot.canCancel, isTrue);
    });

    test('takes its terms and route from the accepted quote', () {
      final accepted = quoteOf(
        source: SwapLiquiditySource.atomic,
        from: btc,
        to: gleec,
        sell: '0.1',
        expected: '50',
        guaranteed: '49',
      );
      final snapshot = describe(accepted: accepted);

      expect(snapshot.from, btc);
      expect(snapshot.fromTicker, 'BTC');
      expect(snapshot.to, gleec);
      expect(snapshot.sellAmount, d('0.1'));
      expect(snapshot.expectedReceive, d('50'));
      expect(snapshot.minimumReceive, d('49'));
      expect(snapshot.fromAddress, accepted.fromAddress);
      expect(snapshot.stages, accepted.stages);
    });

    test('names each network of a swap known only by its record', () {
      final snapshot = describe(swap: atomicSwapOf('a-1', ['Started']));

      expect(snapshot.stages, [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
        SwapRouteStage(
          kind: SwapRouteStageKind.send,
          network: execNetworks.networkOf(eth),
          asset: eth,
        ),
        SwapRouteStage(
          kind: SwapRouteStageKind.exchange,
          network: execNetworks.networkOf(usdc),
          asset: usdc,
        ),
        SwapRouteStage(
          kind: SwapRouteStageKind.receive,
          network: execNetworks.networkOf(usdc),
          asset: usdc,
        ),
      ]);
      expect(snapshot.minimumReceive, d('3000'));
    });

    test('keeps the tickers of coins the wallet does not know', () {
      final snapshot = describe(
        swap: atomicSwapOf('a-1', ['Started'], sell: 'OLD', buy: 'NEW'),
      );
      expect(snapshot.from, isNull);
      expect(snapshot.fromTicker, 'OLD');
      expect(snapshot.to, isNull);
      expect(snapshot.toTicker, 'NEW');
      expect(snapshot.stages, [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
      ]);
    });

    test('an event logged without a time is undated', () {
      final swap = Swap.fromJson({
        'type': 'Taker',
        'uuid': 'a-1',
        'events': [
          {
            'timestamp': 0,
            'event': {'type': 'Started'},
          },
        ],
        'success_events': const <String>[],
        'error_events': const <String>[],
      });
      expect(describe(swap: swap).createdAt, isNull);
    });

    test('an outcome ends the stage and the chance to cancel', () {
      final snapshot = atomicSnapshot(
        uuid: 'a-1',
        stage: SwapProgressStage.matching,
        networks: execNetworks,
        resolveAsset: resolveTicker,
        canCancel: true,
        outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.noMatch),
      );
      expect(snapshot.stage, isNull);
      expect(snapshot.canCancel, isFalse);
      expect(snapshot.isTerminal, isTrue);
    });
  });

  group('a maker\'s own swap', () {
    test('a completed one delivers what the maker bought', () {
      final snapshot = atomicSnapshotFromSwap(
        atomicSwapOf('m-1', ['Started', 'Finished'], maker: true),
        networks: execNetworks,
        resolveAsset: resolveTicker,
      );
      expect(snapshot.from, eth);
      expect(snapshot.to, usdc);
      expect(snapshot.sellAmount, d('1'));
      expect(snapshot.outcome!.receivedAmount, d('3000'));
      expect(snapshot.outcome!.receivedAsset, usdc);
    });

    test(
      'one that failed after the maker payment left is never "nothing moved"',
      () {
        final snapshot = atomicSnapshotFromSwap(
          atomicSwapOf('m-1', [
            'Started',
            'Negotiated',
            'TakerFeeValidated',
            'MakerPaymentSent',
            'TakerPaymentValidateFailed',
            'MakerPaymentWaitRefundStarted',
            'MakerPaymentRefundFailed',
            'Finished',
          ], maker: true),
          networks: execNetworks,
          resolveAsset: resolveTicker,
        );
        expect(snapshot.fundsMovement, isNot(SwapFundsMovement.none));
        expect(
          snapshot.outcome!.failure!.nextStep,
          SwapNextStep.contactSupport,
        );
        expect(snapshot.needsAttention, isTrue);
      },
    );
  });
}
