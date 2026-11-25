// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

import '../../support/legal_documents_fixture.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the review says about its latest re-price: every figure a
/// changed quote moved, old against new, and each status that needs the
/// user said once.
///
/// Status copy is looked up by key, so rewording it does not read as a
/// broken review; figures are asserted as written.
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

  Future<void> pump(
    WidgetTester tester,
    SwapQuote quote, {
    SwapReviewStatus status = SwapReviewStatus.ready,
    SwapQuote? previous,
  }) async {
    swap.emit(
      swapPricedForm(ranked: [quote]).copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(
          legalSnapshot: legalFixtureSnapshot(),
          quote: quote,
          status: status,
          previous: previous,
        ),
      ),
    );
    await pumpSwapUi(
      tester,
      const SwapReviewView(),
      bloc: swap,
      services: services,
      size: const Size(420, 2400),
      // The footer's spinner never settles while the quote is re-checked.
      settle: status != SwapReviewStatus.revalidating,
    );
  }

  /// The label, old value and new value of the changed figure [id].
  List<String?> changed(WidgetTester tester, String id) => [
    for (final text in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(Key('swap-review-change-$id')),
        matching: find.byType(Text),
      ),
    ))
      text.data,
  ];

  final changeRows = find.byWidgetPredicate(
    (widget) =>
        widget.key is ValueKey<String> &&
        (widget.key! as ValueKey<String>).value.startsWith(
          'swap-review-change-',
        ),
  );

  group('the latest re-price', () {
    // Looked up as the test runs: the strings load with the first frame.
    Finder title() => find.text(LocaleKeys.swapReviewUpdatedTitle.tr());

    testWidgets('an update gives the minimum and the cost, old and new', (
      tester,
    ) async {
      await pump(
        tester,
        quoteOf(
          guaranteed: '2900',
          pricing: pricingOf(minimum: '2900', network: '5'),
        ),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(),
      );

      expect(title(), findsOneWidget);
      expect(changed(tester, 'minimum'), [
        LocaleKeys.swapMinimumReceived.tr(),
        '2,985 USDC',
        '2,900 USDC',
      ]);
      expect(changed(tester, 'cost'), [
        LocaleKeys.swapTotalCost.tr(),
        r'$3.00',
        r'$5.00',
      ]);
      expect(changeRows, findsNWidgets(2));
    });

    testWidgets('an update of the cost alone says only that', (tester) async {
      await pump(
        tester,
        quoteOf(pricing: pricingOf(network: '5')),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(),
      );

      expect(changed(tester, 'cost'), [
        LocaleKeys.swapTotalCost.tr(),
        r'$3.00',
        r'$5.00',
      ]);
      expect(changeRows, findsOneWidget);
    });

    testWidgets('an update lists the expected amount when that moved too', (
      tester,
    ) async {
      await pump(
        tester,
        quoteOf(expected: '2950', guaranteed: '2935'),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(),
      );

      expect(changed(tester, 'expected'), [
        LocaleKeys.swapYouReceive.tr(),
        '3,000 USDC',
        '2,950 USDC',
      ]);
      expect(changed(tester, 'minimum'), [
        LocaleKeys.swapMinimumReceived.tr(),
        '2,985 USDC',
        '2,935 USDC',
      ]);
      expect(changeRows, findsNWidgets(2));
    });

    testWidgets('a cost that was unknown is not compared', (tester) async {
      await pump(
        tester,
        quoteOf(
          guaranteed: '2900',
          pricing: pricingOf(minimum: '2900'),
        ),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(pricing: pricingOf(network: null)),
      );

      expect(changed(tester, 'minimum').skip(1), ['2,985 USDC', '2,900 USDC']);
      expect(changeRows, findsOneWidget);
    });

    testWidgets('a change too small for the usual precision still reads '
        'as one', (tester) async {
      await pump(
        tester,
        quoteOf(
          guaranteed: '2985.1234',
          pricing: pricingOf(network: '3.004'),
        ),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(
          guaranteed: '2985.1291',
          pricing: pricingOf(network: '3.001'),
        ),
      );

      // The minimum gets the decimals that tell it apart; a cost is shown
      // in cents, so a change within one is left out.
      expect(changed(tester, 'minimum').skip(1), [
        '2,985.129 USDC',
        '2,985.123 USDC',
      ]);
      expect(changeRows, findsOneWidget);
    });

    testWidgets('an update with no figure to show still says the quote '
        'changed, never an empty notice', (tester) async {
      for (final previous in [quoteOf(), null]) {
        await pump(
          tester,
          quoteOf(),
          status: SwapReviewStatus.materialUpdate,
          previous: previous,
        );

        expect(title(), findsOneWidget);
        expect(changeRows, findsNothing);
        final callout = tester.widget<SwapCallout>(
          find.byKey(const Key('swap-review-changed')),
        );
        expect(callout.message, 'swapReviewUpdatedFallback'.tr());
        expect(callout.message.trim(), isNotEmpty);
      }
    });

    testWidgets('an update is read out whole: its title and every change', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        quoteOf(
          guaranteed: '2900',
          pricing: pricingOf(minimum: '2900', network: '5'),
        ),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(),
      );

      final node = tester.getSemantics(
        find.byKey(const Key('swap-review-changed')),
      );
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(node.label, contains(LocaleKeys.swapReviewUpdatedTitle.tr()));
      for (final spoken in [
        'swapReviewUpdatedSpoken'.tr(
          args: [
            LocaleKeys.swapMinimumReceived.tr(),
            '2,985 USDC',
            '2,900 USDC',
          ],
        ),
        'swapReviewUpdatedSpoken'.tr(
          args: [LocaleKeys.swapTotalCost.tr(), r'$3.00', r'$5.00'],
        ),
      ]) {
        expect(node.label, contains(spoken));
      }
      handle.dispose();
    });

    for (final (status, heading, body) in [
      (
        SwapReviewStatus.expired,
        LocaleKeys.swapReviewExpiredTitle,
        LocaleKeys.swapReviewExpiredBody,
      ),
      (
        SwapReviewStatus.revalidationFailed,
        LocaleKeys.swapReviewFailedTitle,
        LocaleKeys.swapReviewFailedBody,
      ),
      (
        SwapReviewStatus.rejected,
        LocaleKeys.swapReviewRejectedTitle,
        LocaleKeys.swapReviewRejectedBody,
      ),
    ]) {
      testWidgets('${status.name} is explained once, in a callout', (
        tester,
      ) async {
        await pump(tester, quoteOf(), status: status);

        expect(find.text(heading.tr()), findsOneWidget);
        expect(find.text(body.tr()), findsOneWidget);
        expect(find.byType(SwapBadge), findsNothing);
      });
    }

    testWidgets('a check in progress says starting waits for it, aloud', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pump(tester, quoteOf(), status: SwapReviewStatus.revalidating);

      final line = find.text(LocaleKeys.swapReviewRevalidatingBody.tr());
      expect(line, findsOneWidget);
      expect(
        tester
            .getSemantics(
              find.ancestor(of: line, matching: find.byType(SwapHelperLine)),
            )
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('a ready review has nothing to explain', (tester) async {
      await pump(tester, quoteOf());

      expect(find.byType(SwapCallout), findsNothing);
      expect(
        find.text(LocaleKeys.swapReviewRevalidatingBody.tr()),
        findsNothing,
      );
    });
  });

  group('a balance to keep available', () {
    SwapQuote funded(String held, {String guaranteed = '2985'}) {
      final base = quoteOf(guaranteed: guaranteed);
      return SwapQuote(
        id: base.id,
        source: base.source,
        routeKind: base.routeKind,
        order: base.order,
        from: base.from,
        to: base.to,
        sellAmount: base.sellAmount,
        expectedReceive: base.expectedReceive,
        guaranteedReceive: base.guaranteedReceive,
        fees: base.fees,
        stages: base.stages,
        estimatedDuration: base.estimatedDuration,
        quotedAt: base.quotedAt,
        pricing: base.pricing,
        requiredFeeBalances: <AssetId, Decimal>{eth: d(held)},
      );
    }

    // The bloc asks again for this alone, which used to leave the notice
    // with a title and nothing under it.
    testWidgets('a balance the swap now needs more of is a change of its '
        'own', (tester) async {
      await pump(
        tester,
        funded('0.004'),
        status: SwapReviewStatus.materialUpdate,
        previous: funded('0.002'),
      );

      expect(changed(tester, 'funding-ETH'), [
        'swapReviewRequiredFunding'.tr(args: ['ETH']),
        '0.002 ETH',
        '0.004 ETH',
      ]);
      expect(
        tester
            .widget<SwapCallout>(find.byKey(const Key('swap-review-changed')))
            .message,
        'swapReviewUpdatedIntro'.tr(),
      );
    });

    testWidgets('one that fell is not raised as a warning', (tester) async {
      await pump(
        tester,
        funded('0.001', guaranteed: '2900'),
        status: SwapReviewStatus.materialUpdate,
        previous: funded('0.002'),
      );

      expect(
        find.byKey(const Key('swap-review-change-funding-ETH')),
        findsNothing,
      );
      expect(changed(tester, 'minimum').skip(1), ['2,985 USDC', '2,900 USDC']);
    });
  });
}
