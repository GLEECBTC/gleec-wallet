// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/pickers/swap_options_sheet.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the comparison: every option on offer, compared on what it
/// promises, chosen deliberately, and never chosen once it has expired.
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

  final best = quoteOf(id: 'best');
  final fast = quoteOf(
    id: 'fast',
    order: SwapQuoteOrder.fastest,
    routeKind: SwapRouteKind.crossChain,
    expected: '2990',
    guaranteed: '2975',
    duration: const Duration(seconds: 20),
    stages: [
      const SwapRouteStage(kind: SwapRouteStageKind.prepare),
      SwapRouteStage(kind: SwapRouteStageKind.send, asset: eth),
      SwapRouteStage(kind: SwapRouteStageKind.bridge, asset: usdc),
      SwapRouteStage(kind: SwapRouteStageKind.receive, asset: usdc),
    ],
  );
  final unpriced = pricingOf(swap: null, complete: false);

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    Size size = const Size(420, 1600),
    double textScale = 1,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapOptionsSheet(),
      bloc: swap,
      services: services,
      size: size,
      textScale: textScale,
    );
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  /// The value beside [label] in the fee breakdown.
  Finder breakdown(String label, String value) => find.descendant(
    of: find.widgetWithText(SwapDetailRow, label),
    matching: find.text(value),
  );

  testWidgets('every option is compared on what it promises', (tester) async {
    await pump(tester, swapPricedForm(ranked: [best, fast]));

    expect(find.text('Compare options'), findsOneWidget);
    expect(
      find.text(
        'Best net return among currently available, comparable options.',
      ),
      findsOneWidget,
    );
    expect(find.text('3,000 USDC expected'), findsOneWidget);
    expect(find.text('Best net return'), findsOneWidget);
    expect(find.text('Same network'), findsOneWidget);
    expect(find.text('2,990 USDC expected'), findsOneWidget);
    expect(find.text('Fastest'), findsOneWidget);
    expect(find.text('Across networks'), findsOneWidget);
    expect(find.text('About 20 sec'), findsOneWidget);
    // Stages leave out the preparation nobody waits for.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('None'), findsNWidgets(2));
    expect(find.text('Slippage · 0.5%'), findsOneWidget);

    await tapText(tester, 'Fee breakdown');
    expect(breakdown('Network costs', r'$3.00'), findsOneWidget);
    expect(breakdown('Swap costs', r'$0.00'), findsOneWidget);
    expect(breakdown('Total cost', r'$3.00'), findsOneWidget);
  });

  testWidgets('another option, chosen and used, goes to the bloc', (
    tester,
  ) async {
    swap.emit(swapPricedForm(ranked: [best, fast]));
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
    );
    await tapText(tester, 'Compare options');
    expect(swap.events, [const UnifiedSwapAlternativesRequested()]);

    final fastCard = find.text('2,990 USDC expected');
    expect(
      tester.getSemantics(fastCard),
      isSemantics(isInMutuallyExclusiveGroup: true, isChecked: false),
    );
    await tapText(tester, '2,990 USDC expected');
    expect(
      tester.getSemantics(fastCard),
      isSemantics(isInMutuallyExclusiveGroup: true, isChecked: true),
    );

    await tapText(tester, 'Use this option');
    expect(swap.events.last, const UnifiedSwapOptionSelected('fast'));
    expect(find.text('Use this option'), findsNothing);
  });

  testWidgets('a choice a refresh withdrew falls back to the selected one', (
    tester,
  ) async {
    await pump(tester, swapPricedForm(ranked: [best, fast]));
    await tapText(tester, '2,990 USDC expected');

    final slower = quoteOf(id: 'slower', expected: '2980', guaranteed: '2970');
    await emitSwapState(tester, swap, swapPricedForm(ranked: [best, slower]));
    await tapText(tester, 'Use this option');

    expect(swap.events, [const UnifiedSwapOptionSelected('best')]);
  });

  testWidgets('options that cannot be compared are set apart', (tester) async {
    final partial = quoteOf(id: 'partial', expected: '3050', pricing: unpriced);
    await pump(tester, swapPricedForm(ranked: [best], unrankable: [partial]));

    // The heading and the option's own badge.
    expect(find.text('Unable to compare'), findsNWidgets(2));
    expect(
      above(
        tester,
        find.text('Unable to compare').first,
        find.text('3,050 USDC expected'),
      ),
      isTrue,
    );
    expect(find.text('Incomplete'), findsOneWidget);
    expect(find.text('Best net return'), findsNothing);
  });

  testWidgets('when none can be ranked, one is chosen by hand', (tester) async {
    await pump(
      tester,
      swapPricedForm(
        ranked: [],
        unrankable: [
          quoteOf(id: 'u1', pricing: unpriced),
          quoteOf(id: 'u2', expected: '2995', pricing: unpriced),
        ],
      ),
    );

    expect(
      find.text(
        'These options are not ranked. Choose one after reviewing its '
        'available details.',
      ),
      findsOneWidget,
    );
    expect(find.text('Choose manually'), findsOneWidget);
    expect(
      find.text(
        "These options can't be ranked reliably using minimum received and "
        'total cost. Select one to continue.',
      ),
      findsOneWidget,
    );
    expect(swapButtonEnabled(tester, find.text('Select an option')), isFalse);

    await tapText(tester, '2,995 USDC expected');
    await tapText(tester, 'Use this option');
    expect(swap.events, [const UnifiedSwapOptionSelected('u2')]);
  });

  testWidgets('expired options must be refreshed before one is chosen', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm(
        ranked: [best, fast],
        evaluation: SwapEvaluationStatus.expired,
      ),
    );

    expect(
      find.text('These options expired. Refresh to see current prices.'),
      findsOneWidget,
    );
    await tapText(tester, '2,990 USDC expected');
    expect(
      tester.getSemantics(find.text('2,990 USDC expected')),
      isSemantics(isChecked: false),
    );
    expect(find.text('Use this option'), findsNothing);

    await tapText(tester, 'Refresh quote');
    expect(swap.events, [const UnifiedSwapEvaluationRequested()]);
  });

  testWidgets('a lone option is shown as its details, while a faster one is '
      'looked for', (tester) async {
    await pump(tester, swapPricedForm().copyWith(checkingAlternatives: true));

    expect(find.text('Option details'), findsOneWidget);
    expect(find.text('Checking for a faster route…'), findsOneWidget);
  });

  testWidgets('each option says what permission it asks for', (tester) async {
    SwapApprovalRequirement approval({required bool reset}) =>
        SwapApprovalRequirement(
          asset: usdc,
          exactAmount: d('1250'),
          resetsFirst: reset,
        );
    await pump(
      tester,
      swapPricedForm(
        ranked: [
          quoteOf(id: 'exact', approval: approval(reset: false)),
          quoteOf(
            id: 'reset',
            expected: '2990',
            approval: approval(reset: true),
            source: SwapLiquiditySource.atomic,
            routeKind: SwapRouteKind.direct,
          ),
        ],
      ),
    );

    expect(find.text('Exact amount'), findsOneWidget);
    expect(find.text('Reset + exact'), findsOneWidget);
    expect(find.text('Direct exchange'), findsOneWidget);
    expect(swapRouteKindLabel(SwapRouteKind.direct), 'Direct exchange');
    expect(swapRouteKindLabel(SwapRouteKind.sameChain), 'Same network');
    expect(swapRouteKindLabel(SwapRouteKind.crossChain), 'Across networks');
  });

  testWidgets('the fee breakdown gives the approval\'s share, and says when '
      'a cost is unknown', (tester) async {
    final approving = quoteOf(
      approval: SwapApprovalRequirement(
        asset: eth,
        exactAmount: d('1'),
        resetsFirst: false,
      ),
      pricing: pricingOf(network: '4.2', approval: '1.2', swap: null),
    );
    await pump(tester, swapPricedForm(ranked: [approving]));
    await tapText(tester, 'Fee breakdown');

    expect(breakdown('Network costs', r'$4.20'), findsOneWidget);
    expect(breakdown('↳ Approval network cost', r'$1.20'), findsOneWidget);
    expect(breakdown('Swap costs', 'Incomplete'), findsOneWidget);
    expect(breakdown('Total cost', 'Incomplete'), findsOneWidget);
  });

  testWidgets('slippage is changed from the comparison, and announced', (
    tester,
  ) async {
    await pump(tester, swapPricedForm());
    await tapText(tester, 'Change');

    expect(find.text('Use 0.5%'), findsOneWidget);
    await tapText(tester, '1%');
    await tapText(tester, 'Use 1%');

    expect(swap.events, [const UnifiedSwapSlippageChanged(0.01)]);
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Slippage set to 1%. Checking prices again.'),
    ]);
    expect(find.text('Use 1%'), findsNothing);
    expect(find.text('Option details'), findsOneWidget);
  });

  testWidgets('order-book options have no slippage to set', (tester) async {
    await pump(
      tester,
      swapPricedForm(
        ranked: [
          quoteOf(
            source: SwapLiquiditySource.atomic,
            routeKind: SwapRouteKind.direct,
            order: null,
          ),
        ],
      ),
    );

    expect(find.textContaining('Slippage'), findsNothing);
  });

  group('the figures on a card', () {
    final minimum = find.text('Minimum');
    final total = find.text('Total cost');
    final eta = find.text('ETA');

    testWidgets('sit three to a row on a wide card', (tester) async {
      await pump(tester, swapPricedForm(), size: const Size(500, 1600));
      expect(sameRow(tester, minimum, total), isTrue);
      expect(sameRow(tester, total, eta), isTrue);
    });

    testWidgets('sit two to a row on a phone', (tester) async {
      await pump(tester, swapPricedForm(), size: const Size(375, 1600));
      expect(sameRow(tester, minimum, total), isTrue);
      expect(above(tester, total, eta), isTrue);
    });

    for (final (name, size, scale) in [
      ('on a very narrow screen', const Size(280, 1600), 1.0),
      ('at 200% text', const Size(420, 3000), 2.0),
    ]) {
      testWidgets('stack one to a row $name', (tester) async {
        await pump(tester, swapPricedForm(), size: size, textScale: scale);
        expect(above(tester, minimum, total), isTrue);
        expect(above(tester, total, eta), isTrue);
      });
    }
  });
}
