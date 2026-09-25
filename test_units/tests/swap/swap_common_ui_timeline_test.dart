import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_timeline.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The steps a swap shows: which one it is on, where it stopped, and what
/// each step says.
void main() {
  final networks = SwapNetworks([eth, usdc, btc, gleec]);
  const done = SwapStepStatus.done;
  const current = SwapStepStatus.current;
  const error = SwapStepStatus.error;
  const cancelled = SwapStepStatus.cancelled;
  const waiting = SwapStepStatus.notStarted;

  const prepare = SwapRouteStage(kind: SwapRouteStageKind.prepare);
  final reset = SwapRouteStage(
    kind: SwapRouteStageKind.resetApproval,
    asset: usdc,
  );
  final approve = SwapRouteStage(kind: SwapRouteStageKind.approve, asset: usdc);
  final send = SwapRouteStage(kind: SwapRouteStageKind.send, asset: usdc);
  final bridge = SwapRouteStage(
    kind: SwapRouteStageKind.bridge,
    network: 'Base',
    asset: eth,
  );
  final receive = SwapRouteStage(kind: SwapRouteStageKind.receive, asset: eth);
  final full = [prepare, reset, approve, send, bridge, receive];
  const approvalTx = SwapEvidence(
    executionId: 'swap-1',
    approvalTxHashes: ['0xapprove'],
  );

  List<SwapTimelineStep> stepsOf(SwapExecutionSnapshot snapshot) =>
      SwapTimeline.of(snapshot, networks);
  List<SwapStepStatus> statuses(SwapExecutionSnapshot snapshot) => [
    for (final step in stepsOf(snapshot)) step.status,
  ];

  group('swap timeline', () {
    useEnglishCopy();

    group('without route stages', () {
      List<String> titles(SwapExecutionSnapshot snapshot) => [
        for (final step in stepsOf(snapshot)) step.title,
      ];

      test('a same-network route converts', () {
        expect(titles(snap(stages: const [])), [
          'Preparing',
          'Sending on Ethereum',
          'Converting asset',
          'Receive USDC',
        ]);
      });

      test('a cross-network route bridges', () {
        expect(
          titles(snap(stages: const [], routeKind: SwapRouteKind.crossChain)),
          [
            'Preparing',
            'Sending on Ethereum',
            'Moving to Ethereum',
            'Receive USDC',
          ],
        );
      });

      test('a peer-to-peer swap exchanges', () {
        expect(
          titles(snap(stages: const [], source: SwapLiquiditySource.atomic)),
          [
            'Preparing',
            'Sending on Ethereum',
            'Exchanging asset',
            'Receive USDC',
          ],
        );
      });
    });

    group('while running', () {
      List<SwapStepStatus> at(
        SwapProgressStage? stage, {
        List<SwapRouteStage>? stages,
        SwapFundsMovement movement = SwapFundsMovement.sent,
        SwapApprovalRequirement? approval,
        SwapEvidence? evidence,
      }) => statuses(
        snap(
          stage: stage,
          stages: stages ?? full,
          fundsMovement: movement,
          approval: approval,
          evidence: evidence,
        ),
      );

      List<SwapStepStatus> currentAt(int index, [int count = 6]) => [
        for (var i = 0; i < count; i++)
          i < index
              ? done
              : i == index
              ? current
              : waiting,
      ];

      test('preparing, matching and signing sit on the first step', () {
        for (final stage in [
          SwapProgressStage.preparing,
          SwapProgressStage.matching,
          SwapProgressStage.signing,
          null,
        ]) {
          expect(at(stage), currentAt(0), reason: '$stage');
        }
      });

      test('approving sits on the reset only until it went out', () {
        final resetting = SwapApprovalRequirement(
          asset: usdc,
          exactAmount: d('1250'),
          resetsFirst: true,
        );
        expect(
          at(SwapProgressStage.approving, approval: resetting),
          currentAt(1),
        );
        expect(
          at(
            SwapProgressStage.approving,
            approval: resetting,
            evidence: approvalTx,
          ),
          currentAt(2),
        );
        expect(at(SwapProgressStage.approving), currentAt(2));
      });

      test('a route without the step falls back to the first', () {
        expect(
          at(SwapProgressStage.approving, stages: [prepare, send, receive]),
          currentAt(0, 3),
        );
      });

      test('sending and confirming sit on the send', () {
        expect(at(SwapProgressStage.sending), currentAt(3));
        expect(at(SwapProgressStage.confirming), currentAt(3));
      });

      test('delivery stages sit on the step after the send', () {
        for (final stage in [
          SwapProgressStage.bridging,
          SwapProgressStage.awaitingDelivery,
          SwapProgressStage.refunding,
          SwapProgressStage.actionRequired,
        ]) {
          expect(at(stage), currentAt(4), reason: stage.name);
        }
        expect(
          at(SwapProgressStage.bridging, stages: [prepare, send, receive]),
          currentAt(2, 3),
        );
      });

      test('exchanging sits on the exchange', () {
        final stages = [
          prepare,
          send,
          const SwapRouteStage(kind: SwapRouteStageKind.exchange),
          receive,
        ];
        expect(
          at(SwapProgressStage.exchanging, stages: stages),
          currentAt(2, 4),
        );
      });

      test('an unknown stage sits after the send only once funds left', () {
        expect(at(SwapProgressStage.unknown), currentAt(4));
        expect(
          at(SwapProgressStage.unknown, movement: SwapFundsMovement.uncertain),
          currentAt(3),
        );
      });
    });

    group('once finished', () {
      List<SwapStepStatus> ended(
        SwapExecutionOutcome outcome, {
        List<SwapRouteStage>? stages,
        SwapFundsMovement movement = SwapFundsMovement.none,
        SwapEvidence? evidence,
      }) => statuses(
        snap(
          outcome: outcome,
          stages: stages ?? full,
          fundsMovement: movement,
          evidence: evidence,
        ),
      );

      test('a delivery of any kind completes every step', () {
        for (final kind in [
          SwapOutcomeKind.completed,
          SwapOutcomeKind.partialBelowMinimum,
          SwapOutcomeKind.partialOtherToken,
        ]) {
          expect(
            ended(SwapExecutionOutcome(kind: kind)),
            everyElement(done),
            reason: kind.name,
          );
        }
      });

      test('a stop before approving marks the first step', () {
        for (final kind in [
          SwapOutcomeKind.cancelled,
          SwapOutcomeKind.noMatch,
        ]) {
          expect(ended(SwapExecutionOutcome(kind: kind)), [
            cancelled,
            waiting,
            waiting,
            waiting,
            waiting,
            waiting,
          ]);
        }
      });

      test('a stop after approving marks the send', () {
        expect(
          ended(
            const SwapExecutionOutcome(kind: SwapOutcomeKind.cancelled),
            evidence: approvalTx,
          ),
          [done, done, done, cancelled, waiting, waiting],
        );
      });

      test('a refund stops just after the send, within the route', () {
        const refunded = SwapExecutionOutcome(kind: SwapOutcomeKind.refunded);
        expect(ended(refunded), [done, done, done, done, cancelled, waiting]);
        expect(ended(refunded, stages: [prepare, send]), [done, cancelled]);
      });

      test('a failed permission marks the approval step', () {
        final outcome = failed(SwapFailureReason.approvalFailed);
        expect(ended(outcome), [done, done, error, waiting, waiting, waiting]);
        expect(ended(outcome, stages: [prepare, reset, send]), [
          done,
          error,
          waiting,
        ]);
        expect(ended(outcome, stages: [prepare, send]), [error, waiting]);
      });

      test('other failures stop where the funds did', () {
        final outcome = failed(SwapFailureReason.internal);
        expect(ended(outcome, movement: SwapFundsMovement.sent), [
          done,
          done,
          done,
          done,
          error,
          waiting,
        ]);
        expect(
          ended(
            outcome,
            stages: [prepare, send],
            movement: SwapFundsMovement.sent,
          ),
          [done, error],
        );
        expect(ended(outcome), [
          error,
          waiting,
          waiting,
          waiting,
          waiting,
          waiting,
        ]);
        expect(ended(outcome, evidence: approvalTx), [
          done,
          done,
          done,
          error,
          waiting,
          waiting,
        ]);
        for (final movement in [
          SwapFundsMovement.feesOnly,
          SwapFundsMovement.uncertain,
        ]) {
          expect(ended(outcome, movement: movement), [
            done,
            done,
            done,
            error,
            waiting,
            waiting,
          ]);
        }
      });
    });

    group('step words', () {
      test('each step names its asset or network', () {
        final steps = stepsOf(snap(stages: full));
        expect(
          [for (final step in steps) step.title],
          [
            'Preparing',
            'Resetting permission',
            'Approving USDC',
            'Sending on Ethereum',
            'Moving to Base',
            'Receive ETH',
          ],
        );
        expect(
          [for (final step in steps) step.detail],
          [
            'Checking the latest details',
            'Setting the current USDC permission to zero',
            'Exact amount only',
            'Source transaction',
            'Destination tracking',
            '3,000 ETH at 0x5520…7B91 on Ethereum',
          ],
        );
      });

      test('the receive step reads as received once done', () {
        final steps = stepsOf(snap(outcome: completed(amount: '3001.129')));
        expect(steps.last.title, 'Received');
        expect(steps.last.detail, '3,001.12 USDC at 0x5520…7B91 on Ethereum');
      });

      test("a route's own network names beat the assets'", () {
        final steps = stepsOf(
          snap(
            toAddress: null,
            stages: [
              SwapRouteStage(
                kind: SwapRouteStageKind.send,
                asset: eth,
                network: 'Mainnet',
              ),
              SwapRouteStage(
                kind: SwapRouteStageKind.convert,
                asset: usdc,
                network: 'Base',
              ),
              SwapRouteStage(
                kind: SwapRouteStageKind.receive,
                asset: usdc,
                network: 'Arbitrum',
              ),
              const SwapRouteStage(kind: SwapRouteStageKind.exchange),
            ],
          ),
        );
        expect(steps[0].title, 'Sending on Mainnet');
        expect(steps[1].title, 'Converting asset');
        expect(steps[1].detail, 'On Base');
        expect(steps[2].detail, '3,000 USDC on Arbitrum');
        expect(steps[3].title, 'Exchanging asset');
        expect(steps[3].detail, 'Peer-to-peer exchange');
      });

      test('a swap of assets the wallet does not know still names them', () {
        final steps = stepsOf(
          snap(
            stages: const [],
            from: null,
            fromTicker: 'WBTC',
            to: null,
            toTicker: 'XYZ',
          ),
        );
        expect(steps[1].title, isNot('Sending on '));
        expect(steps.last.title, 'Receive XYZ');
      });

      test('the receive step shows the best-known amount, rounded down', () {
        String receiveDetail(SwapExecutionSnapshot snapshot) =>
            stepsOf(snapshot).last.detail;
        expect(
          receiveDetail(snap(expected: '3000.129')),
          '3,000.12 USDC at 0x5520…7B91 on Ethereum',
        );
        expect(
          receiveDetail(snap(expected: null)),
          '2,985 USDC at 0x5520…7B91 on Ethereum',
        );
        expect(
          receiveDetail(snap(expected: null, minimum: null)),
          'USDC at 0x5520…7B91 on Ethereum',
        );
      });

      test('the receive step names what actually arrived', () {
        String arrived(SwapExecutionOutcome outcome) =>
            stepsOf(snap(outcome: outcome)).last.detail;
        expect(
          arrived(
            SwapExecutionOutcome(
              kind: SwapOutcomeKind.partialOtherToken,
              receivedAmount: d('0.51'),
              receivedSymbol: 'stETH',
            ),
          ),
          '0.51 stETH at 0x5520…7B91 on Ethereum',
        );
        expect(
          arrived(
            SwapExecutionOutcome(
              kind: SwapOutcomeKind.completed,
              receivedAmount: d('2'),
            ),
          ),
          '2 USDC at 0x5520…7B91 on Ethereum',
        );
      });
    });

    test('a quote describes its steps, none received yet', () {
      final quote = quoteOf(from: usdc, to: eth, stages: full);
      expect(SwapTimeline.describe(quote, networks), [
        'Preparing',
        'Resetting permission',
        'Approving USDC',
        'Sending on Ethereum',
        'Moving to Base',
        'Receive ETH',
      ]);
    });

    test('a step keeps its title, detail and status', () {
      const step = SwapTimelineStep(
        title: 'Preparing',
        detail: 'Checking the latest details',
        status: SwapStepStatus.current,
      );
      expect(step.title, 'Preparing');
      expect(step.detail, 'Checking the latest details');
      expect(step.status, SwapStepStatus.current);
    });
  });
}
