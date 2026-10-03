// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/pickers/swap_options_sheet.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what a rate-limited cross-network source looks like: never an
/// error that a retry fixes at once, honest about how long it lasts, and
/// never hiding what the order book did answer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;
  late FakeSwapServices services;

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
  });

  tearDown(() => swap.close());

  const limited = SwapQuoteFailure(
    source: SwapLiquiditySource.routed,
    kind: SwapQuoteFailureKind.rateLimited,
  );
  const pausedLine =
      'Cross-network prices are paused while the price service limits '
      'requests, which can take up to two hours.';
  final ongoing = DateTime(2100);
  final over = DateTime(2000);

  Future<void> pump(
    WidgetTester tester,
    Widget child,
    UnifiedSwapState state,
  ) async {
    swap.emit(state);
    await pumpSwapUi(tester, child, bloc: swap, services: services);
  }

  bool enabled(WidgetTester tester, String label) =>
      swapButtonEnabled(tester, find.text(label));

  SwapTone toneOf(WidgetTester tester, String text) => tester
      .widget<SwapHelperLine>(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(SwapHelperLine),
        ),
      )
      .tone;

  group('behind an order-book miss', () {
    const miss = SwapQuoteFailure(
      source: SwapLiquiditySource.atomic,
      kind: SwapQuoteFailureKind.noRoute,
    );

    UnifiedSwapState failed(SwapQuoteFailure primary, DateTime until) =>
        swapBaseForm().copyWith(
          evaluation: SwapEvaluationStatus.failed,
          failure: primary,
          failures: [primary, limited],
          rateLimitedUntil: until,
        );

    testWidgets('says what the book found, and holds Try again', (
      tester,
    ) async {
      await pump(tester, const SwapEntryView(), failed(miss, ongoing));

      const found = 'No order-book offer fits this amount right now.';
      expect(find.text(found), findsOneWidget);
      expect(toneOf(tester, found), SwapTone.warning);
      expect(find.text(pausedLine), findsOneWidget);
      expect(find.textContaining('Try again in a moment'), findsNothing);
      expect(swapPrimaryLabel(tester), 'Try again');
      expect(enabled(tester, 'Try again'), isFalse);
    });

    testWidgets('once the pause is over, Try again asks again', (tester) async {
      await pump(tester, const SwapEntryView(), failed(miss, over));

      expect(enabled(tester, 'Try again'), isTrue);
      await tester.tap(swapPrimaryAction);
      await tester.pumpAndSettle();
      expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
    });

    testWidgets('keeps an amount the offers take one tap away', (tester) async {
      final gap = SwapQuoteFailure(
        source: SwapLiquiditySource.atomic,
        kind: SwapQuoteFailureKind.noRoute,
        offers: SwapOrderBookOffers([
          SwapOfferBand(d('0.5'), d('0.8')),
          SwapOfferBand(d('1.5'), d('4')),
        ]),
      );
      await pump(tester, const SwapEntryView(), failed(gap, ongoing));

      expect(find.textContaining('No single offer takes'), findsOneWidget);
      expect(find.text(pausedLine), findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Use 0.8 ETH');
      expect(enabled(tester, 'Use 0.8 ETH'), isTrue);
    });
  });

  testWidgets('with the order book unanswered too, Try again asks it now', (
    tester,
  ) async {
    const unanswered = SwapQuoteFailure(
      source: SwapLiquiditySource.atomic,
      kind: SwapQuoteFailureKind.timeout,
    );
    await pump(
      tester,
      const SwapEntryView(),
      swapBaseForm().copyWith(
        evaluation: SwapEvaluationStatus.failed,
        failure: limited,
        failures: [limited, unanswered],
        rateLimitedUntil: ongoing,
      ),
    );

    expect(
      find.text(
        "Order-book prices couldn't be checked, and cross-network prices are "
        'paused while the price service limits requests. Try again to check '
        'order-book prices.',
      ),
      findsOneWidget,
    );
    expect(enabled(tester, 'Try again'), isTrue);
  });

  testWidgets('an amount under the smallest offer is a warning while paused', (
    tester,
  ) async {
    final below = SwapQuoteFailure(
      source: SwapLiquiditySource.atomic,
      kind: SwapQuoteFailureKind.belowMinimum,
      minimum: d('1.5'),
      offers: SwapOrderBookOffers([SwapOfferBand(d('1.5'), d('4'))]),
    );
    await pump(
      tester,
      const SwapEntryView(),
      swapBaseForm().copyWith(
        evaluation: SwapEvaluationStatus.failed,
        failure: below,
        failures: [below, limited],
        rateLimitedUntil: ongoing,
      ),
    );

    const smallest = 'The smallest offer right now takes 1.5 ETH.';
    expect(toneOf(tester, smallest), SwapTone.warning);
    expect(find.text(pausedLine), findsOneWidget);
  });

  testWidgets('beside order-book prices, says those still work', (
    tester,
  ) async {
    final book = quoteOf(
      id: 'book',
      source: SwapLiquiditySource.atomic,
      routeKind: SwapRouteKind.direct,
      order: null,
    );
    await pump(
      tester,
      const SwapEntryView(),
      swapPricedForm(ranked: [book], failures: const [limited]),
    );

    expect(
      find.text(
        'Cross-network prices are paused while the price service limits '
        'requests, which can take up to two hours. Order-book swaps still '
        'work.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the comparison says why no cross-network option is listed', (
    tester,
  ) async {
    await pump(
      tester,
      const SwapOptionsSheet(),
      swapPricedForm(failures: const [limited]),
    );

    expect(find.text(pausedLine), findsOneWidget);
  });

  group('a review whose price could not be confirmed', () {
    UnifiedSwapState reviewing(SwapQuoteFailure failure, {DateTime? until}) =>
        swapPricedForm().copyWith(
          view: UnifiedSwapView.review,
          rateLimitedUntil: until,
          review: SwapReview(
            quote: quoteOf(),
            status: SwapReviewStatus.revalidationFailed,
            revalidationFailure: failure,
          ),
        );

    testWidgets('for the rate limit, says how long and holds Try again', (
      tester,
    ) async {
      await pump(
        tester,
        const SwapReviewView(),
        reviewing(limited, until: ongoing),
      );

      expect(find.text('Price check paused'), findsOneWidget);
      expect(
        find.text(
          "The price service is limiting requests, so this price can't be "
          'confirmed yet. This can take up to two hours. Nothing has been '
          'signed or sent.',
        ),
        findsOneWidget,
      );
      expect(enabled(tester, 'Try again'), isFalse);
    });

    testWidgets('for the rate limit, lets Try again ask once it is over', (
      tester,
    ) async {
      await pump(
        tester,
        const SwapReviewView(),
        reviewing(limited, until: ongoing),
      );
      // The pause ends by clearing only the time, as the bloc's timer does.
      await emitSwapState(
        tester,
        swap,
        swap.state.copyWith(clearRateLimit: true),
      );

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(swap.events, [const UnifiedSwapStartRequested()]);
    });

    testWidgets('because the route is gone, goes back instead of retrying', (
      tester,
    ) async {
      await pump(
        tester,
        const SwapReviewView(),
        reviewing(
          const SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.noRoute,
          ),
        ),
      );

      expect(find.text('This price is no longer available'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      await tester.tap(find.text('Back to swap'));
      await tester.pumpAndSettle();
      expect(swap.events, [const UnifiedSwapReviewClosed()]);
    });

    testWidgets('for funds that no longer cover it, goes back plainly', (
      tester,
    ) async {
      await pump(
        tester,
        const SwapReviewView(),
        reviewing(
          SwapQuoteFailure(
            source: SwapLiquiditySource.atomic,
            kind: SwapQuoteFailureKind.insufficientFunds,
            asset: eth,
          ),
        ),
      );

      expect(find.text("This swap can't go ahead as reviewed"), findsOneWidget);
      expect(find.text('This price is no longer available'), findsNothing);
      expect(find.text('Back to swap'), findsOneWidget);
    });

    testWidgets('for a timeout, offers Try again at once', (tester) async {
      await pump(
        tester,
        const SwapReviewView(),
        reviewing(
          const SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: SwapQuoteFailureKind.timeout,
          ),
        ),
      );

      expect(find.text('Latest quote not confirmed'), findsWidgets);
      expect(enabled(tester, 'Try again'), isTrue);
    });
  });
}
