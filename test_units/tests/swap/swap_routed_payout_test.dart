import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/swap_analytics.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers payouts KDF measures on-chain and those it can only take from the
/// provider's report (KDF 667045c), and a gas estimate that fails while a
/// swap starts: what the user is told arrived, and why a swap stopped.
void main() {
  SwapExecutionSnapshot map(RoutedSwapProgress progress) =>
      routedSnapshotFrom(progress, networks: execNetworks);

  RoutedSwapProgress finished(RoutedSwapReceipt receipt) =>
      progressOf(phase: RoutedSwapPhase.finished, receipt: receipt);

  final reported = RoutedSwapReportedAmount(amount: d('2991'), assetId: usdc);

  group('a finished routed swap', () {
    test('a measured payout is what arrived, as measured', () {
      final outcome = map(
        finished(
          RoutedSwapReceipt(
            outcome: RoutedSwapOutcome.completed,
            amount: d('2990'),
            assetId: usdc,
            reported: reported,
          ),
        ),
      ).outcome!;
      expect(outcome.kind, SwapOutcomeKind.completed);
      expect(outcome.receivedAmount, d('2990'));
      expect(outcome.receivedAsset, usdc);
      expect(outcome.receivedReported, isFalse);
    });

    test('a payout KDF could not measure is the report, marked as one', () {
      final outcome = map(
        finished(
          RoutedSwapReceipt(
            outcome: RoutedSwapOutcome.completed,
            reported: reported,
          ),
        ),
      ).outcome!;
      expect(outcome.kind, SwapOutcomeKind.completed);
      expect(outcome.receivedAmount, d('2991'));
      expect(outcome.receivedAsset, usdc);
      expect(outcome.receivedSymbol, isNull);
      expect(outcome.receivedReported, isTrue);
    });

    test('a reported provider symbol is shown, never resolved', () {
      final outcome = map(
        finished(
          RoutedSwapReceipt(
            outcome: RoutedSwapOutcome.partial,
            partialReason: RoutedSwapPartialReason.intermediateToken,
            reported: RoutedSwapReportedAmount(
              amount: d('2991'),
              symbol: 'axlUSDC',
            ),
          ),
        ),
      ).outcome!;
      expect(outcome.kind, SwapOutcomeKind.partialOtherToken);
      expect(outcome.receivedAsset, isNull);
      expect(outcome.receivedSymbol, 'axlUSDC');
      expect(outcome.receivedReported, isTrue);
    });

    test('with neither amount, nothing is claimed to have arrived', () {
      final snapshot = map(
        finished(const RoutedSwapReceipt(outcome: RoutedSwapOutcome.completed)),
      );
      expect(snapshot.outcome!.receivedAmount, isNull);
      expect(snapshot.outcome!.receivedReported, isFalse);
      expect(snapshot.isSuccess, isTrue);
      expect(snapshot.fundsMovement, SwapFundsMovement.sent);
    });
  });

  group('a gas estimate that failed at start', () {
    test('is its own reason, worth another try', () {
      final failure = map(
        progressOf(
          phase: RoutedSwapPhase.failed,
          failure: failureOf(
            RoutedSwapFailureKind.gasEstimationFailed,
            errorType: 'GasEstimationFailed',
          ),
        ),
      ).outcome!.failure!;
      expect(failure.reason, SwapFailureReason.networkFee);
      expect(failure.nextStep, SwapNextStep.retry);
      expect(failure.retryable, isTrue);
      expect(SwapAnalyticsReporter.failureCategory(failure.reason), 'network_fee');
    });
  });

  group('copy', () {
    useEnglishCopy();
    final networks = SwapNetworks([eth, usdc, btc, gleec]);
    SwapHeroCopy heroOf(SwapExecutionSnapshot snapshot) =>
        SwapExecutionCopy(snapshot, networks).hero;

    test('a reported payout says whose figure it is', () {
      final hero = heroOf(
        snap(
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.completed,
            receivedAmount: d('2991.129'),
            receivedAsset: usdc,
            receivedReported: true,
          ),
        ),
      );
      expect(hero.title, 'You received 2,991.12 USDC as reported by LI.FI');
      expect(hero.tone, SwapTone.success);
    });

    test('a measured payout needs no qualifier', () {
      final hero = heroOf(
        snap(
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.completed,
            receivedAmount: d('2990'),
            receivedAsset: usdc,
          ),
        ),
      );
      expect(hero.title, 'You received 2,990 USDC');
    });

    test('a short reported payout names the report in the body', () {
      final hero = heroOf(
        snap(
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.partialBelowMinimum,
            receivedAmount: d('2900'),
            receivedAsset: usdc,
            receivedReported: true,
          ),
        ),
      );
      expect(
        hero.body,
        'The swap completed with 2,900 USDC as reported by LI.FI, below the '
        'minimum of 2,985 USDC.',
      );
    });

    test('a failed fee estimate says nothing was sent, on which network', () {
      final hero = heroOf(
        snap(
          fundsMovement: SwapFundsMovement.none,
          outcome: const SwapExecutionOutcome(
            kind: SwapOutcomeKind.failed,
            failure: SwapExecutionFailure(
              reason: SwapFailureReason.networkFee,
              nextStep: SwapNextStep.retry,
            ),
          ),
        ),
      );
      expect(hero.title, "The network fee couldn't be worked out");
      expect(
        hero.body,
        "Ethereum didn't give a fee estimate, so nothing was sent. Try again "
        'in a moment.',
      );
      expect(hero.icon, Icons.local_gas_station_outlined);
      expect(hero.tone, SwapTone.warning);
    });

    test('after an approval, it says what the approval cost', () {
      final hero = heroOf(
        snap(
          fundsMovement: SwapFundsMovement.feesOnly,
          outcome: const SwapExecutionOutcome(
            kind: SwapOutcomeKind.failed,
            failure: SwapExecutionFailure(
              reason: SwapFailureReason.networkFee,
              nextStep: SwapNextStep.retry,
            ),
          ),
        ),
      );
      expect(
        hero.body,
        "Nothing was swapped. Your ETH didn't leave; network fees were spent.",
      );
    });
  });
}
