import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// What a finished swap lets someone do next, and what support is handed.
void main() {
  final networks = SwapNetworks([eth, usdc, btc, gleec]);
  SwapExecutionCopy copyOf(SwapExecutionSnapshot snapshot) =>
      SwapExecutionCopy(snapshot, networks);

  group('swap outcome actions', () {
    List<SwapOutcomeAction> actionsOf(SwapExecutionSnapshot snapshot) =>
        copyOf(snapshot).actions;

    List<SwapOutcomeAction> failedWith(
      SwapFailureReason reason, {
      SwapFundsMovement movement = SwapFundsMovement.none,
      SwapLiquiditySource source = SwapLiquiditySource.routed,
      String? sourceTx,
      bool retryable = false,
    }) => actionsOf(
      snap(
        source: source,
        fundsMovement: movement,
        evidence: SwapEvidence(executionId: 'swap-1', sourceTxHash: sourceTx),
        outcome: SwapExecutionOutcome(
          kind: SwapOutcomeKind.failed,
          failure: SwapExecutionFailure(
            reason: reason,
            nextStep: SwapNextStep.retry,
            retryable: retryable,
          ),
        ),
      ),
    );

    test('a running swap offers nothing yet', () {
      expect(actionsOf(snap()), isEmpty);
    });

    test('each finished outcome offers its next step', () {
      List<SwapOutcomeAction> ended(SwapOutcomeKind kind) =>
          actionsOf(snap(outcome: SwapExecutionOutcome(kind: kind)));
      expect(actionsOf(snap(outcome: completed())), [
        SwapOutcomeAction.startAnother,
      ]);
      expect(ended(SwapOutcomeKind.partialBelowMinimum), [
        SwapOutcomeAction.startAnother,
        SwapOutcomeAction.contactSupport,
      ]);
      expect(ended(SwapOutcomeKind.refunded), [SwapOutcomeAction.tryAgain]);
      expect(ended(SwapOutcomeKind.cancelled), [SwapOutcomeAction.tryAgain]);
      expect(ended(SwapOutcomeKind.noMatch), [SwapOutcomeAction.tryAgain]);
    });

    test('a token the wallet does not know cannot be swapped onwards', () {
      expect(
        actionsOf(
          snap(
            outcome: SwapExecutionOutcome(
              kind: SwapOutcomeKind.partialOtherToken,
              receivedAmount: d('0.5'),
              receivedSymbol: 'stETH',
            ),
          ),
        ),
        [SwapOutcomeAction.keepToken],
      );
    });

    test('an atomic swap that moved anything goes to Advanced', () {
      for (final movement in [
        SwapFundsMovement.feesOnly,
        SwapFundsMovement.uncertain,
        SwapFundsMovement.sent,
      ]) {
        expect(
          failedWith(
            SwapFailureReason.priceMoved,
            movement: movement,
            source: SwapLiquiditySource.atomic,
          ),
          [SwapOutcomeAction.openAdvanced, SwapOutcomeAction.contactSupport],
        );
      }
      expect(
        failedWith(
          SwapFailureReason.exchangeFailed,
          source: SwapLiquiditySource.atomic,
        ),
        [SwapOutcomeAction.tryAgain],
      );
    });

    test('a price move without a fresh quote can only be retried', () {
      expect(failedWith(SwapFailureReason.priceMoved), [
        SwapOutcomeAction.tryAgain,
      ]);
    });

    test('an unconfirmed swap links its transaction when there is one', () {
      expect(failedWith(SwapFailureReason.notConfirmed, sourceTx: '0xs'), [
        SwapOutcomeAction.viewOnExplorer,
        SwapOutcomeAction.contactSupport,
      ]);
      expect(failedWith(SwapFailureReason.notConfirmed), [
        SwapOutcomeAction.contactSupport,
      ]);
    });

    test('a failed route or an unknown failure goes to support', () {
      for (final reason in [
        SwapFailureReason.routeFailed,
        SwapFailureReason.unknown,
      ]) {
        expect(failedWith(reason), [SwapOutcomeAction.contactSupport]);
      }
      expect(
        actionsOf(
          snap(
            outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.failed),
          ),
        ),
        [SwapOutcomeAction.contactSupport],
      );
    });

    test('a safety check is retried only when it says retrying is sane', () {
      expect(failedWith(SwapFailureReason.safetyCheck, retryable: true), [
        SwapOutcomeAction.tryAgain,
      ]);
      expect(failedWith(SwapFailureReason.safetyCheck), [
        SwapOutcomeAction.contactSupport,
      ]);
    });

    test('a reverted swap is retried first, then looked up', () {
      expect(failedWith(SwapFailureReason.reverted, sourceTx: '0xs'), [
        SwapOutcomeAction.tryAgain,
        SwapOutcomeAction.viewOnExplorer,
      ]);
      expect(failedWith(SwapFailureReason.reverted), [
        SwapOutcomeAction.tryAgain,
      ]);
    });

    test('other failures retry only while the sold amount stayed put', () {
      for (final reason in [
        SwapFailureReason.insufficientBalance,
        SwapFailureReason.approvalFailed,
        SwapFailureReason.walletRejected,
        SwapFailureReason.quoteUnavailable,
        SwapFailureReason.restarted,
        SwapFailureReason.exchangeFailed,
        SwapFailureReason.internal,
      ]) {
        for (final movement in [
          SwapFundsMovement.none,
          SwapFundsMovement.feesOnly,
        ]) {
          expect(
            failedWith(reason, movement: movement),
            [SwapOutcomeAction.tryAgain],
            reason: '${reason.name} ${movement.name}',
          );
        }
        for (final movement in [
          SwapFundsMovement.uncertain,
          SwapFundsMovement.sent,
        ]) {
          expect(
            failedWith(reason, movement: movement),
            [SwapOutcomeAction.contactSupport],
            reason: '${reason.name} ${movement.name}',
          );
        }
      }
    });
  });

  group('swap support payload', () {
    useEnglishCopy();

    final full = snap(
      id: 'swap-9',
      outcome: failed(SwapFailureReason.routeFailed),
      createdAt: DateTime.utc(2026, 9, 25, 10),
      updatedAt: DateTime.utc(2026, 9, 25, 10, 5, 30),
      evidence: const SwapEvidence(
        executionId: 'swap-9',
        approvalTxHashes: ['0xreset', '0xapprove'],
        sourceTxHash: '0xsource',
        destinationTxHash: '0xdestination',
        providerRequestId: 'req-7',
        providerStatus: 'PENDING',
        rawState: 'Bridging',
        errorType: 'BridgeFailed',
        diagnostic: 'aggregator/bridge',
        providerExplorerUrl: 'https://example.invalid/tx',
      ),
    );

    test('a running swap hands over its id, route and status', () {
      expect(
        copyOf(snap()).supportPayload(),
        'Swap ID: swap-1\n'
        'Route: 1 ETH → 3,000 USDC\n'
        'Status: Confirming on Ethereum',
      );
    });

    test('a finished swap hands over every id, hash and time it has', () {
      final lines = copyOf(full).supportPayload().split('\n');
      expect(lines.take(2), ['Swap ID: swap-9', 'Route: 1 ETH → 3,000 USDC']);
      expect(lines[2], endsWith(': Gleec support is needed'));
      expect(lines.skip(3), [
        'Started: 2026-09-25T10:00:00.000Z',
        'Last update: 2026-09-25T10:05:30.000Z',
        'Approval transactions: 0xreset',
        'Approval transactions: 0xapprove',
        'Source transaction: 0xsource',
        'Destination transaction: 0xdestination',
        'Support reference: req-7',
        'state: Bridging',
        'error: BridgeFailed',
        'route: aggregator/bridge',
        'route_status: PENDING',
      ]);
    });

    test('times are written in UTC', () {
      final payload = copyOf(
        snap(createdAt: DateTime(2026, 9, 25, 12)),
      ).supportPayload();
      final started = DateTime(2026, 9, 25, 12).toUtc().toIso8601String();
      expect(payload, contains('Started: $started'));
      expect(started, endsWith('Z'));
    });

    test('addresses and links are never part of it', () {
      final payload = copyOf(full).supportPayload();
      expect(payload, isNot(contains(swapAddress)));
      expect(payload, isNot(contains('https://')));
    });

    test("a finished swap's status is not labelled as in progress", () {
      final lines = copyOf(full).supportPayload().split('\n');
      expect(lines[2], isNot(startsWith('In progress')));
    });
  });
}
