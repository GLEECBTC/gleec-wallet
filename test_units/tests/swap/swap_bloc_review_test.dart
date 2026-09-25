import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the review: when it opens, what closing it does, and how a price
/// that expired or could not be confirmed is re-priced in place.
void main() {
  group('opening the review', () {
    swapBlocTest('waits for an option that can be reviewed', (h) {
      final bloc = h.open(amount: '')..add(const UnifiedSwapReviewOpened());
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
    });

    swapBlocTest('an order-book option asks for no provider terms', (h) {
      h.routed
        ..respond = null
        ..results = [rejected(SwapQuoteFailureKind.noRoute)];
      h.atomic.results = [
        SwapQuoteAvailable(
          quoteOf(
            id: 'book',
            source: SwapLiquiditySource.atomic,
            routeKind: SwapRouteKind.direct,
            order: null,
            quotedAt: h.now(),
          ),
        ),
      ];
      final bloc = h.inReview();

      expect(bloc.state.review!.quote.id, 'book');
      expect(bloc.state.review!.termsRequired, isFalse);
    });

    swapBlocTest('terms accepted before are not asked for again', (h) {
      h.resolve(h.terms.recordAcceptance(at: h.now()));
      final bloc = h.inReview();

      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review!.termsRequired, isFalse);
    });

    swapBlocTest('an option replaced while terms are read is not shown', (h) {
      final bloc = h.open();
      h.termsGate = Completer<void>();
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();
      bloc.add(const UnifiedSwapAmountChanged('0.5'));
      h.settle();

      h.termsGate!.complete();
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect(bloc.state.selectedQuote!.sellAmount, d('0.5'));
    });

    swapBlocTest('a price that went stale unseen opens as expired', (h) {
      final bloc = h.open();
      h.skew = SwapQuote.lifetime;
      bloc.add(const UnifiedSwapReviewOpened());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(bloc.state.review!.canStart, isFalse);
    });
  });

  group('closing the review', () {
    swapBlocTest('returns to the form and keeps its price fresh', (h) {
      final bloc = h.inReview();
      h.elapse(const Duration(seconds: 10));
      bloc.add(const UnifiedSwapReviewClosed());
      h.elapse(const Duration(seconds: 29));

      expect(bloc.state.view, UnifiedSwapView.form);
      expect(bloc.state.review, isNull);
      expect(h.routed.requests, hasLength(1));

      h.elapse(const Duration(seconds: 1));
      expect(h.routed.requests, hasLength(2));
    });

    swapBlocTest('on a price that expired in review prices again', (h) {
      final bloc = h.inReview();
      h.elapse(SwapQuote.lifetime);
      expect(bloc.state.review!.status, SwapReviewStatus.expired);

      bloc.add(const UnifiedSwapReviewClosed());
      h.settle();

      expect(h.routed.requests, hasLength(2));
      expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
      expect(bloc.state.selectedQuote!.quotedAt, h.now());
    });

    swapBlocTest('is refused while the swap is being started', (h) {
      h.routedExecutor.gate = Completer<void>();
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.starting);

      bloc.add(const UnifiedSwapReviewClosed());
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.review);

      h.routedExecutor.gate!.complete();
      h.settle();
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('after a start that may be running, never offers it again', (
      h,
    ) {
      h.routedExecutor.startError = SwapStartUnconfirmedException(
        TimeoutException('lost'),
      );
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.unconfirmed);

      bloc.add(const UnifiedSwapReviewClosed());
      h.settle();

      expect(bloc.state.canReview, isFalse);
    });
  });

  group('refreshing in the review', () {
    SwapQuote lowerMinimum(SwapBlocHarness h) =>
        quoteOf(id: 'fresh', guaranteed: '2900', quotedAt: h.now());

    swapBlocTest('re-prices an expired route in place, never starting', (h) {
      final bloc = h.inReview();
      h.elapse(SwapQuote.lifetime);
      final reviewed = bloc.state.review!.quote;
      h.routed.requoteResult = SwapQuoteAvailable(lowerMinimum(h));
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted.single, reviewed);
      expect(h.routedExecutor.started, isEmpty);
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      expect(bloc.state.review!.previous, reviewed);
    });

    swapBlocTest('says why a re-price was refused, and tries again', (h) {
      final bloc = h.inReview();
      h.routed.requoteResult = const SwapQuoteRejected(
        SwapQuoteFailure(
          source: SwapLiquiditySource.routed,
          kind: SwapQuoteFailureKind.noRoute,
          detail: 'no route now',
        ),
      );
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(bloc.state.review!.rejectionDetail, 'no route now');
      expect(h.routedExecutor.started, isEmpty);

      h.routed.requoteResult = SwapQuoteAvailable(lowerMinimum(h));
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(h.routed.requoted, hasLength(2));
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
    });

    swapBlocTest('a re-price that never answers fails at the time limit', (h) {
      final bloc = h.inReview();
      h.routed.requoteGate = Completer<void>();
      bloc.add(const UnifiedSwapStartRequested());
      h.elapse(const Duration(seconds: 24));
      expect(bloc.state.review!.status, SwapReviewStatus.revalidating);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);
      expect(bloc.state.review!.rejectionDetail, isNull);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('an unchanged price after Refresh can be started', (h) {
      final bloc = h.inReview();
      h.elapse(SwapQuote.lifetime);
      h.routed.requoteResult = SwapQuoteAvailable(
        quoteOf(id: 'fresh', quotedAt: h.now()),
      );
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.quote.id, 'fresh');
    });

    swapBlocTest(
      'updated numbers accepted after they expire are re-priced first',
      (h) {
        final bloc = h.inReview();
        h.routed.requoteResult = SwapQuoteAvailable(lowerMinimum(h));
        bloc.add(const UnifiedSwapStartRequested());
        h.settle();
        expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);

        h.elapse(const Duration(minutes: 5));
        bloc.add(const UnifiedSwapStartRequested());
        h.settle();

        expect(h.routed.requoted, hasLength(2));
      },
    );
  });
}
