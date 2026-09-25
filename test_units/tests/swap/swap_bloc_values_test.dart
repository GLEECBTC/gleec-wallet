import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/swap_execution/swap_execution_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers the swap blocs' events and review state as values: equal when
/// every field is, told apart by any one field, as de-duplication and
/// state comparisons rely on.
void main() {
  // Built from runtime values so no two events are the same const instance.
  final texts = ['1', '2'];
  final flags = [true, false];
  final assets = [eth, btc];
  final quotes = [quoteOf(id: 'a'), quoteOf(id: 'b')];

  final byField = <String, Object Function(int i)>{
    'intent pay': (i) => UnifiedSwapIntentApplied(pay: texts[i]),
    'intent receive': (i) => UnifiedSwapIntentApplied(receive: texts[i]),
    'intent amount': (i) => UnifiedSwapIntentApplied(amount: texts[i]),
    'pay asset': (i) => UnifiedSwapPayAssetChanged(assets[i]),
    'receive asset': (i) => UnifiedSwapReceiveAssetChanged(assets[i]),
    'amount': (i) => UnifiedSwapAmountChanged(texts[i]),
    'quiet evaluation': (i) => UnifiedSwapEvaluationRequested(quiet: flags[i]),
    'option': (i) => UnifiedSwapOptionSelected(texts[i]),
    'fresh quote': (i) => UnifiedSwapFreshQuoteAccepted(quotes[i]),
    'reset keeping the pair': (i) =>
        UnifiedSwapResetRequested(keepPair: flags[i]),
    'follow-up pay': (i) => UnifiedSwapFollowUpRequested(pay: assets[i]),
    'follow-up receive': (i) =>
        UnifiedSwapFollowUpRequested(pay: eth, receive: assets[i]),
    'follow-up amount': (i) =>
        UnifiedSwapFollowUpRequested(pay: eth, amount: texts[i]),
    'visibility': (i) => UnifiedSwapVisibilityChanged(visible: flags[i]),
    'trading enabled': (i) => UnifiedSwapCapabilitiesChanged(
      tradingEnabled: flags[i],
      clockValid: true,
    ),
    'clock valid': (i) => UnifiedSwapCapabilitiesChanged(
      tradingEnabled: true,
      clockValid: flags[i],
    ),
    'activated asset': (i) => UnifiedSwapAssetActivated(assets[i]),
    'slippage': (i) => UnifiedSwapSlippageChanged([0.005, 0.01][i]),
    'foreground': (i) => UnifiedSwapForegroundChanged(foreground: flags[i]),
    'timer': (i) => UnifiedSwapTimerFired(UnifiedSwapTimerKind.values[i]),
    'activity start view': (i) =>
        SwapActivityStarted(filter: SwapActivityFilter.values[i]),
    'activity view': (i) =>
        SwapActivityFilterChanged(SwapActivityFilter.values[i]),
    'watched swap': (i) => SwapExecutionWatched(texts[i]),
    'watched source': (i) =>
        SwapExecutionWatched('1', source: SwapLiquiditySource.values[i]),
    'watched snapshot': (i) =>
        SwapExecutionWatched('1', initial: snapshotOf(id: texts[i])),
  };

  test('events are equal by value and told apart by any field', () {
    for (final MapEntry(key: field, value: make) in byField.entries) {
      expect(make(0), make(0), reason: field);
      expect(make(0).hashCode, make(0).hashCode, reason: field);
      expect(make(0), isNot(make(1)), reason: field);
    }
  });

  test('events without fields are equal only to their own kind', () {
    final events = <Object>{
      const UnifiedSwapStarted(),
      const UnifiedSwapSidesSwitched(),
      const UnifiedSwapAmountModeToggled(),
      const UnifiedSwapMaxRequested(),
      const UnifiedSwapReviewOpened(),
      const UnifiedSwapReviewClosed(),
      const UnifiedSwapStartRequested(),
      const UnifiedSwapProgressLeft(),
      const UnifiedSwapBalancesRefreshed(),
      const UnifiedSwapCatalogRefreshRequested(),
      const UnifiedSwapAlternativesRequested(),
      const SwapActivityRefreshed(),
      const SwapActivityMoreRequested(),
      const SwapExecutionCancelRequested(),
    };

    expect(events, hasLength(14));
  });

  group('a review', () {
    final review = SwapReview(
      quote: quoteOf(id: 'new'),
      status: SwapReviewStatus.materialUpdate,
      previous: quoteOf(id: 'old'),
      termsRequired: true,
      rejectionDetail: 'detail',
    );

    test('copies keep every field they are not told to change', () {
      final copy = review.copyWith(quote: quoteOf(id: 'newer'));

      expect(copy.quote.id, 'newer');
      expect(copy.status, SwapReviewStatus.materialUpdate);
      expect(copy.previous!.id, 'old');
      expect(copy.termsRequired, isTrue);
      expect(copy.rejectionDetail, 'detail');
      expect(review.copyWith(), review);
    });

    test('a copy can drop the numbers first consented to', () {
      expect(review.copyWith(clearPrevious: true).previous, isNull);
    });

    test('only a ready or updated review can start', () {
      expect(
        {
          for (final status in SwapReviewStatus.values)
            if (review.copyWith(status: status).canStart) status,
        },
        {SwapReviewStatus.ready, SwapReviewStatus.materialUpdate},
      );
    });
  });

  test('options list ranked ones first, and none before pricing', () {
    final state = UnifiedSwapState(
      quotes: UnifiedSwapQuotes(
        ranked: [quoteOf(id: 'ranked')],
        unrankable: [quoteOf(id: 'unpriced')],
        failures: const [],
      ),
    );

    expect(const UnifiedSwapState().options, isEmpty);
    expect(state.options.map((q) => q.id), ['ranked', 'unpriced']);
  });
}
