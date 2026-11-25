// The analyzer does not treat test_units as tests.
// ignore_for_file: invalid_use_of_visible_for_testing_member

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

      final changed = find.byKey(const Key('swap-review-changed'));
      expect(changed.hitTestable(), findsOneWidget);
      expect(above(tester, changed, find.text('You pay')), isTrue);
    });

    testWidgets('brings a change into view for someone who had scrolled on, '
        'with the button accepting it', (tester) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready),
        view: const SwapReviewView(),
      );
      await tester.drag(find.text('You pay'), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('You pay').hitTestable(), findsNothing);

      await emitSwapState(
        tester,
        swap,
        reviewing(SwapReviewStatus.materialUpdate),
      );
      await tester.pumpAndSettle();

      final changed = find.byKey(const Key('swap-review-changed'));
      expect(changed.hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(changed).dy,
        greaterThanOrEqualTo(0),
        reason: 'from its first line',
      );
      expect(find.byKey(const Key('swap-start')).hitTestable(), findsOneWidget);
    });

    testWidgets('gives the provider terms beside the button accepting them', (
      tester,
    ) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready, termsRequired: true),
        view: const SwapReviewView(),
      );

      final consent = find.byKey(const Key('swap-legal-consent'));
      final link = find.byKey(const Key('swap-terms-link'));
      final start = find.byKey(const Key('swap-start'));
      expect(find.descendant(of: footer, matching: consent), findsOneWidget);
      expect(find.descendant(of: footer, matching: link), findsOneWidget);
      // What is accepted, then the documents, then the button accepting.
      expect(above(tester, consent, link), isTrue);
      expect(above(tester, link, start), isTrue);
      for (final part in [consent, link, start]) {
        expect(part.hitTestable(), findsOneWidget);
      }
      // Who the provider is closes the review, above the pinned block.
      expect(find.byType(SwapProviderNotice), findsOneWidget);
      expect(
        find.descendant(of: footer, matching: find.byType(SwapProviderNotice)),
        findsNothing,
      );
    });

    testWidgets('already accepted terms leave only the button pinned, and '
        'stay readable at the end of the review', (tester) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready),
        view: const SwapReviewView(),
      );

      final notice = find.byType(SwapProviderNotice);
      final link = find.byKey(const Key('swap-terms-link'));
      expect(find.descendant(of: footer, matching: notice), findsNothing);
      expect(find.descendant(of: footer, matching: link), findsNothing);
      expect(tester.getSize(footer).height, lessThan(iPhoneSe.height * .15));

      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      expect(notice, findsOneWidget);
      expect(link.hitTestable(), findsOneWidget);
    });

    for (final layout in [
      (name: 'zoomed window', size: Size(864, 240), panel: false, scale: 1.0),
      (name: 'short panel', size: Size(430, 300), panel: true, scale: 1.0),
      (name: 'enlarged text', size: iPhoneSe, panel: false, scale: 2.0),
    ]) {
      testWidgets('a short or enlarged review keeps money and consent '
          'reachable: ${layout.name}', (tester) async {
        final review = SwapReview(
          quote: quoteOf(guaranteed: '2900'),
          status: SwapReviewStatus.ready,
          termsRequired: true,
          legalFailed: true,
          legalBypass: true,
        );
        swap.emit(
          swapPricedForm().copyWith(
            view: UnifiedSwapView.review,
            review: review,
          ),
        );
        await pumpSwapUi(
          tester,
          SwapReviewView(inPanel: layout.panel),
          bloc: swap,
          services: services,
          size: layout.size,
          textScale: layout.scale,
        );

        expect(tester.takeException(), isNull);
        for (final item in [
          find.text('You pay'),
          find.text('2,900 USDC'),
          find.byKey(const Key('legal-documents-unavailable')),
          find.byKey(const Key('swap-terms-link')),
          find.byKey(const Key('swap-start')),
        ]) {
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          expect(item.hitTestable(), findsOneWidget);
        }
        // With no room to spare, what blocks the action stays with it and
        // the documents scroll with the review.
        expect(
          find.descendant(
            of: footer,
            matching: find.byKey(const Key('legal-documents-unavailable')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: footer,
            matching: find.byKey(const Key('swap-terms-link')),
          ),
          findsNothing,
        );
        expect(swap.state.review, same(review));
        expect(swap.events, isEmpty);
      });
    }

    testWidgets('at 200% text a first routed swap pins one line of consent '
        'with its button, and leaves most of the screen to the review', (
      tester,
    ) async {
      swap.emit(reviewing(SwapReviewStatus.ready, termsRequired: true));
      await pumpSwapUi(
        tester,
        const SwapReviewView(),
        bloc: swap,
        services: services,
        size: const Size(390, 844),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      final consent = find.byKey(const Key('swap-legal-consent'));
      expect(find.descendant(of: footer, matching: consent), findsOneWidget);
      expect(tester.widget<Text>(consent).data, 'swapLegalConsentCompact'.tr());
      expect(
        find.descendant(
          of: footer,
          matching: find.byKey(const Key('swap-terms-link')),
        ),
        findsNothing,
      );
      expect(tester.getSize(footer).height, lessThan(844 * .3));
      // The heading does not take the room the figures need.
      expect(
        tester.getSize(find.text(LocaleKeys.swapReviewTitle.tr())).height,
        lessThan(50),
      );
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
