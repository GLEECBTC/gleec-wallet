import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Copy that says only what is known: an hour in the singular, a neutral
/// status for support, names for assets the wallet does not know, no
/// invented minimum, and fees that were spent always said so.
void main() {
  final networks = SwapNetworks([eth, usdc, btc, gleec]);
  SwapExecutionCopy copyOf(SwapExecutionSnapshot snapshot) =>
      SwapExecutionCopy(snapshot, networks);

  const unchanged = 'Your balance is unchanged.';
  const feesSpent = "Your ETH didn't leave. Network fees were spent.";
  const feesOnlyHero =
      "Nothing was swapped. Your ETH didn't leave; network fees were spent.";
  const uncertainHero =
      "We can't confirm whether the transaction was sent. Check the explorer "
      'before trying again.';
  const unverified =
      "Last confirmed location: 1 ETH on Ethereum. The current location isn't "
      'verified yet.';

  group('swap copy fixes', () {
    useEnglishCopy();

    test('an hour and a little more reads as one hour', () {
      String of(int seconds) => SwapFormat.duration(Duration(seconds: seconds));
      expect(of(3600), 'About 1 hour');
      expect(of(3779), 'About 1 hour');
      expect(of(3780), 'About 1.1 hours');
      expect(of(7200), 'About 2 hours');
    });

    test('the support hand-off labels any status neutrally', () {
      String statusOf(SwapExecutionSnapshot snapshot) =>
          copyOf(snapshot).supportPayload().split('\n')[2];
      expect(statusOf(snap()), 'Status: Confirming on Ethereum');
      expect(statusOf(snap(outcome: completed())), 'Status: Received');
      expect(
        statusOf(snap(outcome: failed(SwapFailureReason.routeFailed))),
        'Status: Gleec support is needed',
      );
    });

    group('timeline names', () {
      List<(String, String)> stepsOf(SwapExecutionSnapshot snapshot) => [
        for (final step in SwapTimeline.of(snapshot, networks))
          (step.title, step.detail),
      ];

      SwapExecutionSnapshot unknown({
        SwapLiquiditySource source = SwapLiquiditySource.routed,
        SwapRouteKind routeKind = SwapRouteKind.sameChain,
        SwapExecutionOutcome? outcome,
      }) => snap(
        source: source,
        routeKind: routeKind,
        outcome: outcome,
        stages: const [],
        from: null,
        fromTicker: 'WBTC',
        to: null,
        toTicker: 'XYZ',
      );

      test('a swap without stages names unknown assets by their tickers', () {
        expect(stepsOf(unknown()), [
          ('Preparing', 'Checking the latest details'),
          ('Sending on WBTC', 'Source transaction'),
          ('Converting asset', 'On XYZ'),
          ('Receive XYZ', '3,000 XYZ at 0x5520…7B91 on XYZ'),
        ]);
        expect(stepsOf(unknown(routeKind: SwapRouteKind.crossChain))[2], (
          'Moving to XYZ',
          'Destination tracking',
        ));
        expect(stepsOf(unknown(source: SwapLiquiditySource.atomic))[2], (
          'Exchanging asset',
          'Peer-to-peer exchange',
        ));
      });

      test('what arrived is named by the recorded ticker too', () {
        final steps = stepsOf(
          unknown(
            outcome: SwapExecutionOutcome(
              kind: SwapOutcomeKind.completed,
              receivedAmount: d('2'),
            ),
          ),
        );
        expect(steps.last, ('Received', '2 XYZ at 0x5520…7B91 on XYZ'));
      });

      test('a stage that names nothing takes its side of the swap', () {
        final steps = stepsOf(
          snap(
            stages: const [
              SwapRouteStage(kind: SwapRouteStageKind.resetApproval),
              SwapRouteStage(kind: SwapRouteStageKind.approve),
              SwapRouteStage(kind: SwapRouteStageKind.send),
              SwapRouteStage(kind: SwapRouteStageKind.bridge),
              SwapRouteStage(kind: SwapRouteStageKind.receive),
            ],
          ),
        );
        expect(steps, [
          (
            'Resetting permission',
            'Setting the current ETH permission to zero',
          ),
          ('Approving ETH', 'Exact amount only'),
          ('Sending on Ethereum', 'Source transaction'),
          ('Moving to Ethereum', 'Destination tracking'),
          ('Receive USDC', '3,000 USDC at 0x5520…7B91 on Ethereum'),
        ]);
      });
    });

    test('a minimum that is not known is never shown as a figure', () {
      for (final maximum in ['5', null]) {
        final copy = SwapFailureCopy.of(
          SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.belowMinimum,
            maximum: maximum == null ? null : d(maximum),
          ),
          eth,
        );
        expect(copy.message, 'This amount is below the swap minimum.');
        expect(copy.action, SwapEntryAction.none);
        expect(copy.detail, isNull);
      }
    });

    group('a failure that spent only fees', () {
      test('says so in the headline, as where the funds are does', () {
        for (final reason in [
          SwapFailureReason.walletRejected,
          SwapFailureReason.safetyCheck,
          SwapFailureReason.quoteUnavailable,
          SwapFailureReason.restarted,
          SwapFailureReason.internal,
        ]) {
          final copy = copyOf(
            snap(
              fundsMovement: SwapFundsMovement.feesOnly,
              outcome: failed(reason),
            ),
          );
          expect(copy.hero.body, feesOnlyHero, reason: reason.name);
          expect(copy.fundsLocation, feesSpent, reason: reason.name);
        }
      });

      test('names a sold asset the wallet does not know by its ticker', () {
        final copy = copyOf(
          snap(
            from: null,
            fromTicker: 'WBTC',
            fundsMovement: SwapFundsMovement.feesOnly,
            outcome: failed(SwapFailureReason.internal),
          ),
        );
        expect(
          copy.hero.body,
          "Nothing was swapped. Your WBTC didn't leave; network fees were "
          'spent.',
        );
      });

      test('a short balance without figures answers from the funds too', () {
        String bodyOf(SwapFundsMovement movement) => copyOf(
          snap(
            fundsMovement: movement,
            outcome: const SwapExecutionOutcome(
              kind: SwapOutcomeKind.failed,
              failure: SwapExecutionFailure(
                reason: SwapFailureReason.insufficientBalance,
                nextStep: SwapNextStep.fixAndRetry,
              ),
            ),
          ),
        ).hero.body!;
        expect(bodyOf(SwapFundsMovement.none), unchanged);
        expect(bodyOf(SwapFundsMovement.feesOnly), feesOnlyHero);
        expect(bodyOf(SwapFundsMovement.uncertain), uncertainHero);
        expect(bodyOf(SwapFundsMovement.sent), uncertainHero);
      });

      test('an approval on record is fees spent, whatever the engine said', () {
        final copy = copyOf(
          snap(
            fundsMovement: SwapFundsMovement.none,
            evidence: const SwapEvidence(
              executionId: 'swap-1',
              approvalTxHashes: ['0xapprove'],
            ),
            outcome: failed(SwapFailureReason.internal),
          ),
        );
        expect(copy.hero.body, feesOnlyHero);
        expect(copy.fundsLocation, feesSpent);
      });
    });

    group('a swap that stopped before it was sent', () {
      String where({
        SwapOutcomeKind kind = SwapOutcomeKind.cancelled,
        SwapFundsMovement movement = SwapFundsMovement.none,
        bool approvalRemains = false,
        List<String> approvals = const [],
        List<SwapGasSpent> gas = const [],
      }) => copyOf(
        snap(
          fundsMovement: movement,
          approvalRemains: approvalRemains,
          evidence: SwapEvidence(
            executionId: 'swap-1',
            approvalTxHashes: approvals,
            gasSpent: gas,
          ),
          outcome: SwapExecutionOutcome(kind: kind),
        ),
      ).fundsLocation;
      final gas = [SwapGasSpent(ticker: 'ETH', amount: d('0.001'))];

      test('is unchanged only while no fee is on record', () {
        for (final kind in [
          SwapOutcomeKind.cancelled,
          SwapOutcomeKind.noMatch,
        ]) {
          expect(where(kind: kind), unchanged, reason: kind.name);
          expect(
            where(kind: kind, gas: gas),
            feesSpent,
            reason: kind.name,
          );
        }
      });

      test('says fees were spent once an approval was paid for', () {
        expect(where(movement: SwapFundsMovement.feesOnly), feesSpent);
        expect(where(approvals: ['0xapprove']), feesSpent);
        expect(
          where(approvalRemains: true),
          '$feesSpent An exact permission for 1 ETH remains on-chain.',
        );
      });

      test('never calls the balance unchanged when funds may have moved', () {
        for (final movement in [
          SwapFundsMovement.uncertain,
          SwapFundsMovement.sent,
        ]) {
          expect(where(movement: movement), unverified, reason: movement.name);
        }
      });
    });
  });
}
