// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the review discloses: every cost, in dollars or else in
/// tokens, the protection, the route and the identities it touches, and
/// the warnings that apply before anything is signed.
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
    Size size = const Size(420, 2400),
    double textScale = 1,
  }) async {
    swap.emit(
      swapPricedForm(ranked: [quote]).copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(quote: quote, status: status, previous: previous),
      ),
    );
    await pumpSwapUi(
      tester,
      const SwapReviewView(),
      bloc: swap,
      services: services,
      size: size,
      textScale: textScale,
      // The footer's spinner never settles while the quote is re-checked.
      settle: status != SwapReviewStatus.revalidating,
    );
  }

  Future<void> expand(WidgetTester tester, String section) async {
    await tester.tap(find.text(section));
    await tester.pumpAndSettle();
  }

  /// The value beside [label] in a detail section.
  String detail(WidgetTester tester, String label) {
    final row = find.widgetWithText(SwapDetailRow, label);
    return tester.widget<SwapDetailRow>(row).value;
  }

  SwapFeeComponent fee(
    SwapFeeKind kind,
    String amount, {
    AssetId? asset,
    String? symbol,
  }) => SwapFeeComponent(
    kind: kind,
    amount: d(amount),
    deductedFromReceive: false,
    asset: asset,
    symbol: symbol,
  );

  group('costs', () {
    testWidgets('without dollar prices are given in tokens, per token', (
      tester,
    ) async {
      await pump(
        tester,
        quoteOf(
          fees: [
            fee(SwapFeeKind.network, '0.001', asset: eth),
            fee(SwapFeeKind.approvalNetwork, '0.0005', asset: eth),
            fee(SwapFeeKind.swap, '1.5', asset: usdc),
            fee(SwapFeeKind.dexFee, '0.5', asset: usdc),
            fee(SwapFeeKind.swap, '0.1', symbol: 'XYZ'),
          ],
          pricing: pricingOf(network: null, swap: null, complete: false),
        ),
      );
      await expand(tester, 'Costs & protection');

      expect(detail(tester, 'Network costs'), '0.0015 ETH');
      expect(detail(tester, 'Approval network cost'), '0.0005 ETH');
      expect(detail(tester, 'Swap costs'), '2 USDC + 0.1 XYZ');
      // Nothing priced in dollars, so no dollar total either.
      expect(find.text('Incomplete'), findsNWidgets(2));
    });

    testWidgets('with no fees at all cost nothing', (tester) async {
      await pump(
        tester,
        quoteOf(
          fees: const [],
          pricing: pricingOf(network: null, swap: null, complete: false),
        ),
      );
      await expand(tester, 'Costs & protection');

      expect(detail(tester, 'Network costs'), r'$0.00');
      expect(detail(tester, 'Swap costs'), r'$0.00');
      expect(find.text('Approval network cost'), findsNothing);
    });

    testWidgets('priced in dollars round up to the cent', (tester) async {
      await pump(
        tester,
        quoteOf(
          approval: SwapApprovalRequirement(
            asset: eth,
            exactAmount: d('1'),
            resetsFirst: false,
          ),
          fees: [
            fee(SwapFeeKind.network, '0.001', asset: eth),
            fee(SwapFeeKind.approvalNetwork, '0.0004', asset: eth),
          ],
          pricing: pricingOf(network: '4.201', approval: '1.2', swap: '0.5'),
        ),
      );
      await expand(tester, 'Costs & protection');

      expect(detail(tester, 'Network costs'), r'$4.21');
      expect(detail(tester, 'Approval network cost'), r'$1.20');
      expect(detail(tester, 'Swap costs'), r'$0.50');
      expect(
        detail(tester, 'Minimum guard'),
        'Stops before anything is sent if the latest price would pay less '
        'than the minimum',
      );
    });

    for (final (name, quote, slippage) in [
      (
        'a cross-network route gives its slippage',
        quoteWith(quoteOf(), slippage: 0.005),
        '0.5%',
      ),
      (
        'a route that reported none has none',
        quoteOf(),
        'None — fills at the quoted price or not at all',
      ),
      (
        'the order book has none',
        quoteWith(
          quoteOf(
            source: SwapLiquiditySource.atomic,
            routeKind: SwapRouteKind.direct,
          ),
          slippage: 0.01,
        ),
        'None — fills at the quoted price or not at all',
      ),
    ]) {
      testWidgets('slippage: $name', (tester) async {
        await pump(tester, quote);
        await expand(tester, 'Costs & protection');
        expect(detail(tester, 'Slippage'), slippage);
      });
    }
  });

  group('route and identities', () {
    testWidgets('read the route step by step, and name each asset', (
      tester,
    ) async {
      const contract = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
      services.contracts = {usdc: contract};
      await pump(tester, quoteOf());
      await expand(tester, 'Route & identities');

      expect(
        detail(tester, 'How it completes'),
        'Preparing → Sending on Ethereum → Receive USDC',
      );
      expect(detail(tester, 'Source asset'), 'Native ETH · Ethereum');
      expect(find.text('Destination asset · USDC · Ethereum'), findsOneWidget);
      expect(find.text(contract), findsOneWidget);
    });

    for (final (kind, label) in [
      (SwapRouteKind.sameChain, 'Same network'),
      (SwapRouteKind.crossChain, 'Across networks'),
      (SwapRouteKind.direct, 'Direct exchange'),
    ]) {
      testWidgets('give the route\'s kind when no steps are known: $label', (
        tester,
      ) async {
        await pump(tester, quoteOf(routeKind: kind, stages: const []));
        await expand(tester, 'Route & identities');
        expect(detail(tester, 'How it completes'), label);
      });
    }

    testWidgets('list both addresses in full, each to copy', (tester) async {
      const from = '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91';
      const to = '0x80A1c2d4E5f60718293a4B5c6D7e8F9012A342F0';
      final copied = recordClipboard(tester);
      await pump(
        tester,
        quoteWith(quoteOf(), fromAddress: from, toAddress: to),
      );
      await expand(tester, 'Route & identities');

      expect(find.text('Source address'), findsOneWidget);
      expect(find.text('Receiving address'), findsOneWidget);
      expect(find.text(from), findsOneWidget);
      expect(find.text(to), findsOneWidget);

      await tester.tap(find.text('Copy').first);
      await tester.pumpAndSettle();
      expect(copied, [from]);
      expect(find.text('Source address copied'), findsOneWidget);
    });
  });

  group('warnings', () {
    const multiStep = 'This swap completes in several steps';

    testWidgets('a move across networks is several steps', (tester) async {
      await pump(tester, quoteOf(routeKind: SwapRouteKind.crossChain));

      expect(find.text(multiStep), findsOneWidget);
      expect(
        find.text(
          "Completed steps can't be reversed. If a later step stops, "
          'Activity shows the last confirmed location.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('so are two conversions on one network, but not one', (
      tester,
    ) async {
      SwapQuote converting(int times) => quoteOf(
        stages: [
          for (var i = 0; i < times; i++)
            const SwapRouteStage(kind: SwapRouteStageKind.convert),
        ],
      );
      await pump(tester, converting(2));
      expect(find.text(multiStep), findsOneWidget);

      await pump(tester, converting(1));
      expect(find.text(multiStep), findsNothing);
    });

    testWidgets('a high price impact is called out', (tester) async {
      await pump(tester, quoteOf(pricing: pricingOf(expected: '2800')));

      expect(find.text('High price impact'), findsOneWidget);
      expect(
        find.text(
          'You may receive substantially less than the current market '
          'estimate. Review the minimum carefully.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('without a market price, what is still known is said', (
      tester,
    ) async {
      await pump(tester, quoteOf(pricing: pricingOf(expected: null)));

      expect(find.text('Price estimate unavailable'), findsOneWidget);
      expect(
        find.text(
          'Token amounts, minimum received, and costs are available, but a '
          'market estimate is not.',
        ),
        findsOneWidget,
      );
      expect(find.text('High price impact'), findsNothing);
    });
  });

  group('the latest re-price', () {
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

      expect(find.text('Outcome updated'), findsOneWidget);
      expect(
        find.text(
          r'Minimum changed from 2,985 USDC to 2,900 USDC. Total cost '
          r'changed from $3.00 to $5.00.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('an update of the cost alone says only that', (tester) async {
      await pump(
        tester,
        quoteOf(pricing: pricingOf(network: '5')),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(),
      );

      expect(
        find.text(r'Total cost changed from $3.00 to $5.00.'),
        findsOneWidget,
      );
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

      expect(
        find.text('Minimum changed from 2,985 USDC to 2,900 USDC.'),
        findsOneWidget,
      );
    });

    for (final (status, title, body) in [
      (
        SwapReviewStatus.expired,
        'Quote expired',
        'Refresh before starting. Nothing has been signed or sent.',
      ),
      (
        SwapReviewStatus.revalidationFailed,
        'Latest quote not confirmed',
        'Try again before starting. Your selections are preserved.',
      ),
      (
        SwapReviewStatus.rejected,
        "This swap couldn't start",
        'Nothing was sent. Check the amount and try again.',
      ),
    ]) {
      testWidgets('${status.name} is explained: "$title"', (tester) async {
        await pump(tester, quoteOf(), status: status);

        expect(find.text(title), findsWidgets);
        expect(find.text(body), findsOneWidget);
      });
    }

    testWidgets('a check in progress says starting waits for it', (
      tester,
    ) async {
      await pump(tester, quoteOf(), status: SwapReviewStatus.revalidating);

      expect(
        find.text(
          'Checking the latest outcome and costs. Starting is unavailable '
          'until this finishes.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a ready review has nothing to explain', (tester) async {
      await pump(tester, quoteOf());

      for (final title in [
        'Outcome updated',
        'Latest quote not confirmed',
        "This swap couldn't start",
        "We couldn't confirm whether this swap started",
      ]) {
        expect(find.text(title), findsNothing, reason: title);
      }
      expect(find.textContaining('Checking the latest'), findsNothing);
    });
  });

  group('the decision figures', () {
    final total = find.text('Total cost');
    final time = find.text('Estimated completion');

    testWidgets('sit in a row, and say when a cost is unknown', (tester) async {
      await pump(tester, quoteOf(pricing: pricingOf(network: null)));

      expect(sameRow(tester, total, time), isTrue);
      expect(find.text('Incomplete'), findsNWidgets(2));
    });

    testWidgets('stack at 200% text', (tester) async {
      await pump(tester, quoteOf(), size: const Size(375, 4000), textScale: 2);

      expect(above(tester, total, time), isTrue);
      expect(find.text(r'$3.00'), findsNWidgets(2));
    });
  });
}
