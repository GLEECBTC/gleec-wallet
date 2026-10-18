import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a price checked again in the review: a refresh that finds it
/// unchanged is ready to start, and every price under review, updated
/// numbers included, expires on its own clock and is re-priced before
/// anything starts.
void main() {
  /// A re-price with the numbers first reviewed, priced now.
  SwapQuoteAvailable unchanged(SwapBlocHarness h) =>
      SwapQuoteAvailable(quoteOf(id: 'fresh', quotedAt: h.now()));

  /// A re-price whose lower minimum needs consent, priced now.
  SwapQuoteAvailable lower(SwapBlocHarness h) => SwapQuoteAvailable(
    quoteOf(id: 'lower', guaranteed: '2900', quotedAt: h.now()),
  );

  group('a refresh that finds the price unchanged', () {
    swapBlocTest('is ready, and starting re-prices that price first', (h) {
      final bloc = h.inReview();
      h.elapse(SwapQuote.lifetime);
      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(h.routedExecutor.started, isEmpty);

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, hasLength(2));
      expect(h.routedExecutor.started.single.id, 'fresh');
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('expires again a minute after it was priced', (h) {
      final bloc = h.inReview();
      h.elapse(SwapQuote.lifetime);
      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      h.elapse(SwapQuote.lifetime - const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.ready);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(bloc.state.review!.quote.id, 'fresh');
    });

    swapBlocTest('after a refused start clears the refusal, starting nothing', (
      h,
    ) {
      h.routedExecutor.startError = const SwapStartRejectedException(
        SwapStartRejection.quoteStale,
        detail: 'stale',
      );
      final bloc = h.inReview()..add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.rejected);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.rejectionDetail, isNull);
      expect(h.routedExecutor.started, hasLength(1));
    });

    swapBlocTest('after a failed re-price keeps the terms to accept', (h) {
      final bloc = h.inReview();
      h.routed.requoteResult = rejected(SwapQuoteFailureKind.serviceError);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      expect(bloc.state.review!.status, SwapReviewStatus.revalidationFailed);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.termsRequired, isTrue);
      expect(h.routedExecutor.started, isEmpty);
    });
  });

  group('updated numbers', () {
    swapBlocTest('accepted while they stand start as shown', (h) {
      final bloc = h.inReview();
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      h.elapse(SwapQuote.lifetime - const Duration(seconds: 1));

      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, hasLength(1));
      expect(h.routedExecutor.started.single.id, 'lower');
    });

    swapBlocTest('expire a minute after they were priced', (h) {
      final bloc = h.inReview();
      h.elapse(const Duration(seconds: 30));
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      h.elapse(const Duration(seconds: 59));
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(bloc.state.review!.canStart, isFalse);
    });

    swapBlocTest('once expired are refreshed against the numbers agreed', (h) {
      final bloc = h.inReview();
      final agreed = bloc.state.review!.quote;
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      h.elapse(SwapQuote.lifetime);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, [agreed, agreed]);
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
      expect(bloc.state.review!.previous, isNull);
      expect(h.routedExecutor.started, isEmpty);
    });

    swapBlocTest('accepted after they went stale unseen are re-priced', (h) {
      final bloc = h.inReview();
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      // The device slept past the numbers' minute: no timer has run.
      h.skew = SwapQuote.lifetime;
      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, hasLength(2));
      expect(h.routedExecutor.started.single.id, 'fresh');
    });

    swapBlocTest('stale and moved again ask for consent once more', (h) {
      final bloc = h.inReview();
      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();
      h.skew = SwapQuote.lifetime;

      h.routed.requoteResult = lower(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(bloc.state.review!.status, SwapReviewStatus.materialUpdate);
      expect(bloc.state.review!.quote.quotedAt, h.now());
      expect(h.routedExecutor.started, isEmpty);
    });
  });

  group('numbers accepted for a swap the engine stopped', () {
    swapBlocTest('start at once while they stand', (h) {
      final bloc = h.open()
        ..add(
          UnifiedSwapFreshQuoteAccepted(
            quoteOf(id: 'agreed', quotedAt: h.now()),
          ),
        );
      h.settle();

      expect(h.routedExecutor.started.single.id, 'agreed');
      expect(bloc.state.view, UnifiedSwapView.progress);
    });

    swapBlocTest('once stale open as expired, to be refreshed first', (h) {
      final agreed = quoteOf(id: 'agreed', quotedAt: h.now());
      final bloc = h.open();
      h.elapse(SwapQuote.lifetime);
      bloc.add(UnifiedSwapFreshQuoteAccepted(agreed));
      h.settle();

      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
      expect(h.routedExecutor.started, isEmpty);

      h.routed.requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.settle();

      expect(h.routed.requoted, [agreed]);
      expect(bloc.state.review!.status, SwapReviewStatus.ready);
    });
  });

  group('the price under review', () {
    swapBlocTest('of an option priced later than the rest keeps its time', (h) {
      h.routed.respond = (request) => [
        SwapQuoteAvailable(
          quoteOf(
            id: 'older',
            quotedAt: h.now().subtract(const Duration(seconds: 20)),
          ),
        ),
        SwapQuoteAvailable(
          quoteOf(id: 'newer', guaranteed: '2980', quotedAt: h.now()),
        ),
      ];
      final bloc = h.open();
      expect(bloc.state.selectedId, 'older');
      bloc
        ..add(const UnifiedSwapOptionSelected('newer'))
        ..add(const UnifiedSwapReviewOpened());
      h.settle();

      h.elapse(const Duration(seconds: 59));
      expect(bloc.state.review!.status, SwapReviewStatus.ready);

      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.expired);
    });

    swapBlocTest('that expires while re-priced is left to the re-price', (h) {
      final bloc = h.inReview();
      h.elapse(const Duration(seconds: 59));
      h.routed
        ..requoteGate = Completer<void>()
        ..requoteResult = unchanged(h);
      bloc.add(const UnifiedSwapStartRequested());
      h.elapse(const Duration(seconds: 1));
      expect(bloc.state.review!.status, SwapReviewStatus.revalidating);

      h.routed.requoteGate!.complete();
      h.settle();

      expect(h.routedExecutor.started.single.id, 'fresh');
    });
  });
}
