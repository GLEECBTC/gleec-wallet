// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the form does with what someone types and taps: the amount
/// as typed, the dollar toggle, Max, switching sides, and editing while the
/// review is open beside it.
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

  final field = find.byKey(const Key('swap-amount'));

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    bool panelOpen = false,
    bool settle = true,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      SwapEntryView(panelOpen: panelOpen),
      bloc: swap,
      services: services,
      settle: settle,
    );
  }

  TextEditingController controller(WidgetTester tester) =>
      tester.widget<TextField>(field).controller!;

  // Waiting for an amount: the only unpriced state whose action is still.
  final empty = swapBaseForm(
    input: '',
  ).copyWith(issue: SwapFormIssue.amountMissing);
  // The receive side worth $2,990, so the pay side's $3,000 is the only one.
  final priced = swapPricedForm(
    ranked: [quoteOf(pricing: pricingOf(expected: '2990'))],
  );

  group('the amount', () {
    testWidgets('goes to the bloc as typed, a comma read as a point', (
      tester,
    ) async {
      await pump(tester, empty);
      await tester.enterText(field, '1,5');

      expect(swap.events, [const UnifiedSwapAmountChanged('1.5')]);
      expect(controller(tester).text, '1.5');
    });

    testWidgets('refuses a second point or a letter, keeping what was there', (
      tester,
    ) async {
      await pump(tester, empty);
      await tester.enterText(field, '1.5');
      await tester.enterText(field, '1.5.2');
      await tester.enterText(field, '1.5x');

      expect(swap.events, [const UnifiedSwapAmountChanged('1.5')]);
      expect(controller(tester).text, '1.5');

      await tester.enterText(field, '');
      expect(swap.events.last, const UnifiedSwapAmountChanged(''));
    });

    testWidgets('in dollars takes two decimal places at most', (tester) async {
      await pump(tester, empty.copyWith(amountMode: SwapAmountMode.fiat));
      await tester.enterText(field, '12.345');
      expect(swap.events, isEmpty);

      await tester.enterText(field, '12.34');
      expect(swap.events, [const UnifiedSwapAmountChanged('12.34')]);
    });

    testWidgets('set by the bloc replaces the field, the cursor at its end', (
      tester,
    ) async {
      await pump(tester, priced);
      await emitSwapState(tester, swap, priced.copyWith(inputText: '1.9979'));

      expect(controller(tester).text, '1.9979');
      expect(
        controller(tester).selection,
        const TextSelection.collapsed(offset: 6),
      );
    });

    testWidgets('is left alone when the bloc agrees, so typing never jumps', (
      tester,
    ) async {
      await pump(tester, priced);
      await tester.enterText(field, '12');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '12',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();

      await emitSwapState(
        tester,
        swap,
        priced.copyWith(inputText: '12', balance: d('3')),
      );

      expect(controller(tester).text, '12');
      expect(
        controller(tester).selection,
        const TextSelection.collapsed(offset: 1),
      );
      expect(find.text('Balance 3 ETH'), findsOneWidget);
    });

    testWidgets('lights the pay card while focused, unless it is wrong', (
      tester,
    ) async {
      BoxDecoration card() =>
          tester
                  .widget<AnimatedContainer>(
                    find
                        .ancestor(
                          of: field,
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      Color border() => (card().border! as Border).top.color;

      await pump(tester, priced);
      expect(card().boxShadow, isNull);
      expect(border(), SwapPalette.dark.controlBorder);

      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(card().boxShadow, isNotEmpty);
      expect(border(), SwapPalette.dark.brand);

      swap.emit(
        priced.copyWith(inputText: '0', issue: SwapFormIssue.amountZero),
      );
      await tester.pumpAndSettle();
      expect(find.text('Amount must be greater than 0.'), findsOneWidget);
      expect(card().boxShadow, isNull);
      expect(border(), SwapPalette.dark.danger);
    });
  });

  group('the dollar line', () {
    testWidgets('switches entry between the token and US dollars', (
      tester,
    ) async {
      await pump(tester, priced);
      expect(find.text(r'$3,000.00'), findsOneWidget);
      expect(find.byTooltip('Enter amount in USD'), findsOneWidget);

      await tester.tap(find.text(r'$3,000.00'));
      expect(swap.events, [const UnifiedSwapAmountModeToggled()]);

      swap.emit(
        priced.copyWith(inputText: '1500', amountMode: SwapAmountMode.fiat),
      );
      await tester.pumpAndSettle();
      expect(find.text('≈ 0.5 ETH'), findsOneWidget);
      expect(find.byTooltip('Enter amount in ETH'), findsOneWidget);
      expect(
        tester.getSemantics(find.byTooltip('Enter amount in ETH')),
        isSemantics(
          label: '≈ 0.5 ETH. Enter amount in ETH',
          isButton: true,
          hasTapAction: true,
        ),
      );

      await tester.tap(find.text('≈ 0.5 ETH'));
      expect(swap.events, [
        const UnifiedSwapAmountModeToggled(),
        const UnifiedSwapAmountModeToggled(),
      ]);
    });

    testWidgets('without a price says so and offers no toggle', (tester) async {
      await pump(
        tester,
        swapBaseForm(
          pay: btc,
          input: '',
        ).copyWith(issue: SwapFormIssue.amountMissing),
      );

      expect(find.text('Price estimate unavailable'), findsOneWidget);
      expect(find.byTooltip('Enter amount in USD'), findsNothing);
    });
  });

  group('Max', () {
    testWidgets('asks for everything sellable, and says so', (tester) async {
      await pump(tester, priced);
      expect(find.text('Balance 2 ETH'), findsOneWidget);

      await tester.tap(find.text('Max'));
      expect(swap.events, [const UnifiedSwapMaxRequested()]);
      expect(tester.takeAnnouncements(), [
        isAccessibilityAnnouncement(
          'Maximum amount applied with network fees kept back',
        ),
      ]);
    });

    testWidgets('is not offered before the balance is known', (tester) async {
      await pump(tester, priced.copyWith(clearBalance: true));

      expect(find.text('Max'), findsNothing);
      expect(find.textContaining('Balance'), findsNothing);
    });
  });

  group('the switch', () {
    testWidgets('swaps the two sides, and says so', (tester) async {
      await pump(tester, priced);
      await tester.tap(find.byTooltip('Switch direction'));

      expect(swap.events, [const UnifiedSwapSidesSwitched()]);
      expect(tester.takeAnnouncements(), [
        isAccessibilityAnnouncement('Pay and receive assets switched'),
      ]);
    });

    testWidgets('does nothing while neither side is chosen', (tester) async {
      await pump(
        tester,
        swapBaseForm().copyWith(clearPay: true, clearReceive: true),
      );
      await tester.tap(find.byTooltip('Switch direction'));

      expect(swap.events, isEmpty);
      expect(
        tester.getSemantics(find.byTooltip('Switch direction')),
        isSemantics(
          label: 'Switch direction',
          isButton: true,
          isEnabled: false,
        ),
      );
    });
  });

  group('with the review open beside the form', () {
    final inReview = swapPricedForm().copyWith(
      view: UnifiedSwapView.review,
      review: SwapReview(quote: quoteOf(), status: SwapReviewStatus.ready),
    );

    testWidgets('says editing closes it, in place of the action', (
      tester,
    ) async {
      await pump(tester, inReview, panelOpen: true);

      expect(
        find.text(
          'Review is open in the side panel. Editing the swap closes it and '
          'checks a fresh quote.',
        ),
        findsOneWidget,
      );
      expect(swapPrimaryAction, findsNothing);
    });

    testWidgets('an edit closes the review before it is sent', (tester) async {
      await pump(tester, inReview, panelOpen: true);
      await tester.enterText(field, '2');
      await tester.tap(find.text('Max'));

      expect(swap.events, [
        const UnifiedSwapReviewClosed(),
        const UnifiedSwapAmountChanged('2'),
        const UnifiedSwapReviewClosed(),
        const UnifiedSwapMaxRequested(),
      ]);
    });
  });

  testWidgets('fresh options are announced when they become ready', (
    tester,
  ) async {
    await pump(
      tester,
      swapBaseForm().copyWith(evaluation: SwapEvaluationStatus.checking),
      settle: false,
    );
    expect(tester.takeAnnouncements(), isEmpty);

    swap.emit(swapPricedForm());
    await tester.pump();
    expect(tester.takeAnnouncements(), [
      isAccessibilityAnnouncement('Updated swap options are ready'),
    ]);

    // Still ready, and then expired: neither is news worth announcing.
    swap.emit(swapPricedForm(ranked: [quoteOf(expected: '3100')]));
    await tester.pump();
    swap.emit(swapPricedForm(evaluation: SwapEvaluationStatus.expired));
    await tester.pump();
    expect(tester.takeAnnouncements(), isEmpty);
  });
}
