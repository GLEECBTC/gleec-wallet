import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// The recovery answers: where the funds are, the price move, and the one
/// line an Activity row shows.
void main() {
  final networks = SwapNetworks([eth, usdc, btc, gleec]);
  SwapExecutionCopy copyOf(SwapExecutionSnapshot snapshot) =>
      SwapExecutionCopy(snapshot, networks);

  group('swap recovery copy', () {
    useEnglishCopy();

    group('price move', () {
      test('compares the old minimum with the new one, rounded down', () {
        final copy = copyOf(
          snap(
            minimum: '2985.129',
            fundsMovement: SwapFundsMovement.none,
            outcome: failed(
              SwapFailureReason.priceMoved,
              freshQuote: quoteOf(guaranteed: '2950.999'),
            ),
          ),
        );
        expect(
          copy.priceMoveComparison,
          'Minimum was 2,985.12 USDC. Now 2,950.99 USDC.',
        );
      });

      test('says nothing without a fresh quote or an old minimum', () {
        expect(
          copyOf(
            snap(outcome: failed(SwapFailureReason.priceMoved)),
          ).priceMoveComparison,
          isNull,
        );
        expect(
          copyOf(
            snap(
              minimum: null,
              outcome: failed(
                SwapFailureReason.priceMoved,
                freshQuote: quoteOf(),
              ),
            ),
          ).priceMoveComparison,
          isNull,
        );
        expect(copyOf(snap()).priceMoveComparison, isNull);
      });
    });

    group('where the funds are', () {
      String where(SwapExecutionSnapshot snapshot) =>
          copyOf(snapshot).fundsLocation;

      test('delivered funds are at the address on the network', () {
        expect(
          where(snap(outcome: completed(amount: '3001.129'))),
          '3,001.12 USDC at 0x5520…7B91 on Ethereum.',
        );
        expect(
          where(snap(outcome: completed(), toAddress: null)),
          '3,001 USDC on Ethereum.',
        );
      });

      test('a partial delivery answers the same way', () {
        expect(
          where(
            snap(
              outcome: SwapExecutionOutcome(
                kind: SwapOutcomeKind.partialBelowMinimum,
                receivedAmount: d('2900'),
                receivedAsset: usdc,
              ),
            ),
          ),
          '2,900 USDC at 0x5520…7B91 on Ethereum.',
        );
        expect(
          where(
            snap(
              outcome: SwapExecutionOutcome(
                kind: SwapOutcomeKind.partialOtherToken,
                receivedAmount: d('0.51'),
                receivedSymbol: 'stETH',
              ),
            ),
          ),
          '0.51 stETH at 0x5520…7B91 on Ethereum.',
        );
      });

      test('a refund is back on the source network', () {
        expect(
          where(
            snap(
              outcome: const SwapExecutionOutcome(
                kind: SwapOutcomeKind.refunded,
              ),
            ),
          ),
          'Returned to your address on Ethereum.',
        );
      });

      test('a cancellation or no match leaves the balance unchanged', () {
        for (final kind in [
          SwapOutcomeKind.cancelled,
          SwapOutcomeKind.noMatch,
        ]) {
          expect(
            where(
              snap(
                fundsMovement: SwapFundsMovement.none,
                outcome: SwapExecutionOutcome(kind: kind),
              ),
            ),
            'Your balance is unchanged.',
          );
        }
      });

      test('a failure answers from how the funds moved', () {
        SwapExecutionSnapshot failure(
          SwapFundsMovement movement, {
          SwapLiquiditySource source = SwapLiquiditySource.routed,
          String? sell = '1',
        }) => snap(
          source: source,
          sell: sell,
          fundsMovement: movement,
          outcome: failed(SwapFailureReason.internal),
        );
        expect(
          where(failure(SwapFundsMovement.none)),
          'Your balance is unchanged.',
        );
        expect(
          where(failure(SwapFundsMovement.feesOnly)),
          "Your ETH didn't leave. Network fees were spent.",
        );
        for (final movement in [
          SwapFundsMovement.uncertain,
          SwapFundsMovement.sent,
        ]) {
          expect(
            where(failure(movement)),
            'Last confirmed location: 1 ETH on Ethereum. The current '
            "location isn't verified yet.",
          );
          expect(
            where(failure(movement, source: SwapLiquiditySource.atomic)),
            'Locked in the exchange on Ethereum until it completes or '
            'refunds.',
          );
        }
        expect(
          where(failure(SwapFundsMovement.sent, sell: null)),
          'Last confirmed location: ETH on Ethereum. The current location '
          "isn't verified yet.",
        );
      });

      test('a running swap answers from how the funds moved too', () {
        expect(
          where(snap(stage: SwapProgressStage.bridging)),
          'Last confirmed location: 1 ETH on Ethereum. The current location '
          "isn't verified yet.",
        );
        expect(
          where(
            snap(
              stage: SwapProgressStage.preparing,
              fundsMovement: SwapFundsMovement.none,
            ),
          ),
          'Your balance is unchanged.',
        );
      });

      test('a permission left on-chain is always mentioned', () {
        expect(
          where(
            snap(
              fundsMovement: SwapFundsMovement.feesOnly,
              approvalRemains: true,
              approval: SwapApprovalRequirement(
                asset: usdc,
                exactAmount: d('1250'),
                resetsFirst: true,
              ),
              outcome: failed(SwapFailureReason.walletRejected),
            ),
          ),
          "Your ETH didn't leave. Network fees were spent. An exact "
          'permission for 1,250 USDC remains on-chain.',
        );
        expect(
          where(
            snap(
              fundsMovement: SwapFundsMovement.none,
              approvalRemains: true,
              outcome: const SwapExecutionOutcome(
                kind: SwapOutcomeKind.cancelled,
              ),
            ),
          ),
          "Your ETH didn't leave. Network fees were spent. An exact "
          'permission for 1 ETH remains on-chain.',
        );
      });
    });

    group('activity status line', () {
      String line(SwapExecutionSnapshot snapshot) =>
          copyOf(snapshot).statusLine;

      test('a running swap reads as its hero, or as needing action', () {
        expect(line(snap()), 'Confirming on Ethereum');
        expect(
          line(snap(stage: SwapProgressStage.actionRequired)),
          'Action required',
        );
      });

      test('each outcome has its own short status', () {
        SwapExecutionSnapshot ended(
          SwapOutcomeKind kind, {
          bool approvalRemains = false,
        }) => snap(
          approvalRemains: approvalRemains,
          outcome: SwapExecutionOutcome(kind: kind),
        );
        expect(line(snap(outcome: completed())), 'Received');
        expect(
          line(ended(SwapOutcomeKind.partialBelowMinimum)),
          'Received less than expected',
        );
        expect(
          line(ended(SwapOutcomeKind.partialOtherToken)),
          'Different token received',
        );
        expect(line(ended(SwapOutcomeKind.refunded)), 'Refund received');
        expect(line(ended(SwapOutcomeKind.cancelled)), 'Cancelled');
        expect(
          line(ended(SwapOutcomeKind.cancelled, approvalRemains: true)),
          'Permission remains',
        );
        expect(line(ended(SwapOutcomeKind.noMatch)), 'No match found');
      });

      test('a failure reads as its headline', () {
        expect(
          line(snap(outcome: failed(SwapFailureReason.routeFailed))),
          'Gleec support is needed',
        );
      });
    });
  });
}
