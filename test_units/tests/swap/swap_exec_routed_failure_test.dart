import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a routed failure's explanation — reason, next step, shortfall and
/// the re-priced quote — and the evidence every routed snapshot carries.
void main() {
  SwapExecutionFailure failureFrom(
    RoutedSwapFailure failure, {
    SwapQuote? accepted,
  }) => routedSnapshotFrom(
    progressOf(phase: RoutedSwapPhase.failed, failure: failure),
    networks: execNetworks,
    accepted: accepted,
  ).outcome!.failure!;

  group('reason', () {
    test('each engine failure kind has its reason', () {
      const expected = {
        RoutedSwapFailureKind.priceMoved: SwapFailureReason.priceMoved,
        RoutedSwapFailureKind.insufficientBalance:
            SwapFailureReason.insufficientBalance,
        RoutedSwapFailureKind.approvalFailed: SwapFailureReason.approvalFailed,
        RoutedSwapFailureKind.signingRejected: SwapFailureReason.walletRejected,
        RoutedSwapFailureKind.bridgeFailed: SwapFailureReason.routeFailed,
        RoutedSwapFailureKind.preflightRejected: SwapFailureReason.safetyCheck,
        RoutedSwapFailureKind.quoteUnavailable:
            SwapFailureReason.quoteUnavailable,
        RoutedSwapFailureKind.abortedOnRestart: SwapFailureReason.restarted,
        RoutedSwapFailureKind.internalError: SwapFailureReason.internal,
        RoutedSwapFailureKind.unknown: SwapFailureReason.unknown,
      };
      for (final MapEntry(key: kind, value: reason) in expected.entries) {
        expect(failureFrom(failureOf(kind)).reason, reason, reason: kind.name);
      }
    });

    test('a failed swap transaction is reverted only when the engine says '
        'so', () {
      SwapFailureReason reasonOf(RoutedSwapTxFailureReason? txReason) =>
          failureFrom(
            failureOf(
              RoutedSwapFailureKind.swapTransactionFailed,
              txReason: txReason,
            ),
          ).reason;

      expect(
        reasonOf(RoutedSwapTxFailureReason.sourceTransactionReverted),
        SwapFailureReason.reverted,
      );
      expect(
        reasonOf(RoutedSwapTxFailureReason.sourceTransactionNotConfirmed),
        SwapFailureReason.notConfirmed,
      );
      expect(
        reasonOf(RoutedSwapTxFailureReason.unknown),
        SwapFailureReason.notConfirmed,
      );
      expect(reasonOf(null), SwapFailureReason.notConfirmed);
    });

    test('keeps the engine\'s own words as diagnostic detail only', () {
      final failure = failureFrom(
        failureOf(
          RoutedSwapFailureKind.quoteUnavailable,
          errorType: 'NoRouteFound',
          message: 'no route right now',
          noRouteReasons: ['Insufficient liquidity'],
        ),
      );
      expect(failure.detail, 'NoRouteFound: no route right now');
      expect(failure.noRouteReasons, ['Insufficient liquidity']);
    });
  });

  group('next step', () {
    test('each retry policy has its next step', () {
      const expected = {
        RoutedSwapRetryPolicy.retry: SwapNextStep.retry,
        RoutedSwapRetryPolicy.requote: SwapNextStep.requote,
        RoutedSwapRetryPolicy.fixAndRetry: SwapNextStep.fixAndRetry,
        RoutedSwapRetryPolicy.wait: SwapNextStep.wait,
        RoutedSwapRetryPolicy.contactSupport: SwapNextStep.contactSupport,
      };
      for (final MapEntry(key: policy, value: step) in expected.entries) {
        final failure = failureFrom(
          failureOf(RoutedSwapFailureKind.internalError, policy: policy),
        );
        expect(failure.nextStep, step, reason: policy.name);
        expect(
          failure.retryable,
          policy == RoutedSwapRetryPolicy.retry ||
              policy == RoutedSwapRetryPolicy.requote,
          reason: policy.name,
        );
      }
    });

    test('a safety check decides for itself whether a retry is sensible', () {
      final stale = failureFrom(
        failureOf(
          RoutedSwapFailureKind.preflightRejected,
          policy: RoutedSwapRetryPolicy.contactSupport,
          check: RoutedSwapPreflightCheck.simulation,
        ),
      );
      final blocked = failureFrom(
        failureOf(
          RoutedSwapFailureKind.preflightRejected,
          check: RoutedSwapPreflightCheck.targetAllowlist,
        ),
      );
      expect(stale.retryable, isTrue);
      expect(blocked.retryable, isFalse);
    });
  });

  test('an insufficient balance names what ran short, and by how much', () {
    final failure = failureFrom(
      failureOf(
        RoutedSwapFailureKind.insufficientBalance,
        policy: RoutedSwapRetryPolicy.fixAndRetry,
        shortfall: RoutedSwapShortfall(
          ticker: 'ETH',
          assetId: eth,
          available: d('0.01'),
          required: d('0.02'),
        ),
      ),
    );
    expect(failure.shortfallAsset, eth);
    expect(failure.shortfallTicker, 'ETH');
    expect(failure.shortfallAvailable, d('0.01'));
    expect(failure.shortfallRequired, d('0.02'));
  });

  test('without a shortfall, none is claimed', () {
    final failure = failureFrom(
      failureOf(RoutedSwapFailureKind.insufficientBalance),
    );
    expect(failure.shortfallAsset, isNull);
    expect(failure.shortfallTicker, isNull);
    expect(failure.shortfallAvailable, isNull);
    expect(failure.shortfallRequired, isNull);
  });

  group('price moved', () {
    final fresh = offerOf(expected: '2950', guaranteed: '2940');

    test('offers the re-priced route, on the route order the user chose', () {
      final failure = failureFrom(
        failureOf(
          RoutedSwapFailureKind.priceMoved,
          policy: RoutedSwapRetryPolicy.requote,
          freshOffer: fresh,
        ),
        accepted: quoteOf(order: SwapQuoteOrder.fastest),
      );

      expect(failure.freshQuote!.payload, same(fresh));
      expect(failure.freshQuote!.guaranteedReceive, d('2940'));
      expect(failure.freshQuote!.order, SwapQuoteOrder.fastest);
    });

    test('without an accepted quote, the fresh route keeps its own order', () {
      final failure = failureFrom(
        failureOf(
          RoutedSwapFailureKind.priceMoved,
          freshOffer: offerOf(order: RoutedSwapOrder.fastest),
        ),
      );
      expect(failure.freshQuote!.order, SwapQuoteOrder.fastest);
      expect(
        failure.freshQuote,
        routedQuoteFromOffer(
          offerOf(order: RoutedSwapOrder.fastest),
          networks: execNetworks,
        ),
      );
    });

    test('no fresh route means no quote to consent to', () {
      final failure = failureFrom(failureOf(RoutedSwapFailureKind.priceMoved));
      expect(failure.freshQuote, isNull);
    });
  });

  group('evidence', () {
    test('carries every identifier support needs', () {
      final created = DateTime.utc(2026, 9, 24, 10);
      final snapshot = routedSnapshotFrom(
        RoutedSwapProgress(
          uuid: 'r-9',
          phase: RoutedSwapPhase.failed,
          canCancel: false,
          rawState: 'Error',
          approvalTxHashes: const ['0xreset', '0xapprove'],
          sourceTxHash: '0xsource',
          destinationTxHash: '0xdest',
          explorerUrl: 'https://scan.example/tx/0xsource',
          providerStatusDetail: 'BRIDGE_NOT_AVAILABLE',
          createdAt: created,
          updatedAt: created.add(const Duration(minutes: 1)),
          finishedAt: created.add(const Duration(minutes: 2)),
          delayedSince: created.add(const Duration(seconds: 30)),
          failure: failureOf(
            RoutedSwapFailureKind.bridgeFailed,
            movement: RoutedSwapFundsMovement.sent,
            errorType: 'BridgeFailed',
            providerRequestId: 'req-42',
          ),
          gasSpent: [
            RoutedSwapGasPaid(
              ticker: 'ETH',
              assetId: eth,
              amount: d('0.002'),
              txHash: '0xsource',
            ),
            RoutedSwapGasPaid(ticker: 'XYZ', amount: d('0.5')),
          ],
        ),
        networks: execNetworks,
      );

      final evidence = snapshot.evidence;
      expect(snapshot.id, 'r-9');
      expect(evidence.executionId, 'r-9');
      expect(evidence.approvalTxHashes, ['0xreset', '0xapprove']);
      expect(evidence.sourceTxHash, '0xsource');
      expect(evidence.destinationTxHash, '0xdest');
      expect(evidence.providerExplorerUrl, 'https://scan.example/tx/0xsource');
      expect(evidence.providerRequestId, 'req-42');
      expect(evidence.providerStatus, 'BRIDGE_NOT_AVAILABLE');
      expect(evidence.rawState, 'Error');
      expect(evidence.errorType, 'BridgeFailed');
      expect(evidence.gasSpent, [
        SwapGasSpent(
          ticker: 'ETH',
          asset: eth,
          amount: d('0.002'),
          txHash: '0xsource',
        ),
        SwapGasSpent(ticker: 'XYZ', amount: d('0.5')),
      ]);
      expect(snapshot.createdAt, created);
      expect(snapshot.updatedAt, created.add(const Duration(minutes: 1)));
      expect(snapshot.finishedAt, created.add(const Duration(minutes: 2)));
      expect(snapshot.delayedSince, created.add(const Duration(seconds: 30)));
    });

    test('a running swap has no failure evidence, and says if it can stop', () {
      final snapshot = routedSnapshotFrom(
        progressOf(phase: RoutedSwapPhase.signing, canCancel: true),
        networks: execNetworks,
      );
      expect(snapshot.canCancel, isTrue);
      expect(snapshot.evidence.errorType, isNull);
      expect(snapshot.evidence.providerRequestId, isNull);
      expect(snapshot.evidence.gasSpent, isEmpty);
    });
  });
}
