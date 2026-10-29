import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the ways into a start, each of which must hold: none while trading
/// is off, none for a review that has been left or replaced, and none for an
/// option or slippage changed beside the review.
void main() {
  const tradingOff = UnifiedSwapCapabilitiesChanged(
    tradingEnabled: false,
    clockValid: true,
  );
  const policyLoading = UnifiedSwapCapabilitiesChanged(
    tradingEnabled: false,
    tradingStatusLoading: true,
    clockValid: true,
  );
  const tradingOn = UnifiedSwapCapabilitiesChanged(
    tradingEnabled: true,
    clockValid: true,
  );
  const policyUnavailable = UnifiedSwapCapabilitiesChanged(
    tradingEnabled: false,
    tradingStatusUnavailable: true,
    clockValid: true,
  );

  group('during a policy refresh', () {
    swapBlocTest('Max keeps its review and fee reserve without starting', (h) {
      h.routed.max = SwapMaxAmount(
        amount: d('1.99'),
        reservedForFees: d('0.01'),
      );
      final bloc = h.open()..add(const UnifiedSwapMaxRequested());
      h.settle();
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      final review = bloc.state.review!;
      final max = bloc.state.maxApplied;

      bloc
        ..add(policyLoading)
        ..add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review, same(review));
      expect(bloc.state.tradingEnabled, isFalse);
      expect(h.routed.requoted, isEmpty);

      bloc.add(tradingOn);
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review, same(review));
      expect(bloc.state.maxApplied, same(max));
      expect(bloc.state.review!.quote.sellAmount, d('1.99'));
      expect(bloc.state.tradingEnabled, isTrue);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('a resolved restriction still closes the review', (h) {
      final bloc = h.inReview()..add(policyLoading);
      h.settle();
      bloc.add(tradingOff);
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('failed lookups preserve an expired review for hours', (h) {
      final bloc = h.inReview();
      final quote = bloc.state.review!.quote;
      for (var minute = 0; minute < 180; minute++) {
        bloc.add(policyLoading);
        h.settle();
        bloc
          ..add(policyUnavailable)
          ..add(const UnifiedSwapStartRequested());
        h.elapse(const Duration(seconds: 5));
        expect(bloc.state.view, UnifiedSwapView.review);
        expect(bloc.state.tradingEnabled, isFalse);
        bloc.add(tradingOn);
        h.elapse(const Duration(seconds: 55));
      }

      expect(bloc.state.review!.quote, same(quote));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(h.routed.requests, hasLength(1));
      expect(h.routed.requoted, isEmpty);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('an interrupted re-price requires a new user action', (h) {
      final bloc = h.inReview();
      final quote = bloc.state.review!.quote;
      h.routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidating);
      bloc.add(policyLoading);
      h.settle();
      bloc.add(tradingOn);
      h.settle();
      h.routed.requoteGate!.complete();
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review!.quote, same(quote));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(h.routedExecutor.started, isEmpty);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('signing out still discards the review', (h) {
      final bloc = h.inReview()..add(policyLoading);
      h.settle();
      bloc.add(
        const UnifiedSwapCapabilitiesChanged(
          tradingEnabled: false,
          tradingStatusLoading: true,
          clockValid: true,
          signedIn: false,
        ),
      );
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect(h.routedExecutor.started, isEmpty);
    });
  });

  group('with trading turned off', () {
    swapBlocTest('an open review returns to the form, starting nothing', (h) {
      final bloc = h.inReview()..add(tradingOff);
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(h.routed.requoted, isEmpty);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('a re-price under way is not started', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(tradingOff);
      h.settle();

      h.routed.requoteGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
    });

    swapBlocTest('a start recording the terms stops before the engine', (h) {
      final bloc = h.inReview();
      h.termsGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.starting);
      bloc.add(tradingOff);
      h.settle();

      h.termsGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
    });

    swapBlocTest('a start the engine then refuses is not priced again', (h) {
      h.routedExecutor
        ..gate = Completer<void>()
        ..startError = const SwapStartRejectedException(
          SwapStartRejection.notAvailable,
        );
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(tradingOff);
      h.routedExecutor.gate!.complete();
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.rejected);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, hasLength(1));
    });

    swapBlocTest('a new price accepted from a stopped swap is not started', (
      h,
    ) {
      final bloc = h.open()
        ..add(tradingOff)
        ..add(
          UnifiedSwapFreshQuoteAccepted(
            quoteOf(id: 'agreed', quotedAt: h.now()),
          ),
        );
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.view, UnifiedSwapView.form);
    });
  });

  group('a start re-pricing', () {
    swapBlocTest('is dropped once a link changes the pair and another review '
        'opens', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      // Back in the browser, to a link for half as much, then its review.
      bloc.add(
        const UnifiedSwapIntentApplied(
          pay: 'ETH',
          receive: 'USDC-ERC20',
          amount: '0.5',
        ),
      );
      h.settle();
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      expect(bloc.state.review!.quote.sellAmount, d('0.5'));

      h.routed.requoteGate!.complete();
      h.settle();

      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.quote.sellAmount, d('0.5'));
    });

    swapBlocTest('keeps a new price accepted meanwhile from starting too', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      h.routedExecutor.gate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(
        UnifiedSwapFreshQuoteAccepted(quoteOf(id: 'agreed', quotedAt: h.now())),
      );
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidating);

      h.routed.requoteGate!.complete();
      h.settle();
      h.routedExecutor.gate!.complete();
      h.settle();

      expect(h.routedExecutor.started, hasLength(1));
      expect(h.routedExecutor.started.single.id, isNot('agreed'));
    });
  });

  group('an edit beside the open review', () {
    swapBlocTest('to another option closes the review, starting nothing', (h) {
      h.routed.respond = (request) => [
        SwapQuoteAvailable(quoteOf(id: 'a', quotedAt: h.now())),
        SwapQuoteAvailable(
          quoteOf(id: 'b', guaranteed: '2980', quotedAt: h.now()),
        ),
      ];
      final bloc = h.inReview();
      expect(bloc.state.review!.quote.id, 'a');

      bloc
        ..add(const UnifiedSwapOptionSelected('b'))
        ..add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect(bloc.state.selectedId, 'b');
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('renews an option already past its refresh age', (h) {
      h.routed.respond = (request) => [
        SwapQuoteAvailable(quoteOf(id: 'a', quotedAt: h.now())),
        SwapQuoteAvailable(
          quoteOf(id: 'b', guaranteed: '2980', quotedAt: h.now()),
        ),
      ];
      final bloc = h.inReview();
      h.elapse(const Duration(seconds: 55));
      expect(h.routed.requests, hasLength(1));

      bloc.add(const UnifiedSwapOptionSelected('b'));
      h.settle();

      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.selectedId, 'b');
    });

    swapBlocTest('to the same option leaves the review on its own clock', (h) {
      final bloc = h.inReview();
      h.elapse(const Duration(seconds: 30));
      h.routed.requoteResult = SwapQuoteAvailable(
        quoteOf(id: 'lower', guaranteed: '2900', quotedAt: h.now()),
      );
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);

      bloc.add(UnifiedSwapOptionSelected(bloc.state.selectedId!));
      h.elapse(SwapQuote.lifetime - const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
    });

    swapBlocTest('to the slippage closes the review and prices again', (h) {
      final bloc = h.inReview()
        ..add(const UnifiedSwapSlippageChanged(0.01))
        ..add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(h.routedExecutor.started, isEmpty);
      expect(h.routed.requests.last.slippage, 0.01);
      expect(bloc.state.selectedQuote, isNotNull);
    });

    swapBlocTest('waits while the reviewed start is under way', (h) {
      h.routedExecutor.gate = Completer<void>();
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();
      bloc.add(const UnifiedSwapSlippageChanged(0.01));
      h.settle();
      expect(bloc.state.slippage, swapDefaultSlippage);

      h.routedExecutor.gate!.complete();
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.progress);
    });
  });

  swapBlocTest('a new price accepted after a start that may be running is '
      'refused', (h) {
    h.routedExecutor.startError = SwapStartUnconfirmedException(
      TimeoutException('lost'),
    );
    final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
    h.settle();
    expect(bloc.state.review!.status, SwapReviewStatus.unconfirmed);
    h.routedExecutor.startError = null;

    bloc.add(
      UnifiedSwapFreshQuoteAccepted(quoteOf(id: 'agreed', quotedAt: h.now())),
    );
    h.settle();

    expect(h.routedExecutor.started, hasLength(1));
    expect(bloc.state.review?.status, SwapReviewStatus.unconfirmed);
  });
}
