// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';
import 'package:web_dex/views/swap/swap_page.dart';

import '../../support/legal_documents_fixture.dart';

import 'swap_accessibility_checks.dart';
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the moment funds are committed: the action that starts a swap, or
/// accepts changed terms, cannot be pressed by momentum from the control it
/// replaced, and what changed is itemised before it can be accepted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  const phone = Size(390, 844);
  const wallet = '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91';
  final start = find.byKey(const Key('swap-start'));
  // A double tap's second press, and a tap already on its way down.
  const momentum = Duration(milliseconds: 300);

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

  UnifiedSwapState reviewing(
    SwapReviewStatus status, {
    SwapQuote? quote,
    SwapQuote? previous,
    bool termsRequired = false,
    bool legal = true,
  }) => swapPricedForm().copyWith(
    view: UnifiedSwapView.review,
    payAddress: wallet,
    receiveAddress: wallet,
    review: SwapReview(
      legalSnapshot: legal ? legalFixtureSnapshot() : null,
      legalFailed: !legal,
      quote: quote ?? quoteOf(),
      previous: previous,
      status: status,
      termsRequired: termsRequired,
    ),
  );

  Future<void> show(
    WidgetTester tester,
    UnifiedSwapState state, {
    Widget view = const SwapReviewView(),
    Size size = phone,
    double textScale = 1,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      view,
      bloc: swap,
      services: services,
      size: size,
      textScale: textScale,
      settle: false,
    );
  }

  int starts() => swap.events.whereType<UnifiedSwapStartRequested>().length;

  Future<void> press(WidgetTester tester) async {
    await tester.tap(start);
    await tester.pump();
  }

  group('the action that commits', () {
    testWidgets('drops a press inside the arming window and takes one after '
        'it', (tester) async {
      await show(tester, reviewing(SwapReviewStatus.ready, quote: orderBook));

      // Ready to look at from its first frame: nothing flickers into use.
      final button = tester.widget<SwapButton>(start);
      expect(button.onPressed, isNotNull);
      expect(button.busy, isFalse);
      expect(
        swapButtonEnabled(tester, find.text('swapConfirmSwap'.tr())),
        true,
      );

      await press(tester);
      await tester.pump(momentum);
      await press(tester);
      expect(starts(), 0);

      await tester.pump(swapCommitArmingDelay - momentum);
      await press(tester);
      expect(starts(), 1);
    });

    testWidgets('starts once however fast it is pressed again', (tester) async {
      await show(tester, reviewing(SwapReviewStatus.ready));
      await tester.pump(swapCommitArmingDelay);

      await press(tester);
      await press(tester);
      await tester.pump(momentum);
      await press(tester);
      expect(starts(), 1);
    });

    testWidgets('a double tap on Review cannot land as a start', (
      tester,
    ) async {
      final form = swapPricedForm(ranked: [orderBook]);
      await show(tester, form, view: const SwapPage());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('swap-primary-action')),
        warnIfMissed: false,
      );
      // The order book's review opens with nothing to wait for: the commit
      // action is under the same thumb on the very next frame.
      await emitSwapState(
        tester,
        swap,
        form.copyWith(
          view: UnifiedSwapView.review,
          review: SwapReview(quote: orderBook, status: SwapReviewStatus.ready),
        ),
      );
      expect(start.hitTestable(), findsOneWidget);

      await press(tester);
      await tester.pump(momentum);
      await press(tester);
      expect(starts(), 0);

      await tester.pump(swapCommitArmingDelay);
      await press(tester);
      expect(starts(), 1);
    });

    testWidgets('is held again when a re-price changes the terms', (
      tester,
    ) async {
      await show(tester, reviewing(SwapReviewStatus.ready));
      await tester.pump(swapCommitArmingDelay);

      // "Checking…" turns into "Accept updated quote" in the same place.
      await emitSwapState(
        tester,
        swap,
        reviewing(SwapReviewStatus.revalidating),
      );
      await emitSwapState(
        tester,
        swap,
        reviewing(
          SwapReviewStatus.materialUpdate,
          quote: quoteOf(expected: '2950', guaranteed: '2935'),
          previous: quoteOf(),
        ),
      );
      expect(
        tester.widget<SwapButton>(start).label,
        LocaleKeys.swapAcceptUpdated.tr(),
      );
      await press(tester);
      await tester.pump(momentum);
      await press(tester);
      expect(starts(), 0);

      await tester.pump(swapCommitArmingDelay);
      await press(tester);
      expect(starts(), 1);
    });

    testWidgets('is held again when the terms change under the same status', (
      tester,
    ) async {
      final first = reviewing(
        SwapReviewStatus.materialUpdate,
        quote: quoteOf(guaranteed: '2935'),
        previous: quoteOf(),
      );
      await show(tester, first);
      await tester.pump(swapCommitArmingDelay);

      await emitSwapState(
        tester,
        swap,
        reviewing(
          SwapReviewStatus.materialUpdate,
          quote: quoteOf(guaranteed: '2900'),
          previous: quoteOf(),
        ),
      );
      await press(tester);
      expect(starts(), 0);

      await tester.pump(swapCommitArmingDelay);
      await press(tester);
      expect(starts(), 1);
    });

    testWidgets('is held again each time it comes back from a check', (
      tester,
    ) async {
      final ready = reviewing(SwapReviewStatus.ready);
      await show(tester, ready);
      await tester.pump(swapCommitArmingDelay);

      await emitSwapState(tester, swap, reviewing(SwapReviewStatus.expired));
      await emitSwapState(tester, swap, ready);
      await press(tester);
      expect(starts(), 0);

      await tester.pump(swapCommitArmingDelay);
      await press(tester);
      expect(starts(), 1);
    });

    testWidgets('is held again when it becomes available: acceptance asked '
        'for, documents loaded, swaps enabled', (tester) async {
      final ready = reviewing(SwapReviewStatus.ready);
      for (final before in [
        // Pressing now also accepts terms that were not asked for before.
        ready,
        reviewing(SwapReviewStatus.ready, legal: false),
        ready.copyWith(tradingEnabled: false),
      ]) {
        swap.events.clear();
        await show(tester, before);
        await tester.pump(swapCommitArmingDelay);

        await emitSwapState(
          tester,
          swap,
          reviewing(
            SwapReviewStatus.ready,
            termsRequired: identical(before, ready),
          ),
        );
        await press(tester);
        expect(starts(), 0);

        await tester.pump(swapCommitArmingDelay);
        await press(tester);
        expect(starts(), 1);
      }
    });

    testWidgets('holds approve-and-start the same way', (tester) async {
      final approving = quoteOf(
        from: usdc,
        to: eth,
        sell: '1250',
        expected: '0.41',
        guaranteed: '0.4',
        approval: SwapApprovalRequirement(
          asset: usdc,
          exactAmount: d('1250'),
          resetsFirst: false,
        ),
      );
      await show(tester, reviewing(SwapReviewStatus.ready, quote: approving));
      expect(
        tester.widget<SwapButton>(start).label,
        LocaleKeys.swapStartApprove.tr(args: ['1,250 USDC']),
      );

      await press(tester);
      expect(starts(), 0);
      await tester.pump(swapCommitArmingDelay);
      await press(tester);
      expect(starts(), 1);
    });

    testWidgets('does not hold back what commits nothing', (tester) async {
      await show(tester, reviewing(SwapReviewStatus.expired));
      await tester.tap(find.text(LocaleKeys.swapCtaRefresh.tr()));
      expect(starts(), 1);

      await tester.tap(find.byTooltip(LocaleKeys.back.tr()));
      expect(swap.events.last, const UnifiedSwapReviewClosed());
    });

    testWidgets('leaves no timer behind when the review closes mid-window', (
      tester,
    ) async {
      await show(tester, reviewing(SwapReviewStatus.ready));
      await emitSwapState(tester, swap, swapPricedForm());
      expect(start, findsNothing);
      // A pending timer would fail the test as it ends.
    });
  });

  group('the layout', () {
    for (final (name, size, scale) in [
      ('a phone', phone, 1.0),
      ('a small phone', const Size(320, 640), 1.0),
      ('a phone at 200% text', phone, 2.0),
      ('a small phone at 200% text', const Size(360, 740), 2.0),
    ]) {
      testWidgets('a first routed swap is accessible and whole on $name', (
        tester,
      ) async {
        await show(
          tester,
          reviewing(SwapReviewStatus.ready, termsRequired: true),
          size: size,
          textScale: scale,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(start.hitTestable(), findsOneWidget);
        await expectSwapAccessible(tester, largeText: scale > 1);
      });

      testWidgets('changed terms are accessible and whole on $name', (
        tester,
      ) async {
        await show(
          tester,
          reviewing(
            SwapReviewStatus.materialUpdate,
            quote: quoteOf(expected: '2950', guaranteed: '2935'),
            previous: quoteOf(),
          ),
          size: size,
          textScale: scale,
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const Key('swap-review-changed')).hitTestable(),
          findsOneWidget,
        );
        await expectSwapAccessible(tester, largeText: scale > 1);
      });
    }

    testWidgets('the destination address never breaks across lines', (
      tester,
    ) async {
      await show(
        tester,
        reviewing(SwapReviewStatus.ready),
        size: const Size(320, 640),
        textScale: 2,
      );
      await tester.pumpAndSettle();

      // The label, after its icon.
      final paragraph = tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byKey(const Key('swap-review-destination')),
              matching: find.byType(RichText),
            )
            .last,
      );
      final text = paragraph.text.toPlainText();
      final address = text.indexOf('0x');
      // Until the label's own string is in, there is no address to break.
      if (address < 0) return;
      final lines = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: address, extentOffset: text.length),
          )
          .map((box) => box.top.round())
          .toSet();
      expect(lines, hasLength(1), reason: text);
    });
  });
}
