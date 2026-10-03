import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';

import 'swap_test_fixtures.dart';

/// Covers the words and numbers people commit money against.
///
/// Without a loaded translation, copy renders as its key, so these assert
/// which message was chosen rather than its English.
void main() {
  final networks = SwapNetworks([eth, usdc, btc, gleec]);

  group('numbers never promise more than the swap delivers', () {
    test('receive amounts round down, costs round up', () {
      expect(
        SwapFormat.amount(d('3207.189'), rounding: SwapRounding.down),
        '3,207.18',
      );
      expect(
        SwapFormat.amount(d('3207.181'), rounding: SwapRounding.up),
        '3,207.19',
      );
      expect(SwapFormat.usd(d('8.741'), rounding: SwapRounding.up), r'$8.75');
      expect(
        SwapFormat.usd(d('3219.428'), rounding: SwapRounding.down),
        r'$3,219.42',
      );
    });

    test('precision follows magnitude', () {
      expect(SwapFormat.amount(d('2.48123456')), '2.4812');
      expect(SwapFormat.amount(d('0.0180849')), '0.01808');
      expect(SwapFormat.amount(d('1250')), '1,250');
      expect(SwapFormat.amount(d('0')), '0');
    });

    test('dust is shown as dust, never as zero', () {
      expect(SwapFormat.usd(d('0.004')), r'< $0.01');
      expect(
        SwapFormat.amount(d('0.000000001'), rounding: SwapRounding.down),
        startsWith('<'),
      );
    });

    test('percent and short identifiers', () {
      expect(SwapFormat.percent(d('0.052')), '5.2%');
      expect(
        SwapFormat.short('0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91'),
        '0x5520…7B91',
      );
      expect(SwapFormat.short('short'), 'short');
    });
  });

  group('timeline', () {
    List<SwapStepStatus> statuses(SwapExecutionSnapshot snapshot) => [
      for (final step in SwapTimeline.of(snapshot, networks)) step.status,
    ];

    test('marks the current step while running', () {
      expect(statuses(snapshotOf(stage: SwapProgressStage.confirming)), [
        SwapStepStatus.done,
        SwapStepStatus.current,
        SwapStepStatus.notStarted,
      ]);
    });

    test('marks every step done once completed', () {
      expect(
        statuses(snapshotOf(outcome: completed())),
        everyElement(SwapStepStatus.done),
      );
    });

    test('places a failure after the funds left beyond the send', () {
      expect(
        statuses(
          snapshotOf(
            fundsMovement: SwapFundsMovement.sent,
            outcome: failed(SwapFailureReason.routeFailed),
          ),
        ),
        [SwapStepStatus.done, SwapStepStatus.done, SwapStepStatus.error],
      );
    });

    test('a cancellation stops at the first step', () {
      expect(
        statuses(
          snapshotOf(
            fundsMovement: SwapFundsMovement.none,
            outcome: const SwapExecutionOutcome(
              kind: SwapOutcomeKind.cancelled,
            ),
          ),
        ),
        [
          SwapStepStatus.cancelled,
          SwapStepStatus.notStarted,
          SwapStepStatus.notStarted,
        ],
      );
    });

    test('resetting a permission is shown before the approval', () {
      final approval = SwapApprovalRequirement(
        asset: usdc,
        exactAmount: d('1250'),
        resetsFirst: true,
      );
      final steps = [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
        SwapRouteStage(kind: SwapRouteStageKind.resetApproval, asset: usdc),
        SwapRouteStage(kind: SwapRouteStageKind.approve, asset: usdc),
        SwapRouteStage(kind: SwapRouteStageKind.send, asset: usdc),
        SwapRouteStage(kind: SwapRouteStageKind.receive, asset: eth),
      ];
      expect(
        statuses(
          snapshotOf(
            stage: SwapProgressStage.approving,
            approval: approval,
            stages: steps,
          ),
        ).indexOf(SwapStepStatus.current),
        1,
      );
      expect(
        statuses(
          snapshotOf(
            stage: SwapProgressStage.approving,
            approval: approval,
            approvalTxHashes: const ['0xreset'],
            stages: steps,
          ),
        ).indexOf(SwapStepStatus.current),
        2,
      );
    });
  });

  group('recovery copy', () {
    SwapExecutionCopy copyOf(SwapExecutionSnapshot snapshot) =>
        SwapExecutionCopy(snapshot, networks);

    test('never says nothing was sent when funds may have moved', () {
      final copy = copyOf(
        snapshotOf(
          fundsMovement: SwapFundsMovement.uncertain,
          outcome: failed(SwapFailureReason.internal),
        ),
      );
      expect(copy.hero.body, LocaleKeys.swapFailUncertainBody);
      expect(copy.fundsLocation, LocaleKeys.swapFundsUncertain);
    });

    test('says so when nothing moved', () {
      final copy = copyOf(
        snapshotOf(
          fundsMovement: SwapFundsMovement.none,
          outcome: failed(SwapFailureReason.internal),
        ),
      );
      expect(copy.hero.body, LocaleKeys.swapFailInternalBody);
      expect(copy.fundsLocation, LocaleKeys.swapFundsUnchanged);
    });

    test('mentions a permission left on-chain', () {
      final copy = copyOf(
        snapshotOf(
          fundsMovement: SwapFundsMovement.feesOnly,
          approvalRemains: true,
          outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
        ),
      );
      expect(
        copy.fundsLocation,
        contains(LocaleKeys.swapFundsPermissionRemains),
      );
    });

    test('a price move offers the fresh quote for consent', () {
      final copy = copyOf(
        snapshotOf(
          fundsMovement: SwapFundsMovement.none,
          outcome: failed(
            SwapFailureReason.priceMoved,
            freshQuote: quoteOf(guaranteed: '2950'),
          ),
        ),
      );
      expect(copy.actions, [
        SwapOutcomeAction.acceptFreshQuote,
        SwapOutcomeAction.tryAgain,
      ]);
      expect(copy.priceMoveComparison, isNotNull);
    });

    test('a different token received offers a follow-up swap', () {
      final copy = copyOf(
        snapshotOf(
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.partialOtherToken,
            receivedAmount: d('3206.87'),
            receivedAsset: eth,
          ),
        ),
      );
      expect(copy.actions, [
        SwapOutcomeAction.followUp,
        SwapOutcomeAction.keepToken,
      ]);
    });

    test('an atomic swap that failed after paying goes to Advanced', () {
      final copy = copyOf(
        snapshotOf(
          source: SwapLiquiditySource.atomic,
          routeKind: SwapRouteKind.direct,
          fundsMovement: SwapFundsMovement.uncertain,
          outcome: failed(SwapFailureReason.exchangeFailed),
        ),
      );
      expect(copy.actions.first, SwapOutcomeAction.openAdvanced);
    });

    test('the support hand-off carries ids and hashes, not addresses', () {
      final snapshot = snapshotOf(
        sourceTxHash: '0xsource',
        outcome: failed(SwapFailureReason.routeFailed),
      );
      final payload = copyOf(snapshot).supportPayload();
      expect(payload, contains(snapshot.id));
      expect(payload, contains('0xsource'));
      expect(payload, isNot(contains(snapshot.fromAddress)));
    });
  });
}
