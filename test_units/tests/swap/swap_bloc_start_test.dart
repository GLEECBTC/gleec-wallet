import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers starting: which re-priced numbers start at once and which ask
/// again, what a start records, and the form after a swap.
void main() {
  /// Reviews an option costing [before] in fees, then starts it against
  /// [fresh].
  UnifiedSwapBloc startAgainst(
    SwapBlocHarness h,
    SwapQuote fresh, {
    List<SwapFeeComponent>? before,
    SwapApprovalRequirement? approval,
  }) {
    h.routed.respond = (request) => [
      SwapQuoteAvailable(
        quoteOf(fees: before, approval: approval, quotedAt: h.now()),
      ),
    ];
    final bloc = h.inReview();
    h.routed.requoteResult = SwapQuoteAvailable(fresh);
    bloc.add(const UnifiedSwapStartRequested());
    h.settle();
    return bloc;
  }

  swapBlocTest('starting is only possible from the review', (h) {
    final bloc = h.open()..add(const UnifiedSwapStartRequested());
    h.settle();

    expect(bloc.state.view, UnifiedSwapView.form);
    expect(h.routed.requoted, isEmpty);
    expect(h.routedExecutor.started, isEmpty);
  });

  swapBlocTest('a start records the terms at that moment, and the pair', (h) {
    final bloc = h.inReview();
    h.elapse(const Duration(seconds: 5));
    bloc.add(const UnifiedSwapStartRequested());
    h.settle();

    expect(bloc.state.view, UnifiedSwapView.progress);
    final accepted = h.storage.values.values
        .map(SwapTermsAcceptance.tryParse)
        .nonNulls
        .single;
    expect(accepted.acceptedAt, h.now().toUtc());
    expect(h.resolve(h.preferences.lastPair()), (
      from: 'ETH',
      to: 'USDC-ERC20',
    ));
  });

  swapBlocTest('a start the engine refuses keeps its reason', (h) {
    h.routedExecutor.startError = const SwapStartRejectedException(
      SwapStartRejection.notAvailable,
      detail: 'pair paused',
    );
    final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
    h.settle();

    expect(bloc.state.view, UnifiedSwapView.review);
    expect(bloc.state.review!.status, SwapReviewStatus.rejected);
    expect(bloc.state.review!.rejectionDetail, 'pair paused');
  });

  group('re-priced costs', () {
    swapBlocTest('a rise under fifty cents starts without asking', (h) {
      startAgainst(
        h,
        quoteOf(
          id: 'fresh',
          fees: [feeOf(usd: '3.4')],
        ),
      );

      expect(h.routedExecutor.started.single.id, 'fresh');
    });

    swapBlocTest('a rise past fifty cents and a tenth asks again', (h) {
      final bloc = startAgainst(
        h,
        quoteOf(
          id: 'fresh',
          fees: [feeOf(usd: '10')],
        ),
      );

      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      expect(bloc.state.review!.previous!.pricing.totalCostUsd, d('3'));
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('a rise past fifty cents but within a tenth starts', (h) {
      startAgainst(
        h,
        quoteOf(
          id: 'fresh',
          fees: [feeOf(usd: '10.9')],
        ),
        before: [feeOf(usd: '10')],
      );

      expect(h.routedExecutor.started.single.id, 'fresh');
    });

    swapBlocTest('a cost that cannot be priced does not stop a start', (h) {
      startAgainst(
        h,
        quoteOf(
          id: 'fresh',
          fees: [feeOf(usd: null, asset: btc)],
        ),
      );

      expect(h.routedExecutor.started.single.id, 'fresh');
    });
  });

  group('a re-price with different steps returns to the form', () {
    final approval = SwapApprovalRequirement(
      asset: eth,
      exactAmount: d('1'),
      resetsFirst: false,
    );
    List<SwapRouteStage> stages({String? sendNetwork, bool convert = false}) =>
        [
          const SwapRouteStage(kind: SwapRouteStageKind.prepare),
          SwapRouteStage(
            kind: SwapRouteStageKind.send,
            network: sendNetwork,
            asset: eth,
          ),
          if (convert) const SwapRouteStage(kind: SwapRouteStageKind.convert),
          SwapRouteStage(kind: SwapRouteStageKind.receive, asset: usdc),
        ];
    final cases =
        <String, ({SwapApprovalRequirement? before, SwapQuote fresh})>{
          'when a permission is now needed': (
            before: null,
            fresh: quoteOf(id: 'fresh', approval: approval),
          ),
          'when the permission must first be reset': (
            before: approval,
            fresh: quoteOf(
              id: 'fresh',
              approval: SwapApprovalRequirement(
                asset: eth,
                exactAmount: d('1'),
                resetsFirst: true,
              ),
            ),
          ),
          'when a step moves to another network': (
            before: null,
            fresh: quoteOf(
              id: 'fresh',
              stages: stages(sendNetwork: 'Base'),
            ),
          ),
          'when a step is added': (
            before: null,
            fresh: quoteOf(id: 'fresh', stages: stages(convert: true)),
          ),
        };

    for (final MapEntry(key: name, value: change) in cases.entries) {
      swapBlocTest(name, (h) {
        final bloc = startAgainst(h, change.fresh, approval: change.before);

        expect(bloc.state.view, UnifiedSwapView.form);
        expect(bloc.state.structuralNotice, isTrue);
        expect(h.routedExecutor.started, isEmpty);
        expect(h.routed.requests, hasLength(2));
      });
    }

    swapBlocTest('but the same permission and steps start', (h) {
      startAgainst(
        h,
        quoteOf(id: 'fresh', approval: approval, stages: stages()),
        approval: approval,
      );

      expect(h.routedExecutor.started.single.id, 'fresh');
    });
  });

  group('after a swap', () {
    swapBlocTest('leaving progress keeps the pair for another swap', (h) {
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.progress);
      h.balances[eth] = d('0.999');

      bloc.add(const UnifiedSwapProgressLeft());
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect((bloc.state.pay, bloc.state.receive), (eth, usdc));
      expect(bloc.state.inputText, isEmpty);
      expect(bloc.state.activeExecutionId, isNull);
      expect(bloc.state.quotes, isNull);
      expect(bloc.state.issue, SwapFormIssue.amountMissing);
      expect(bloc.state.balance, d('0.999'));
    });

    swapBlocTest('a reset can clear the pair as well', (h) {
      final bloc = h.open()
        ..add(const UnifiedSwapAmountModeToggled())
        ..add(const UnifiedSwapResetRequested(keepPair: false));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (null, null));
      expect(bloc.state.amountMode, SwapAmountMode.token);
      expect(bloc.state.inputText, isEmpty);
      expect(bloc.state.balance, isNull);
    });

    swapBlocTest('a reset while the start re-prices abandons it', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(const UnifiedSwapResetRequested());
      h.settle();

      h.routed.requoteGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
    });

    swapBlocTest('a follow-up sells what the swap delivered', (h) {
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();

      bloc.add(
        UnifiedSwapFollowUpRequested(pay: usdc, receive: eth, amount: '2950'),
      );
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.activeExecutionId, isNull);
      expect(
        (bloc.state.pay, bloc.state.receive, bloc.state.inputText),
        (usdc, eth, '2950'),
      );
      expect(h.routed.requests.last.amount, d('2950'));
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    });

    swapBlocTest('a refund follow-up leaves the receive side open', (h) {
      final bloc = h.open()..add(UnifiedSwapFollowUpRequested(pay: eth));
      h.settle();

      expect((bloc.state.pay, bloc.state.receive), (eth, null));
      expect(bloc.state.inputText, isEmpty);

      bloc.add(UnifiedSwapFollowUpRequested(pay: usdc, receive: usdc));
      h.settle();
      expect((bloc.state.pay, bloc.state.receive), (usdc, null));
    });
  });
}
