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

/// Covers the review's costs where they are least certain: fees the engine
/// could not read, costs with no dollar price, and how a re-price that
/// changed them is put.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;

  setUp(() => swap = RecordingSwapBloc());
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
        review: SwapReview(quote: quote, status: status, previous: previous),
      ),
    );
    await pumpSwapUi(
      tester,
      const SwapReviewView(),
      bloc: swap,
      services: FakeSwapServices(),
      size: const Size(420, 2400),
    );
  }

  Future<void> expandCosts(WidgetTester tester) async {
    await tester.tap(find.text('Costs & protection'));
    await tester.pumpAndSettle();
  }

  String detail(WidgetTester tester, String label) {
    final row = find.widgetWithText(SwapDetailRow, label);
    return tester.widget<SwapDetailRow>(row).value;
  }

  SwapFeeComponent fee(String amount, AssetId asset) => SwapFeeComponent(
    kind: SwapFeeKind.dexFee,
    amount: d(amount),
    deductedFromReceive: false,
    asset: asset,
  );

  final unpriced = pricingOf(network: null, swap: null, complete: false);

  testWidgets('fees the engine could not read are incomplete, not free', (
    tester,
  ) async {
    await pump(
      tester,
      quoteOf(fees: const [], feesKnown: false, pricing: unpriced),
    );
    await expandCosts(tester);

    expect(detail(tester, 'Network costs'), 'Incomplete');
    expect(detail(tester, 'Swap costs'), 'Incomplete');
    expect(find.text(r'$0.00'), findsNothing);
  });

  testWidgets('approval gas reads as part of the network costs', (
    tester,
  ) async {
    SwapFeeComponent gas(SwapFeeKind kind, String amount, String usd) =>
        SwapFeeComponent(
          kind: kind,
          amount: d(amount),
          deductedFromReceive: false,
          asset: eth,
          usdValue: d(usd),
        );
    await pump(
      tester,
      quoteOf(
        approval: SwapApprovalRequirement(
          asset: usdc,
          exactAmount: d('100'),
          resetsFirst: false,
        ),
        fees: [
          gas(SwapFeeKind.network, '0.001', '3'),
          gas(SwapFeeKind.approvalNetwork, '0.0004', '1.2'),
        ],
        pricing: pricingOf(network: '4.2', approval: '1.2'),
      ),
    );
    await expandCosts(tester);

    expect(detail(tester, 'Network costs'), r'$4.20');
    expect(detail(tester, '↳ Approval network cost'), r'$1.20');
  });

  for (final (slippage, shown) in [
    (0.0005, '0.05%'),
    (0.0025, '0.25%'),
    (0.02, '2%'),
  ]) {
    testWidgets('a slippage of $shown reads as it was set', (tester) async {
      await pump(tester, quoteWith(quoteOf(), slippage: slippage));
      await expandCosts(tester);

      expect(detail(tester, 'Slippage'), shown);
    });
  }

  group('an update', () {
    testWidgets('says what the costs not read before come to', (tester) async {
      await pump(
        tester,
        quoteOf(
          guaranteed: '2900',
          pricing: pricingOf(minimum: '2900'),
        ),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(fees: const [], feesKnown: false, pricing: unpriced),
      );

      expect(
        find.text(
          r'Minimum changed from 2,985 USDC to 2,900 USDC. Total cost is now '
          r'known: $3.00.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('compares costs with no dollar price in their tokens', (
      tester,
    ) async {
      await pump(
        tester,
        quoteOf(fees: [fee('2.5', gleec)], pricing: unpriced),
        status: SwapReviewStatus.materialUpdate,
        previous: quoteOf(fees: [fee('2', gleec)], pricing: unpriced),
      );

      expect(
        find.text('Total cost changed from 2 GLEEC to 2.5 GLEEC.'),
        findsOneWidget,
      );
    });
  });
}
