import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// What a swap is called while it runs: its tickers, networks, amounts and
/// the status hero for each stage.
void main() {
  final networks = SwapNetworks([eth, usdc, btc, gleec]);
  SwapExecutionCopy copyOf(SwapExecutionSnapshot snapshot) =>
      SwapExecutionCopy(snapshot, networks);

  group('swap execution copy', () {
    useEnglishCopy();

    group('names', () {
      test('a wallet asset goes by its ticker, not its config id', () {
        final copy = copyOf(snap());
        expect(copy.fromTicker, 'ETH');
        expect(copy.toTicker, 'USDC');
      });

      test('an asset the wallet does not know keeps the recorded ticker', () {
        final copy = copyOf(
          snap(from: null, fromTicker: 'WBTC', to: null, toTicker: 'XYZ'),
        );
        expect(copy.fromTicker, 'WBTC');
        expect(copy.toTicker, 'XYZ');
      });

      test('the route names the networks before the assets do', () {
        final copy = copyOf(
          snap(
            stages: [
              SwapRouteStage(
                kind: SwapRouteStageKind.send,
                asset: eth,
                network: 'Mainnet',
              ),
              const SwapRouteStage(
                kind: SwapRouteStageKind.bridge,
                network: 'Base',
              ),
              SwapRouteStage(kind: SwapRouteStageKind.receive, asset: usdc),
            ],
          ),
        );
        expect(copy.fromNetwork, 'Mainnet');
        expect(copy.toNetwork, 'Base');
      });

      test('the last naming stage wins, and an empty name is skipped', () {
        final copy = copyOf(
          snap(
            stages: [
              const SwapRouteStage(
                kind: SwapRouteStageKind.send,
                network: 'First',
              ),
              const SwapRouteStage(
                kind: SwapRouteStageKind.send,
                network: 'Second',
              ),
              const SwapRouteStage(
                kind: SwapRouteStageKind.bridge,
                network: 'Base',
              ),
              const SwapRouteStage(
                kind: SwapRouteStageKind.receive,
                network: 'Arbitrum',
              ),
              const SwapRouteStage(
                kind: SwapRouteStageKind.receive,
                network: '',
              ),
            ],
          ),
        );
        expect(copy.fromNetwork, 'Second');
        expect(copy.toNetwork, 'Arbitrum');
      });

      test("a side the route does not name goes by its asset's network", () {
        final copy = copyOf(
          snap(
            stages: const [
              SwapRouteStage(kind: SwapRouteStageKind.send, network: 'Base'),
            ],
            to: btc,
          ),
        );
        expect(copy.fromNetwork, 'Base');
        expect(copy.toNetwork, 'BTC');
        expect(copyOf(snap(stages: const [])).fromNetwork, 'Ethereum');
      });

      test('an unknown asset falls back to its ticker for the network', () {
        final copy = copyOf(
          snap(from: null, fromTicker: 'WBTC', to: null, toTicker: 'XYZ'),
        );
        expect(copy.fromNetwork, 'WBTC');
        expect(copy.toNetwork, 'XYZ');
      });
    });

    group('pair line', () {
      test('shows what is sold and what is expected', () {
        expect(copyOf(snap()).pairLine, '1 ETH → 3,000 USDC');
      });

      test('shows what arrived once finished, rounded down', () {
        final copy = copyOf(snap(outcome: completed(amount: '3001.129')));
        expect(copy.pairLine, '1 ETH → 3,001.12 USDC');
      });

      test('falls back to the minimum, then to the tickers', () {
        expect(
          copyOf(snap(expected: null, minimum: '2985.129')).pairLine,
          '1 ETH → 2,985.12 USDC',
        );
        expect(
          copyOf(snap(sell: null, expected: null, minimum: null)).pairLine,
          'ETH → USDC',
        );
      });
    });

    group('received ticker', () {
      test('a wallet asset goes by its ticker', () {
        expect(copyOf(snap(outcome: completed())).receivedTicker, 'USDC');
      });

      test("the provider's symbol names an asset the wallet does not know", () {
        final copy = copyOf(
          snap(
            outcome: SwapExecutionOutcome(
              kind: SwapOutcomeKind.partialOtherToken,
              receivedAmount: d('0.5'),
              receivedSymbol: 'stETH',
            ),
          ),
        );
        expect(copy.receivedTicker, 'stETH');
      });

      test('otherwise it is what was asked for', () {
        expect(copyOf(snap()).receivedTicker, 'USDC');
        expect(
          copyOf(
            snap(
              outcome: const SwapExecutionOutcome(
                kind: SwapOutcomeKind.completed,
              ),
            ),
          ).receivedTicker,
          'USDC',
        );
      });
    });

    group('running hero', () {
      final approval = SwapApprovalRequirement(
        asset: usdc,
        exactAmount: d('1250'),
        resetsFirst: false,
      );
      final reset = SwapApprovalRequirement(
        asset: usdc,
        exactAmount: d('1250'),
        resetsFirst: true,
      );
      final bridgeRoute = [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
        SwapRouteStage(kind: SwapRouteStageKind.send, asset: eth),
        const SwapRouteStage(kind: SwapRouteStageKind.bridge, network: 'Base'),
        SwapRouteStage(kind: SwapRouteStageKind.receive, asset: usdc),
      ];

      final cases = <(String, SwapExecutionSnapshot, SwapHeroCopy)>[
        (
          'preparing',
          snap(stage: SwapProgressStage.preparing),
          const SwapHeroCopy(
            title: 'Preparing swap',
            body: 'Checking the latest details before anything is signed.',
            icon: Icons.autorenew_rounded,
          ),
        ),
        (
          'matching',
          snap(stage: SwapProgressStage.matching),
          const SwapHeroCopy(
            title: 'Finding a counterparty',
            body:
                'Waiting for a peer to take this exchange. Nothing has left '
                'your wallet.',
            icon: Icons.people_alt_outlined,
          ),
        ),
        (
          'approving the sold amount when the route names no permission',
          snap(stage: SwapProgressStage.approving),
          const SwapHeroCopy(
            title: 'Approving exact amount',
            body:
                "Approving exactly 1 ETH. Network fees apply; the ETH you're "
                "swapping hasn't moved.",
            icon: Icons.verified_user_outlined,
          ),
        ),
        (
          'approving the exact permission',
          snap(stage: SwapProgressStage.approving, approval: approval),
          const SwapHeroCopy(
            title: 'Approving exact amount',
            body:
                'Approving exactly 1,250 USDC. Network fees apply; the USDC '
                "you're swapping hasn't moved.",
            icon: Icons.verified_user_outlined,
          ),
        ),
        (
          'resetting before any permission transaction',
          snap(stage: SwapProgressStage.approving, approval: reset),
          const SwapHeroCopy(
            title: 'Resetting token permission',
            body:
                'Setting the current USDC permission to zero, then approving '
                'exactly 1,250 USDC.',
            icon: Icons.layers_clear_outlined,
          ),
        ),
        (
          'approving once the reset went out',
          snap(
            stage: SwapProgressStage.approving,
            approval: reset,
            evidence: const SwapEvidence(
              executionId: 'swap-1',
              approvalTxHashes: ['0xreset'],
            ),
          ),
          const SwapHeroCopy(
            title: 'Approving exact amount',
            body:
                'Approving exactly 1,250 USDC. Network fees apply; the USDC '
                "you're swapping hasn't moved.",
            icon: Icons.verified_user_outlined,
          ),
        ),
        (
          'signing',
          snap(stage: SwapProgressStage.signing),
          const SwapHeroCopy(
            title: 'Signing',
            body:
                'Signing the swap request on this device. Nothing has been '
                'sent yet.',
            icon: Icons.draw_outlined,
          ),
        ),
        (
          'sending',
          snap(stage: SwapProgressStage.sending),
          const SwapHeroCopy(
            title: 'Sending on Ethereum',
            body:
                "Sending the transaction to Ethereum. It can't be cancelled "
                'now.',
            icon: Icons.cell_tower_rounded,
          ),
        ),
        (
          'confirming',
          snap(),
          const SwapHeroCopy(
            title: 'Confirming on Ethereum',
            body: 'Waiting for the source transaction to confirm.',
            icon: Icons.timer_outlined,
          ),
        ),
        (
          'bridging',
          snap(stage: SwapProgressStage.bridging, stages: bridgeRoute),
          const SwapHeroCopy(
            title: 'Moving to Base',
            body: 'This can take a few minutes. Gleec will keep tracking.',
            icon: Icons.route_outlined,
          ),
        ),
        (
          'awaiting delivery',
          snap(stage: SwapProgressStage.awaitingDelivery),
          const SwapHeroCopy(
            title: 'Arriving on Ethereum',
            body: 'Waiting for delivery on Ethereum.',
            icon: Icons.place_outlined,
          ),
        ),
        (
          'refunding',
          snap(stage: SwapProgressStage.refunding),
          const SwapHeroCopy(
            title: 'Refund in progress',
            body:
                'The route is returning your funds. Gleec will keep tracking.',
            icon: Icons.undo_rounded,
            tone: SwapTone.warning,
          ),
        ),
        (
          'action required',
          snap(stage: SwapProgressStage.actionRequired),
          const SwapHeroCopy(
            title: 'Action required',
            body: "Open the route's page to continue.",
            icon: Icons.back_hand_outlined,
            tone: SwapTone.warning,
          ),
        ),
        (
          'exchanging',
          snap(stage: SwapProgressStage.exchanging),
          const SwapHeroCopy(
            title: 'Exchanging asset',
            body:
                'Your payment is locked in the exchange. Waiting for the '
                'other side to complete.',
            icon: Icons.swap_horiz_rounded,
          ),
        ),
        (
          'an unknown stage',
          snap(stage: SwapProgressStage.unknown),
          const SwapHeroCopy(
            title: 'Tracking your swap',
            body:
                'Gleec is checking the latest status. This does not mean the '
                'swap failed.',
            icon: Icons.radar_rounded,
          ),
        ),
        (
          'no stage at all',
          snap(stage: null),
          const SwapHeroCopy(
            title: 'Tracking your swap',
            body:
                'Gleec is checking the latest status. This does not mean the '
                'swap failed.',
            icon: Icons.radar_rounded,
          ),
        ),
        (
          'a delayed status, whatever the stage',
          snap(
            stage: SwapProgressStage.sending,
            delayedSince: DateTime(2026, 9, 25),
          ),
          const SwapHeroCopy(
            title: 'Status update delayed',
            body:
                "We don't have a current update yet. This does not mean the "
                'swap failed.',
            icon: Icons.hourglass_bottom_rounded,
            tone: SwapTone.warning,
          ),
        ),
      ];

      for (final (name, snapshot, expected) in cases) {
        test('says what is happening: $name', () {
          final hero = copyOf(snapshot).hero;
          expect(hero.title, expected.title);
          expect(hero.body, expected.body);
          expect(hero.icon, expected.icon);
          expect(hero.tone, expected.tone);
        });
      }

      test('a finished swap is headlined by its outcome, not its delay', () {
        final hero = copyOf(
          snap(outcome: completed(), delayedSince: DateTime(2026, 9, 25)),
        ).hero;
        expect(hero.title, 'You received 3,001 USDC');
      });
    });

    test('a hero is brand-toned and body-less unless told otherwise', () {
      const hero = SwapHeroCopy(title: 'Title', icon: Icons.abc);
      expect(hero.tone, SwapTone.brand);
      expect(hero.body, isNull);
    });
  });
}
