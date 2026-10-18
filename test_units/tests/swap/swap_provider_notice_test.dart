// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/views/swap/entry/swap_quote_strip.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

const _attribution =
    'Routed through LI.FI, an independent third-party service.';

/// Covers naming the third party a routed swap goes through, with its
/// terms, wherever the swap is priced and reviewed.
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

  final orderBook = quoteOf(
    source: SwapLiquiditySource.atomic,
    routeKind: SwapRouteKind.direct,
    order: null,
  );

  Future<void> pumpStrip(WidgetTester tester, UnifiedSwapState state) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      BlocBuilder<UnifiedSwapBloc, UnifiedSwapState>(
        builder: (context, state) => SwapQuoteStrip(
          state: state,
          onCompare: () {},
          now: () => DateTime(2026, 9, 24, 12),
        ),
      ),
      bloc: swap,
      services: services,
    );
  }

  Future<void> pumpReview(
    WidgetTester tester,
    SwapQuote quote, {
    required bool termsRequired,
  }) async {
    swap.emit(
      swapPricedForm(ranked: [quote]).copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(
          quote: quote,
          status: SwapReviewStatus.ready,
          termsRequired: termsRequired,
        ),
      ),
    );
    await pumpSwapUi(
      tester,
      const SwapReviewView(),
      bloc: swap,
      services: services,
      size: const Size(420, 2400),
    );
  }

  Finder attribution() => find.textContaining(_attribution, findRichText: true);

  group('the quote under the form', () {
    testWidgets('names the provider of a routed swap and links its terms', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await pumpStrip(tester, swapPricedForm());

      expect(attribution(), findsOneWidget);
      await tester.tap(find.byKey(const Key('swap-strip-terms-link')));
      await tester.pumpAndSettle();
      expect(launched, [SwapTermsRepository.termsUrl]);
    });

    testWidgets('says nothing of a provider for an order-book swap', (
      tester,
    ) async {
      await pumpStrip(tester, swapPricedForm(ranked: [orderBook]));

      expect(attribution(), findsNothing);
      expect(find.byKey(const Key('swap-strip-terms-link')), findsNothing);
    });

    testWidgets('leaves it to the review while one is open beside it', (
      tester,
    ) async {
      final quote = quoteOf();
      await pumpStrip(
        tester,
        swapPricedForm(ranked: [quote]).copyWith(
          view: UnifiedSwapView.review,
          review: SwapReview(quote: quote, status: SwapReviewStatus.ready),
        ),
      );

      expect(attribution(), findsNothing);
    });
  });

  group('the review', () {
    testWidgets('names the provider on every routed swap, with one link', (
      tester,
    ) async {
      await pumpReview(tester, quoteOf(), termsRequired: false);

      expect(attribution(), findsOneWidget);
      expect(find.byKey(const Key('swap-terms-link')), findsOneWidget);
      // Accepted already: no acceptance on this one.
      expect(
        find.textContaining('By starting', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('adds the acceptance to a first routed swap, still with one '
        'link', (tester) async {
      await pumpReview(tester, quoteOf(), termsRequired: true);

      expect(attribution(), findsOneWidget);
      expect(
        find.textContaining('By starting', findRichText: true),
        findsOneWidget,
      );
      expect(find.byKey(const Key('swap-terms-link')), findsOneWidget);
    });

    testWidgets('says nothing of a provider for an order-book swap', (
      tester,
    ) async {
      await pumpReview(tester, orderBook, termsRequired: false);

      expect(attribution(), findsNothing);
    });
  });
}
