import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

import 'swap_common_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// How a finished swap is headlined: what arrived, what came back, and for a
/// failure what happened, without ever saying nothing moved when it may have.
void main() {
  final networks = SwapNetworks([eth, usdc, btc, gleec]);
  SwapHeroCopy heroOf(SwapExecutionSnapshot snapshot) =>
      SwapExecutionCopy(snapshot, networks).hero;

  const uncertainBody =
      "We can't confirm whether the transaction was sent. Check the explorer "
      'before trying again.';
  const feesOnlyBody =
      "Nothing was swapped. Your ETH didn't leave; network fees were spent.";

  group('swap outcome hero', () {
    useEnglishCopy();

    group('delivered', () {
      test('a completion says what arrived, rounded down, and where', () {
        final hero = heroOf(snap(outcome: completed(amount: '3001.129')));
        expect(hero.title, 'You received 3,001.12 USDC');
        expect(hero.body, 'Received at 0x5520…7B91 on Ethereum.');
        expect(hero.icon, Icons.check_circle_outline_rounded);
        expect(hero.tone, SwapTone.success);
      });

      test('without an address it names only the network', () {
        final hero = heroOf(snap(outcome: completed(), toAddress: null));
        expect(hero.body, 'Received on Ethereum.');
      });

      test('without an amount it names only the asset', () {
        final hero = heroOf(
          snap(
            outcome: SwapExecutionOutcome(
              kind: SwapOutcomeKind.completed,
              receivedAsset: usdc,
            ),
          ),
        );
        expect(hero.title, 'You received USDC');
      });

      test('less than the minimum says both, each rounded down', () {
        final hero = heroOf(
          snap(
            minimum: '2985.129',
            outcome: SwapExecutionOutcome(
              kind: SwapOutcomeKind.partialBelowMinimum,
              receivedAmount: d('2900.999'),
              receivedAsset: usdc,
            ),
          ),
        );
        expect(hero.title, 'Received less than the minimum');
        expect(
          hero.body,
          'The swap completed with 2,900.99 USDC, below the minimum of '
          '2,985.12 USDC.',
        );
        expect(hero.icon, Icons.trending_down_rounded);
        expect(hero.tone, SwapTone.warning);
      });

      test('an unknown minimum is not invented', () {
        final hero = heroOf(
          snap(
            minimum: null,
            outcome: SwapExecutionOutcome(
              kind: SwapOutcomeKind.partialBelowMinimum,
              receivedAmount: d('2900'),
              receivedAsset: usdc,
            ),
          ),
        );
        expect(
          hero.body,
          'The swap completed with 2,900 USDC, below the minimum of USDC.',
        );
      });

      test('a different token names what arrived and what was asked for', () {
        final hero = heroOf(
          snap(
            outcome: SwapExecutionOutcome(
              kind: SwapOutcomeKind.partialOtherToken,
              receivedAmount: d('0.51'),
              receivedSymbol: 'stETH',
            ),
          ),
        );
        expect(hero.title, 'A different token was received');
        expect(hero.body, 'The swap completed with 0.51 stETH, not USDC.');
        expect(hero.icon, Icons.currency_exchange_rounded);
        expect(hero.tone, SwapTone.warning);
      });
    });

    group('stopped', () {
      test('a refund names the asset and the network it came back on', () {
        final hero = heroOf(
          snap(
            outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.refunded),
          ),
        );
        expect(hero.title, 'Refund received');
        expect(
          hero.body,
          "The swap didn't happen. Your ETH was returned on Ethereum.",
        );
        expect(hero.icon, Icons.undo_rounded);
        expect(hero.tone, SwapTone.success);
      });

      test('a cancellation says nothing was broadcast', () {
        final hero = heroOf(
          snap(
            fundsMovement: SwapFundsMovement.none,
            outcome: const SwapExecutionOutcome(
              kind: SwapOutcomeKind.cancelled,
            ),
          ),
        );
        expect(hero.title, 'Cancelled before funds moved');
        expect(hero.body, 'No asset transfer was broadcast.');
        expect(hero.icon, Icons.cancel_outlined);
        expect(hero.tone, SwapTone.neutral);
      });

      test('a cancellation warns about the exact permission left behind', () {
        final hero = heroOf(
          snap(
            fundsMovement: SwapFundsMovement.feesOnly,
            approvalRemains: true,
            approval: SwapApprovalRequirement(
              asset: usdc,
              exactAmount: d('1250'),
              resetsFirst: false,
            ),
            outcome: const SwapExecutionOutcome(
              kind: SwapOutcomeKind.cancelled,
            ),
          ),
        );
        expect(
          hero.body,
          'No swap was sent. The exact permission for 1,250 USDC stays '
          'on-chain.',
        );
        expect(hero.tone, SwapTone.warning);
      });

      test('no match says nothing was sent', () {
        final hero = heroOf(
          snap(
            source: SwapLiquiditySource.atomic,
            fundsMovement: SwapFundsMovement.none,
            outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.noMatch),
          ),
        );
        expect(hero.title, 'No match found');
        expect(
          hero.body,
          'No one took this exchange in time. Nothing was sent.',
        );
        expect(hero.icon, Icons.person_search_outlined);
        expect(hero.tone, SwapTone.neutral);
      });
    });

    group('failed', () {
      SwapHeroCopy failure(
        SwapFailureReason reason, {
        SwapFundsMovement movement = SwapFundsMovement.none,
      }) => heroOf(snap(fundsMovement: movement, outcome: failed(reason)));

      final fixed = <(SwapFailureReason, String, String, IconData, SwapTone)>[
        (
          SwapFailureReason.priceMoved,
          'Price changed',
          'The price moved below your minimum before anything was sent.',
          Icons.show_chart_rounded,
          SwapTone.warning,
        ),
        (
          SwapFailureReason.approvalFailed,
          'Token permission failed',
          "The approval didn't complete, so nothing was swapped. Its network "
              'fee may be spent.',
          Icons.gpp_bad_outlined,
          SwapTone.danger,
        ),
        (
          SwapFailureReason.reverted,
          'Transaction reverted',
          "The network rejected this transaction. Your ETH didn't leave; the "
              'network fee was spent.',
          Icons.error_outline_rounded,
          SwapTone.danger,
        ),
        (
          SwapFailureReason.notConfirmed,
          'Still waiting for confirmation',
          "The transaction was sent but hasn't confirmed yet. It may still "
              'confirm — check the explorer before trying again.',
          Icons.hourglass_bottom_rounded,
          SwapTone.warning,
        ),
        (
          SwapFailureReason.routeFailed,
          'Gleec support is needed',
          'Your funds left Ethereum, but the route reported a failure without '
              'a refund. Share the evidence with support.',
          Icons.support_agent_rounded,
          SwapTone.danger,
        ),
        (
          SwapFailureReason.unknown,
          "We're reviewing an unfamiliar status",
          'Gleec will keep tracking. Share the evidence with support if this '
              'persists.',
          Icons.help_outline_rounded,
          SwapTone.warning,
        ),
      ];
      for (final (reason, title, body, icon, tone) in fixed) {
        test('${reason.name} explains itself', () {
          final hero = failure(reason, movement: SwapFundsMovement.sent);
          expect(hero.title, title);
          expect(hero.body, body);
          expect(hero.icon, icon);
          expect(hero.tone, tone);
        });
      }

      final guarded = <(SwapFailureReason, String, String, IconData)>[
        (
          SwapFailureReason.walletRejected,
          'Request declined',
          'Nothing was sent for this step.',
          Icons.do_not_disturb_on_outlined,
        ),
        (
          SwapFailureReason.safetyCheck,
          'Swap blocked by a safety check',
          'Gleec stopped this route before signing. Nothing was sent.',
          Icons.shield_outlined,
        ),
        (
          SwapFailureReason.quoteUnavailable,
          "The price couldn't be confirmed",
          'Nothing was sent. Get a fresh quote to try again.',
          Icons.price_change_outlined,
        ),
        (
          SwapFailureReason.restarted,
          'Stopped when Gleec restarted',
          'Nothing was swapped. You can start again safely.',
          Icons.restart_alt_rounded,
        ),
        (
          SwapFailureReason.internal,
          'Something went wrong',
          'Nothing was sent. Try again.',
          Icons.error_outline_rounded,
        ),
      ];
      for (final (reason, title, safe, icon) in guarded) {
        test('${reason.name} says nothing was sent only when nothing was', () {
          final hero = failure(reason);
          expect(hero.title, title);
          expect(hero.body, safe);
          expect(hero.icon, icon);
          expect(hero.tone, SwapTone.warning);
          expect(
            failure(reason, movement: SwapFundsMovement.feesOnly).body,
            feesOnlyBody,
          );
          for (final movement in [
            SwapFundsMovement.uncertain,
            SwapFundsMovement.sent,
          ]) {
            expect(
              failure(reason, movement: movement).body,
              uncertainBody,
              reason: movement.name,
            );
          }
        });
      }

      test('an internal error is danger once the swap may have left', () {
        final internal = SwapFailureReason.internal;
        expect(
          failure(internal, movement: SwapFundsMovement.feesOnly).tone,
          SwapTone.warning,
        );
        expect(
          failure(internal, movement: SwapFundsMovement.uncertain).tone,
          SwapTone.danger,
        );
        expect(
          failure(internal, movement: SwapFundsMovement.sent).tone,
          SwapTone.danger,
        );
      });

      test('a failed exchange points to Advanced once anything was sent', () {
        final exchange = SwapFailureReason.exchangeFailed;
        final safe = failure(exchange);
        expect(safe.title, "The exchange didn't complete");
        expect(safe.body, 'Nothing was sent. You can try again.');
        expect(safe.icon, Icons.sync_problem_rounded);
        expect(safe.tone, SwapTone.warning);
        for (final movement in [
          SwapFundsMovement.feesOnly,
          SwapFundsMovement.uncertain,
          SwapFundsMovement.sent,
        ]) {
          final moved = failure(exchange, movement: movement);
          expect(
            moved.body,
            'Open it in Advanced for the full log and recovery options.',
          );
          expect(moved.tone, SwapTone.danger);
        }
      });

      test('a failure without a reason is an unfamiliar status', () {
        final hero = heroOf(
          snap(
            outcome: const SwapExecutionOutcome(kind: SwapOutcomeKind.failed),
          ),
        );
        expect(hero.title, "We're reviewing an unfamiliar status");
      });
    });

    group('short balance', () {
      SwapHeroCopy shortOf(SwapExecutionFailure failure) => heroOf(
        snap(
          fundsMovement: SwapFundsMovement.none,
          outcome: SwapExecutionOutcome(
            kind: SwapOutcomeKind.failed,
            failure: failure,
          ),
        ),
      );

      test('says what was needed, rounded up, and held, rounded down', () {
        final hero = shortOf(
          SwapExecutionFailure(
            reason: SwapFailureReason.insufficientBalance,
            nextStep: SwapNextStep.fixAndRetry,
            shortfallAsset: usdc,
            shortfallTicker: 'IGNORED',
            shortfallRequired: d('1250.00001'),
            shortfallAvailable: d('1000.999'),
          ),
        );
        expect(hero.title, 'Not enough balance');
        expect(
          hero.body,
          'The swap needed 1,250.01 USDC but this address had 1,000.99 USDC. '
          'Nothing was swapped.',
        );
        expect(hero.icon, Icons.account_balance_wallet_outlined);
        expect(hero.tone, SwapTone.warning);
      });

      test("names the engine's ticker, then the sold asset", () {
        SwapExecutionFailure short({String? ticker}) => SwapExecutionFailure(
          reason: SwapFailureReason.insufficientBalance,
          nextStep: SwapNextStep.fixAndRetry,
          shortfallTicker: ticker,
          shortfallRequired: d('2'),
          shortfallAvailable: d('1'),
        );
        expect(
          shortOf(short(ticker: 'WETH')).body,
          'The swap needed 2 WETH but this address had 1 WETH. Nothing was '
          'swapped.',
        );
        expect(
          shortOf(short()).body,
          'The swap needed 2 ETH but this address had 1 ETH. Nothing was '
          'swapped.',
        );
      });

      test('without both figures it only says the balance is unchanged', () {
        for (final (required, available) in [(d('2'), null), (null, d('1'))]) {
          final hero = shortOf(
            SwapExecutionFailure(
              reason: SwapFailureReason.insufficientBalance,
              nextStep: SwapNextStep.fixAndRetry,
              shortfallRequired: required,
              shortfallAvailable: available,
            ),
          );
          expect(hero.body, 'Your balance is unchanged.');
        }
      });
    });
  });
}
