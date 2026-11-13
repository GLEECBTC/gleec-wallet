import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_exec_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers how a routed swap's engine snapshot becomes the app's: the outcome,
/// whether funds moved, the stage, and the leftover permission. Claiming that
/// nothing moved when it may have is the mistake this guards against.
void main() {
  SwapExecutionSnapshot map(RoutedSwapProgress progress, {SwapQuote? quote}) =>
      routedSnapshotFrom(progress, networks: execNetworks, accepted: quote);

  RoutedSwapProgress finished(
    RoutedSwapOutcome outcome, {
    RoutedSwapPartialReason? reason,
    AssetId? asset,
    String? symbol,
    List<String> approvals = const [],
  }) => progressOf(
    phase: RoutedSwapPhase.finished,
    approvals: approvals,
    receipt: RoutedSwapReceipt(
      outcome: outcome,
      partialReason: reason,
      amount: d('2990'),
      assetId: asset,
      symbol: symbol,
    ),
  );

  RoutedSwapProgress failedWith(
    RoutedSwapFailureKind kind, {
    RoutedSwapFundsMovement movement = RoutedSwapFundsMovement.none,
    List<String> approvals = const [],
  }) => progressOf(
    phase: RoutedSwapPhase.failed,
    approvals: approvals,
    failure: failureOf(kind, movement: movement),
  );

  group('outcome', () {
    test('a completed receipt is a success, with what arrived', () {
      final snapshot = map(finished(RoutedSwapOutcome.completed, asset: usdc));

      expect(snapshot.outcome!.kind, SwapOutcomeKind.completed);
      expect(snapshot.outcome!.receivedAmount, d('2990'));
      expect(snapshot.outcome!.receivedAsset, usdc);
      expect(snapshot.outcome!.receivedSymbol, isNull);
      expect(snapshot.fundsMovement, SwapFundsMovement.sent);
      expect(snapshot.stage, isNull);
      expect(snapshot.isSuccess, isTrue);
    });

    test('a refund is its own outcome', () {
      final snapshot = map(finished(RoutedSwapOutcome.refunded, asset: eth));
      expect(snapshot.outcome!.kind, SwapOutcomeKind.refunded);
      expect(snapshot.isSuccess, isFalse);
    });

    test('a partial fill below the minimum says so', () {
      final snapshot = map(
        finished(
          RoutedSwapOutcome.partial,
          reason: RoutedSwapPartialReason.belowMinimum,
          asset: usdc,
        ),
      );
      expect(snapshot.outcome!.kind, SwapOutcomeKind.partialBelowMinimum);
      expect(snapshot.needsAttention, isTrue);
    });

    test('any other partial fill delivered a different token', () {
      for (final reason in [
        RoutedSwapPartialReason.intermediateToken,
        RoutedSwapPartialReason.unknown,
        null,
      ]) {
        final snapshot = map(
          finished(
            RoutedSwapOutcome.partial,
            reason: reason,
            symbol: 'axlUSDC',
          ),
        );
        expect(
          snapshot.outcome!.kind,
          SwapOutcomeKind.partialOtherToken,
          reason: '$reason',
        );
      }
    });

    test('an outcome this build cannot read never reads as success', () {
      final snapshot = map(finished(RoutedSwapOutcome.unknown, asset: usdc));

      expect(snapshot.outcome!.kind, SwapOutcomeKind.partialOtherToken);
      expect(snapshot.isSuccess, isFalse);
      expect(snapshot.needsAttention, isTrue);
    });

    test('a token the wallet does not know is named by its symbol only', () {
      final unknown = map(
        finished(RoutedSwapOutcome.partial, symbol: 'axlUSDC'),
      ).outcome!;
      final known = map(
        finished(RoutedSwapOutcome.completed, asset: usdc, symbol: 'USDC'),
      ).outcome!;

      expect(unknown.receivedAsset, isNull);
      expect(unknown.receivedSymbol, 'axlUSDC');
      expect(known.receivedSymbol, isNull);
    });

    test('a cancellation is not a failure', () {
      final snapshot = map(failedWith(RoutedSwapFailureKind.cancelled));

      expect(snapshot.outcome!.kind, SwapOutcomeKind.cancelled);
      expect(snapshot.outcome!.failure, isNull);
      expect(snapshot.fundsMovement, SwapFundsMovement.none);
      expect(snapshot.needsAttention, isFalse);
    });

    test('a failure keeps its reason and ends the swap', () {
      final snapshot = map(failedWith(RoutedSwapFailureKind.bridgeFailed));

      expect(snapshot.outcome!.kind, SwapOutcomeKind.failed);
      expect(snapshot.outcome!.failure!.reason, SwapFailureReason.routeFailed);
      expect(snapshot.stage, isNull);
      expect(snapshot.isTerminal, isTrue);
    });

    test('a receipt wins over a failure reported alongside it', () {
      final snapshot = map(
        progressOf(
          phase: RoutedSwapPhase.finished,
          receipt: RoutedSwapReceipt(
            outcome: RoutedSwapOutcome.completed,
            amount: d('1'),
            assetId: usdc,
          ),
          failure: failureOf(RoutedSwapFailureKind.internalError),
        ),
      );
      expect(snapshot.outcome!.kind, SwapOutcomeKind.completed);
      expect(snapshot.fundsMovement, SwapFundsMovement.sent);
    });
  });

  group('funds movement', () {
    test('a failure says exactly what the engine says moved', () {
      const expected = {
        RoutedSwapFundsMovement.none: SwapFundsMovement.none,
        RoutedSwapFundsMovement.feesOnly: SwapFundsMovement.feesOnly,
        RoutedSwapFundsMovement.uncertain: SwapFundsMovement.uncertain,
        RoutedSwapFundsMovement.sent: SwapFundsMovement.sent,
      };
      for (final MapEntry(key: engine, value: app) in expected.entries) {
        final snapshot = map(
          failedWith(RoutedSwapFailureKind.internalError, movement: engine),
        );
        expect(snapshot.fundsMovement, app, reason: engine.name);
        expect(
          snapshot.needsAttention,
          app != SwapFundsMovement.none,
          reason: engine.name,
        );
      }
    });

    test('a running swap moved nothing before it sends', () {
      for (final phase in [
        RoutedSwapPhase.preparing,
        RoutedSwapPhase.signing,
      ]) {
        expect(
          map(progressOf(phase: phase)).fundsMovement,
          SwapFundsMovement.none,
          reason: phase.name,
        );
        expect(
          map(progressOf(phase: phase, approvals: ['0xap'])).fundsMovement,
          SwapFundsMovement.feesOnly,
          reason: '${phase.name} after an approval',
        );
      }
    });

    test('an approval in flight spends only fees', () {
      expect(
        map(progressOf(phase: RoutedSwapPhase.approving)).fundsMovement,
        SwapFundsMovement.feesOnly,
      );
    });

    test('from sending on, the funds are never said to be untouched', () {
      const expected = {
        RoutedSwapPhase.sending: SwapFundsMovement.uncertain,
        RoutedSwapPhase.confirming: SwapFundsMovement.sent,
        RoutedSwapPhase.bridging: SwapFundsMovement.sent,
        RoutedSwapPhase.unknown: SwapFundsMovement.uncertain,
        RoutedSwapPhase.finished: SwapFundsMovement.uncertain,
        RoutedSwapPhase.failed: SwapFundsMovement.uncertain,
      };
      for (final MapEntry(key: phase, value: movement) in expected.entries) {
        expect(
          map(progressOf(phase: phase)).fundsMovement,
          movement,
          reason: phase.name,
        );
      }
    });
  });

  group('stage', () {
    test('each engine phase has its stage', () {
      const expected = {
        RoutedSwapPhase.preparing: SwapProgressStage.preparing,
        RoutedSwapPhase.approving: SwapProgressStage.approving,
        RoutedSwapPhase.signing: SwapProgressStage.signing,
        RoutedSwapPhase.sending: SwapProgressStage.sending,
        RoutedSwapPhase.confirming: SwapProgressStage.confirming,
        RoutedSwapPhase.bridging: SwapProgressStage.bridging,
        RoutedSwapPhase.unknown: SwapProgressStage.unknown,
      };
      for (final MapEntry(key: phase, value: stage) in expected.entries) {
        final snapshot = map(progressOf(phase: phase));
        expect(snapshot.stage, stage, reason: phase.name);
        expect(snapshot.isTerminal, isFalse, reason: phase.name);
      }
    });

    test('a terminal phase without a result keeps tracking as unknown', () {
      for (final phase in [RoutedSwapPhase.finished, RoutedSwapPhase.failed]) {
        final snapshot = map(progressOf(phase: phase));
        expect(snapshot.stage, SwapProgressStage.unknown, reason: phase.name);
        expect(snapshot.isTerminal, isFalse, reason: phase.name);
      }
    });

    test('the bridge stage decides what a bridging swap is waiting for', () {
      const expected = {
        RoutedSwapBridgeStage.bridging: SwapProgressStage.bridging,
        RoutedSwapBridgeStage.destinationPending:
            SwapProgressStage.awaitingDelivery,
        RoutedSwapBridgeStage.refundPending: SwapProgressStage.refunding,
        RoutedSwapBridgeStage.actionRequired: SwapProgressStage.actionRequired,
        RoutedSwapBridgeStage.unknown: SwapProgressStage.bridging,
      };
      for (final MapEntry(key: bridge, value: stage) in expected.entries) {
        final snapshot = map(
          progressOf(phase: RoutedSwapPhase.bridging, bridgeStage: bridge),
        );
        expect(snapshot.stage, stage, reason: bridge.name);
      }
      final waiting = map(
        progressOf(
          phase: RoutedSwapPhase.bridging,
          bridgeStage: RoutedSwapBridgeStage.actionRequired,
        ),
      );
      expect(waiting.needsAttention, isTrue);
    });
  });

  group('leftover permission', () {
    const approved = ['0xreset', '0xapprove'];

    test('remains after a cancellation or a failure that sent nothing', () {
      expect(
        map(
          failedWith(RoutedSwapFailureKind.cancelled, approvals: approved),
        ).approvalRemains,
        isTrue,
      );
      for (final movement in [
        RoutedSwapFundsMovement.none,
        RoutedSwapFundsMovement.feesOnly,
      ]) {
        final snapshot = map(
          failedWith(
            RoutedSwapFailureKind.priceMoved,
            movement: movement,
            approvals: approved,
          ),
        );
        expect(snapshot.approvalRemains, isTrue, reason: movement.name);
        expect(snapshot.needsAttention, isTrue, reason: movement.name);
      }
    });

    test('is not claimed once the swap may have spent it', () {
      for (final movement in [
        RoutedSwapFundsMovement.uncertain,
        RoutedSwapFundsMovement.sent,
      ]) {
        final snapshot = map(
          failedWith(
            RoutedSwapFailureKind.bridgeFailed,
            movement: movement,
            approvals: approved,
          ),
        );
        expect(snapshot.approvalRemains, isFalse, reason: movement.name);
      }
      expect(
        map(
          finished(RoutedSwapOutcome.completed, approvals: approved),
        ).approvalRemains,
        isFalse,
      );
    });

    test('is not claimed without an approval, or while running', () {
      expect(
        map(failedWith(RoutedSwapFailureKind.cancelled)).approvalRemains,
        isFalse,
      );
      expect(
        map(
          progressOf(phase: RoutedSwapPhase.signing, approvals: approved),
        ).approvalRemains,
        isFalse,
      );
    });
  });

  group('route kind without an offer', () {
    RoutedSwapRequest request(AssetId? from, AssetId? to) => RoutedSwapRequest(
      fromTicker: from?.id ?? 'OLD',
      toTicker: to?.id ?? 'NEW',
      from: from,
      to: to,
      amount: d('2'),
    );

    test('is same-chain only when both assets share a network', () {
      expect(
        map(progressOf(requested: request(eth, usdc))).routeKind,
        SwapRouteKind.sameChain,
      );
      expect(
        map(progressOf(requested: request(eth, arbEth))).routeKind,
        SwapRouteKind.crossChain,
      );
    });

    test('assumes a bridge wait when an asset or the request is unknown', () {
      expect(
        map(progressOf(requested: request(null, usdc))).routeKind,
        SwapRouteKind.crossChain,
      );
      expect(
        map(progressOf(requested: request(eth, null))).routeKind,
        SwapRouteKind.crossChain,
      );
      expect(map(progressOf()).routeKind, SwapRouteKind.crossChain);
    });

    test('names the swap from the durable request', () {
      final snapshot = map(progressOf(requested: request(null, usdc)));

      expect(snapshot.from, isNull);
      expect(snapshot.fromTicker, 'OLD');
      expect(snapshot.to, usdc);
      expect(snapshot.toTicker, 'USDC-ERC20');
      expect(snapshot.sellAmount, d('2'));
      expect(snapshot.expectedReceive, isNull);
      expect(snapshot.minimumReceive, isNull);
      expect(snapshot.fromAddress, isNull);
      expect(snapshot.approval, isNull);
      expect(snapshot.stages, isEmpty);
      expect(snapshot.evidence.diagnostic, isNull);
    });

    test('with no request either, the tickers are blank', () {
      final snapshot = map(progressOf());
      expect(snapshot.fromTicker, '');
      expect(snapshot.toTicker, '');
      expect(snapshot.sellAmount, isNull);
    });
  });

  group('described from the offer', () {
    final offer = offerOf(
      kind: RoutedSwapRouteKind.crossChain,
      to: arbEth,
      expected: '0.99',
      guaranteed: '0.98',
      approval: const RoutedSwapApprovalInfo(
        txCount: 2,
        resetsFirst: true,
        spender: '0xspender',
      ),
    );

    test('carries the route the user accepted', () {
      final plan = routedQuoteFromOffer(offer, networks: execNetworks);
      final snapshot = map(progressOf(offer: offer));

      expect(snapshot.routeKind, SwapRouteKind.crossChain);
      expect(snapshot.from, eth);
      expect(snapshot.fromTicker, 'ETH');
      expect(snapshot.to, arbEth);
      expect(snapshot.toTicker, 'ETH-ARB20');
      expect(snapshot.sellAmount, d('1'));
      expect(snapshot.expectedReceive, d('0.99'));
      expect(snapshot.minimumReceive, d('0.98'));
      expect(snapshot.fromAddress, '0xfrom');
      expect(snapshot.toAddress, '0xfrom');
      expect(snapshot.approval, plan.approval);
      expect(snapshot.approval!.resetsFirst, isTrue);
      expect(snapshot.stages, plan.stages);
      expect(snapshot.estimatedDuration, const Duration(seconds: 30));
      expect(snapshot.evidence.diagnostic, plan.diagnostic);
    });

    test('prefers the executed route over the accepted one', () {
      final executed = offerOf(guaranteed: '2900', to: usdc);
      final snapshot = map(progressOf(offer: offer, executed: executed));

      expect(snapshot.to, usdc);
      expect(snapshot.minimumReceive, d('2900'));
      expect(snapshot.routeKind, SwapRouteKind.sameChain);
    });

    test('lets the durable record override the minimum and the estimate', () {
      final snapshot = map(
        progressOf(
          offer: offer,
          minimum: d('0.97'),
          duration: const Duration(minutes: 20),
        ),
      );
      expect(snapshot.minimumReceive, d('0.97'));
      expect(snapshot.estimatedDuration, const Duration(minutes: 20));
    });

    test('an offer on the record wins over the accepted quote', () {
      final snapshot = map(
        progressOf(offer: offer),
        quote: quoteOf(from: btc, to: gleec),
      );
      expect(snapshot.from, eth);
      expect(snapshot.to, arbEth);
    });
  });
}
