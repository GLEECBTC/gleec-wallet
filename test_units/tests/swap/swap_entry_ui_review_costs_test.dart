// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
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
    await tester.tap(find.text(LocaleKeys.swapReviewCostsProtection.tr()));
    await tester.pumpAndSettle();
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

  testWidgets('fees the engine could not read are a dash with a reason, '
      'never free', (tester) async {
    await pump(
      tester,
      quoteOf(fees: const [], feesKnown: false, pricing: unpriced),
    );
    await expandCosts(tester);

    expect(detail(tester, 'Network costs'), '—');
    expect(detail(tester, 'Swap costs'), '—');
    // The figures above the details: total and network cost.
    expect(find.text('—'), findsNWidgets(4));
    expect(find.text('swapReviewCostsUnknownNote'.tr()), findsOneWidget);
    expect(find.text(r'$0.00'), findsNothing);
    expect(find.text(LocaleKeys.swapCostIncomplete.tr()), findsNothing);
  });

  testWidgets('known fees carry no such note', (tester) async {
    await pump(tester, quoteOf());

    expect(find.text('swapReviewCostsUnknownNote'.tr()), findsNothing);
    expect(find.text('—'), findsNothing);
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

      expect(changed(tester, 'minimum').skip(1), ['2,985 USDC', '2,900 USDC']);
      // Nothing to compare with: a dash, then what they are now.
      expect(changed(tester, 'cost'), [
        LocaleKeys.swapTotalCost.tr(),
        '—',
        r'$3.00',
      ]);
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

      expect(changed(tester, 'cost'), [
        LocaleKeys.swapTotalCost.tr(),
        '2 GLEEC',
        '2.5 GLEEC',
      ]);
    });
  });
}
