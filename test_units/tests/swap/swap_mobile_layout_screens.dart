part of 'swap_mobile_layout_test.dart';

void _reviewCases() {
  group('the review on a phone', () {
    UnifiedSwapState reviewing(
      SwapReviewStatus status, {
      bool termsRequired = false,
    }) => swapPricedForm().copyWith(
      view: UnifiedSwapView.review,
      review: SwapReview(
        legalSnapshot: legalFixtureSnapshot(),
        quote: quoteOf(guaranteed: '2900'),
        previous: quoteOf(),
        status: status,
        termsRequired: termsRequired,
      ),
    );

    testWidgets('says what changed before the swap it changed', (tester) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.materialUpdate),
        view: const SwapReviewView(),
      );

      final changed = find.text('Outcome updated');
      expect(changed.hitTestable(), findsOneWidget);
      expect(above(tester, changed, find.text('You pay')), isTrue);
    });

    testWidgets('gives the provider terms beside the button accepting them', (
      tester,
    ) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready, termsRequired: true),
        view: const SwapReviewView(),
      );

      expect(
        find.descendant(
          of: footer,
          matching: find.byKey(const Key('swap-terms-link')),
        ),
        findsOneWidget,
      );
      expect(find.byType(SwapProviderNotice), findsOneWidget);
      expect(
        above(
          tester,
          find.byType(SwapProviderNotice),
          find.byKey(const Key('swap-start')),
        ),
        isTrue,
      );
    });

    testWidgets('already accepted terms remain readable beside the action', (
      tester,
    ) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready),
        view: const SwapReviewView(),
      );

      expect(
        find.descendant(of: footer, matching: find.byType(SwapProviderNotice)),
        findsOneWidget,
      );
      expect(find.byType(SwapProviderNotice), findsOneWidget);
    });
  });
}

void _fabCases() {
  group('the bug-report button', () {
    Future<void> pumpFab(WidgetTester tester, {required bool feedback}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              floatingActionButton: MainLayoutFab(
                showAddCoinButton: false,
                isMini: true,
                showFeedbackButton: feedback,
              ),
            ),
          ),
        );

    testWidgets('stays off the swap screens, where it would cover their '
        'pinned actions', (tester) async {
      await pumpFab(tester, feedback: true);
      expect(find.byTooltip('Report a bug or feedback'), findsOneWidget);

      await pumpFab(tester, feedback: false);
      expect(find.byTooltip('Report a bug or feedback'), findsNothing);
    });
  });
}

void _sheetCases() {
  group('a short sheet', () {
    Future<void> open(WidgetTester tester, Size size) async {
      await pumpSwapUi(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSwapSlippageSheet(context, swap),
            child: const Text('open'),
          ),
        ),
        bloc: swap,
        services: services,
        size: size,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('rises from the bottom of a phone, only as tall as it needs', (
      tester,
    ) async {
      await open(tester, iPhoneSe);

      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(tester.getTopLeft(sheet).dy, greaterThan(iPhoneSe.height / 3));
      expect(tester.getBottomLeft(sheet).dy, iPhoneSe.height);
      expect(find.text('open').hitTestable(), findsNothing);
    });

    testWidgets('swiped down, closes without saving', (tester) async {
      await open(tester, iPhoneSe);
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.fling(find.text('Slippage'), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(find.text('Use 0.5%'), findsNothing);
      expect(swap.events, isEmpty);
    });

    final dialog = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(Material),
    );
    final use = find.text('Use 0.5%');

    testWidgets('opens as a small dialog in a wider window, with its button '
        'right under the choices', (tester) async {
      await open(tester, tablet);

      expect(find.byType(BottomSheet), findsNothing);
      final box = tester.getRect(dialog.first);
      expect(box.width, lessThanOrEqualTo(440));
      expect(box.center.dx, closeTo(tablet.width / 2, 1));
      expect(box.center.dy, closeTo(tablet.height / 2, 1));
      expect(box.height, lessThan(tablet.height / 2));
      // With no drag handle above, the title keeps its room at the top.
      expect(
        tester.getTopLeft(find.text('Slippage')).dy - box.top,
        greaterThanOrEqualTo(18),
      );
      expect(
        tester.getTopLeft(use).dy -
            tester.getBottomLeft(find.text('Custom')).dy,
        lessThan(120),
      );
    });

    testWidgets('closes on Escape without saving', (tester) async {
      await open(tester, tablet);
      expect(find.byType(Dialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(swap.events, isEmpty);
    });

    testWidgets('sits above the keyboard, with no room left for it inside', (
      tester,
    ) async {
      const keyboard = 336.0;
      await open(tester, tablet);
      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField), '3');
      await tester.pumpAndSettle();

      final box = tester.getRect(dialog.first);
      expect(box.bottom, lessThanOrEqualTo(tablet.height - keyboard));
      expect(
        box.bottom - tester.getBottomLeft(find.text('Use 3%')).dy,
        lessThan(48),
      );
    });

    testWidgets('keeps the side panel in a window too short for a dialog', (
      tester,
    ) async {
      await open(tester, sideways);

      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(use, findsOneWidget);
    });
  });
}
