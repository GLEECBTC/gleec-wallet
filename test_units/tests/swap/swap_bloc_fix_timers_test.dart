import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_bloc_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a price shown again late in its life, after the app or the form was
/// out of sight or the review was open: it is renewed at once rather than
/// left to expire before its next refresh comes round.
void main() {
  swapBlocTest('the app brought back late renews the price at once', (h) {
    final bloc = h.open()
      ..add(const UnifiedSwapForegroundChanged(foreground: false));
    h.elapse(const Duration(seconds: 30));
    expect(h.routed.requests, hasLength(1));

    bloc.add(const UnifiedSwapForegroundChanged(foreground: true));
    h.settle();

    expect(h.routed.requests, hasLength(2));
    expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
    expect(bloc.state.selectedQuote!.quotedAt, h.now());
  });

  swapBlocTest('leaving the review late renews the price, then as usual', (h) {
    final bloc = h.inReview();
    h.elapse(const Duration(seconds: 45));
    bloc.add(const UnifiedSwapReviewClosed());
    h.settle();

    expect(h.routed.requests, hasLength(2));
    expect(bloc.state.selectedQuote!.quotedAt, h.now());

    h.elapse(const Duration(seconds: 29));
    expect(h.routed.requests, hasLength(2));

    h.elapse(const Duration(seconds: 1));
    expect(h.routed.requests, hasLength(3));
  });

  swapBlocTest('with more than an interval to live, the refresh waits', (h) {
    final bloc = h.open()
      ..add(const UnifiedSwapVisibilityChanged(visible: false));
    h.elapse(const Duration(seconds: 29));
    bloc.add(const UnifiedSwapVisibilityChanged(visible: true));
    h.settle();
    expect(h.routed.requests, hasLength(1));

    h.elapse(const Duration(seconds: 30));

    expect(h.routed.requests, hasLength(2));
    expect(bloc.state.evaluation, SwapEvaluationStatus.ready);
  });

  swapBlocTest('a late return during a rate-limit pause still waits', (h) {
    final bloc = h.open();
    h.routed
      ..respond = null
      ..results = [rejected(SwapQuoteFailureKind.rateLimited)];
    h.elapse(const Duration(seconds: 30));
    expect(bloc.state.rateLimitedUntil, isNotNull);

    bloc
      ..add(const UnifiedSwapVisibilityChanged(visible: false))
      ..add(const UnifiedSwapVisibilityChanged(visible: true));
    h.settle();

    expect(h.routed.requests, hasLength(2));
  });
}
