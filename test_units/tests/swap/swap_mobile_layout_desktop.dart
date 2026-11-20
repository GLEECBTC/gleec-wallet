// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

part of 'swap_mobile_layout_test.dart';

void _desktopCases() {
  group('the form in a desktop window', () {
    // A laptop window reserves the quote region before an option arrives.
    const laptop = Size(1366, 700);
    const tall = Size(1366, 1200);
    final unpriced = swapBaseForm(input: '')
        .copyWith(issue: SwapFormIssue.amountMissing);

    Future<void> show(WidgetTester tester, UnifiedSwapState state) async {
      swap.emit(state);
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('pins the main action once the quote runs past the bottom', (
      tester,
    ) async {
      await pump(tester, swapPricedForm(), size: laptop);

      expect(
        find.descendant(of: footer, matching: swapPrimaryAction),
        findsOneWidget,
      );
      expect(swapPrimaryAction.hitTestable(), findsOneWidget);
    });

    testWidgets('keeps it right after the quote while everything fits', (
      tester,
    ) async {
      await pump(tester, swapPricedForm(), size: tall);

      expect(footer, findsNothing);
      expect(
        above(tester, find.byType(SwapQuoteStrip), swapPrimaryAction),
        isTrue,
      );
      expect(swapPrimaryAction.hitTestable(), findsOneWidget);
    });

    testWidgets('keeps the pinned action stable as quotes arrive and clear', (
      tester,
    ) async {
      await pump(tester, unpriced, size: laptop);
      expect(footer, findsOneWidget);
      expect(swapPrimaryLabel(tester), 'Enter amount');
      final position = tester.getRect(swapPrimaryAction);

      await show(tester, swapPricedForm());
      expect(
        find.descendant(of: footer, matching: swapPrimaryAction),
        findsOneWidget,
      );
      expect(swapPrimaryLabel(tester), 'Review swap');
      expect(tester.getRect(swapPrimaryAction), position);

      await show(tester, unpriced);
      expect(footer, findsOneWidget);
      expect(swapPrimaryAction.hitTestable(), findsOneWidget);
      expect(tester.getRect(swapPrimaryAction), position);
    });

    testWidgets('holds steady when only the action itself does not fit', (
      tester,
    ) async {
      await pump(tester, swapPricedForm(), size: tall);
      final whole = tester.getSize(find.byType(SwapColumn)).height;

      // The form fits without its action and not with it: pinned, and it
      // stays pinned rather than flipping each frame.
      tester.view.physicalSize = Size(tall.width, whole - 10);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: footer, matching: swapPrimaryAction),
        findsOneWidget,
      );
    });

    testWidgets('pins it when the window gets shorter, and lets go after', (
      tester,
    ) async {
      await pump(tester, swapPricedForm(), size: tall);
      expect(footer, findsNothing);

      tester.view.physicalSize = laptop;
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: footer, matching: swapPrimaryAction),
        findsOneWidget,
      );

      tester.view.physicalSize = tall;
      await tester.pumpAndSettle();
      expect(footer, findsNothing);
    });
  });
}
