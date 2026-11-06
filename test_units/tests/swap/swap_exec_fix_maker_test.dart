import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';

import 'swap_exec_atomic_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a maker's own swap, started from Advanced and reaching Activity and
/// sign-in: a maker pays no fee and pays first, so its log reads differently
/// from a taker's.
void main() {
  SwapExecutionSnapshot fromLog(
    List<String> events, {
    Map<String, String> txHashes = const {},
  }) => atomicSnapshotFromSwap(
    atomicSwapOf('m-1', events, maker: true, txHashes: txHashes),
    networks: execNetworks,
    resolveAsset: resolveTicker,
  );

  const validated = ['Started', 'Negotiated', 'TakerFeeValidated'];
  const paid = [...validated, 'MakerPaymentSent'];
  const takerPaid = [
    ...paid,
    'TakerPaymentReceived',
    'TakerPaymentWaitConfirmStarted',
    'TakerPaymentValidatedAndConfirmed',
  ];

  test('each step of its log has its stage and funds movement', () {
    final expected = <List<String>, (SwapProgressStage, SwapFundsMovement)>{
      ['Started', 'Negotiated']: (
        SwapProgressStage.preparing,
        SwapFundsMovement.none,
      ),
      validated: (SwapProgressStage.sending, SwapFundsMovement.none),
      paid: (SwapProgressStage.exchanging, SwapFundsMovement.sent),
      takerPaid: (SwapProgressStage.exchanging, SwapFundsMovement.sent),
      [...takerPaid, 'TakerPaymentSpent']: (
        SwapProgressStage.exchanging,
        SwapFundsMovement.sent,
      ),
      [...paid, 'TakerPaymentValidateFailed', 'MakerPaymentWaitRefundStarted']:
          (SwapProgressStage.refunding, SwapFundsMovement.sent),
      [...paid, 'TakerPaymentValidateFailed', 'MakerPaymentRefundStarted']: (
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
    }
  });

  test('a failure before its payment left moved nothing, and is safe to '
      'retry', () {
    final snapshot = fromLog([
      ...validated,
      'MakerPaymentTransactionFailed',
      'Finished',
    ]);
    final failure = snapshot.outcome!.failure!;

    expect(snapshot.fundsMovement, SwapFundsMovement.none);
    expect(failure.nextStep, SwapNextStep.retry);
    expect(failure.retryable, isTrue);
    expect(failure.detail, 'MakerPaymentTransactionFailed');
    expect(snapshot.needsAttention, isFalse);
  });

  test('a refund by either route brings back what it sold', () {
    for (final refund in [
      'MakerPaymentRefunded',
      'MakerPaymentRefundFinished',
    ]) {
      final snapshot = fromLog([
        ...paid,
        'TakerPaymentValidateFailed',
        'MakerPaymentWaitRefundStarted',
        refund,
        'Finished',
      ]);
      expect(snapshot.outcome!.kind, SwapOutcomeKind.refunded, reason: refund);
      expect(snapshot.outcome!.receivedAsset, eth, reason: refund);
      expect(snapshot.fundsMovement, SwapFundsMovement.sent, reason: refund);
      expect(snapshot.needsAttention, isFalse, reason: refund);
    }
  });

  test('its own payment is the sent side, and the taker payment it spent '
      'the received side', () {
    final evidence = fromLog(
      [...takerPaid, 'TakerPaymentSpent'],
      txHashes: {
        'MakerPaymentSent': '0xmaker',
        'TakerPaymentReceived': '0xtaker',
        'TakerPaymentSpent': '0xspend',
      },
    ).evidence;

    expect(evidence.sourceTxHash, '0xmaker');
    expect(evidence.destinationTxHash, '0xspend');
  });

  test('one that failed after its payment left is listed under Needs '
      'attention', () async {
    final history = SwapHistoryRepository(
      routedSwaps: _NoRoutedSwaps(),
      atomicHistory: ({required int limit, required int page}) async =>
          AtomicSwapHistoryPage(
            swaps: [
              atomicSwapOf('m-1', [
                ...paid,
                'TakerPaymentValidateFailed',
                'MakerPaymentWaitRefundStarted',
                'MakerPaymentRefundFailed',
                'Finished',
              ], maker: true),
            ],
            hasMore: false,
          ),
      networks: () => execNetworks,
      resolveAsset: resolveTicker,
    );

    final attention = await history.load(filter: SwapActivityFilter.attention);
    final done = await history.load(filter: SwapActivityFilter.completed);

    expect(attention.entries.single.fundsMovement, SwapFundsMovement.uncertain);
    expect(done.entries, isEmpty);
  });
}

/// A routed history with nothing in it.
class _NoRoutedSwaps implements RoutedSwapManager {
  @override
  Future<RoutedSwapHistoryPage> history({
    int pageNumber = 1,
    int limit = 20,
    RoutedSwapHistoryFilter? filter,
    AssetId? from,
    AssetId? to,
    DateTime? createdAfter,
    DateTime? createdBefore,
  }) async => const RoutedSwapHistoryPage(
    entries: [],
    total: 0,
    pageNumber: 1,
    totalPages: 1,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
