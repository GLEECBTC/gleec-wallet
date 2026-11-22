// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/entry/swap_quote_strip.dart';

import '../../support/legal_documents_fixture.dart';
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers what the form holds still and what it says: the block under the
/// cards keeping its height through a price check, hints that outlast one,
/// placeholders where a figure is not known, and amounts read with their
/// unit.
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

  // Tall and wide: the main action follows the content rather than being
  // pinned, so anything that moves the content would move it.
  const desktop = Size(1280, 1400);

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    Size size = desktop,
    bool panelOpen = false,
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      SwapEntryView(panelOpen: panelOpen),
      bloc: swap,
      services: services,
      size: size,
      settle: false,
    );
    await tester.pump();
  }

  final region = find.byKey(const Key('swap-quote-region'));
  final empty = swapBaseForm(input: '')
      .copyWith(issue: SwapFormIssue.amountMissing);
  final checking = swapBaseForm().copyWith(
    evaluation: SwapEvaluationStatus.checking,
    quotesPending: true,
  );
  const failure = SwapQuoteFailure(
    source: SwapLiquiditySource.routed,
    kind: SwapQuoteFailureKind.serviceError,
    cause: SwapQuoteFailureCause.engine,
  );

  group('the block under the cards', () {
    testWidgets('keeps its height, and the action its place, from an empty '
        'amount through a check to a price or a failure', (tester) async {
      await pump(tester, empty);
      final block = tester.getRect(region);
      final action = tester.getRect(swapPrimaryAction);
      final cards = [
        tester.getRect(find.byType(SwapPayCard)),
        tester.getRect(find.byType(SwapReceiveCard)),
      ];
      // Its figures hold their place before there are any.
      expect(find.byType(SwapQuoteStrip), findsOneWidget);
      expect(action.top - block.bottom, 14);

      Future<void> expectStill(String moment, UnifiedSwapState state) async {
        await emitSwapState(tester, swap, state);
        expect(tester.getRect(region), block, reason: moment);
        expect(tester.getRect(swapPrimaryAction), action, reason: moment);
        expect(tester.getRect(find.byType(SwapPayCard)), cards[0]);
        expect(tester.getRect(find.byType(SwapReceiveCard)), cards[1]);
      }

      await expectStill('typed', swapBaseForm());
      await expectStill('checking', checking);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('swapQuoteSlow'.tr()), findsOneWidget);
      expect(tester.getRect(swapPrimaryAction), action);
      await expectStill('priced', swapPricedForm());
      await expectStill(
        'the best of two',
        swapPricedForm(
          ranked: [
            quoteOf(),
            quoteOf(id: 'other', expected: '2990', guaranteed: '2975'),
          ],
        ),
      );
      await expectStill(
        'failed',
        swapBaseForm().copyWith(
          evaluation: SwapEvaluationStatus.failed,
          failure: failure,
          failures: const [failure],
        ),
      );
      await expectStill('cleared', empty);
    });

    testWidgets('keeps no room before a pair is chosen', (tester) async {
      await pump(tester, swapBaseForm(input: '').copyWith(clearReceive: true));

      expect(tester.getSize(region).height, 0);
      expect(
        tester.getTopLeft(swapPrimaryAction).dy -
            tester.getBottomLeft(find.byType(SwapReceiveCard)).dy,
        14,
      );
    });

    testWidgets('holds placeholders only where the pair can be priced', (
      tester,
    ) async {
      await pump(tester, empty);
      expect(
        find.descendant(
          of: find.byType(SwapQuoteStrip),
          matching: find.text(SwapFormat.unknown),
        ),
        findsNWidgets(3),
      );
      expect(find.byType(SwapRatePlaceholder), findsOneWidget);
      // Nothing is being waited for yet, so nothing is said to be.
      expect(find.text(LocaleKeys.swapHelperChecking.tr()), findsNothing);

      await emitSwapState(
        tester,
        swap,
        swapBaseForm().copyWith(issue: SwapFormIssue.pairUnsupported),
      );
      expect(find.byType(SwapQuoteStrip), findsNothing);
      expect(find.byType(SwapRatePlaceholder), findsNothing);
    });

    testWidgets('a hint holds its place while a new estimate is on its way', (
      tester,
    ) async {
      UnifiedSwapState out(UnifiedSwapState state) =>
          state.copyWith(signedIn: false, clearBalance: true);

      await pump(tester, out(empty));
      final signedOut = LocaleKeys.swapHelperSignedOut.tr();
      final priced = LocaleKeys.swapHelperSignedOutPriced.tr();
      final place = tester.getTopLeft(find.text(signedOut));

      // Typing and checking do not take the hint away, or move it.
      for (final state in [swapBaseForm(), checking]) {
        await emitSwapState(tester, swap, out(state));
        expect(tester.getTopLeft(find.text(signedOut)), place);
      }
      // A price changes what there is to say, in the same place.
      await emitSwapState(tester, swap, out(swapPricedForm()));
      expect(find.text(signedOut), findsNothing);
      expect(tester.getTopLeft(find.text(priced)), place);
      // The next edit does not swap the hint back and forth.
      for (final state in [swapBaseForm(input: '2'), checking]) {
        await emitSwapState(tester, swap, out(state));
        expect(tester.getTopLeft(find.text(priced)), place);
        expect(find.text(signedOut), findsNothing);
      }
    });

    testWidgets('changed terms beside the form leave their figures to the '
        'review', (tester) async {
      final original = quoteOf();
      final reviewed = swapPricedForm(ranked: [original]).copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(
          legalSnapshot: legalFixtureSnapshot(),
          quote: original,
          status: SwapReviewStatus.ready,
        ),
      );
      await pump(tester, reviewed, panelOpen: true);
      final block = tester.getRect(region);
      expect(find.text('2,985 USDC'), findsOneWidget);
      expect(find.byType(SwapRateLine), findsOneWidget);

      await emitSwapState(
        tester,
        swap,
        reviewed.copyWith(
          review: reviewed.review!.copyWith(
            status: SwapReviewStatus.materialUpdate,
            previous: original,
            quote: quoteOf(id: 'new', expected: '2950', guaranteed: '2935'),
          ),
        ),
      );
      // The old minimum, cost and rate are gone, not shown beside the new.
      expect(find.byType(SwapQuoteStrip), findsNothing);
      expect(find.byType(SwapRateLine), findsNothing);
      expect(find.text('2,985 USDC'), findsNothing);
      expect(find.text('swapPreviousEstimate'.tr()), findsOneWidget);
      expect(tester.getRect(region), block);
    });
  });

  group('figures', () {
    Finder inPay(Finder finder) =>
        find.descendant(of: find.byType(SwapPayCard), matching: finder);
    Finder inReceive(Finder finder) =>
        find.descendant(of: find.byType(SwapReceiveCard), matching: finder);

    testWidgets('an amount with nothing to convert is a dash, not a zero', (
      tester,
    ) async {
      await pump(tester, empty.copyWith(amountMode: SwapAmountMode.fiat));
      expect(
        inPay(find.text(LocaleKeys.swapApproxToken.tr(args: ['—', 'ETH']))),
        findsOneWidget,
      );
      expect(find.textContaining('≈ 0'), findsNothing);
      // The dollar sign stands with the placeholder it belongs to.
      expect(inPay(find.text(r'$')), findsOneWidget);

      await emitSwapState(
        tester,
        swap,
        swapBaseForm(input: '.').copyWith(issue: SwapFormIssue.amountMalformed),
      );
      expect(inPay(find.text(SwapFormat.unknown)), findsOneWidget);
      expect(find.text(r'$0.00'), findsNothing);
    });

    testWidgets('the estimate is marked as one, and steps back once expired', (
      tester,
    ) async {
      Color amountColor() =>
          tester.widget<Text>(find.text('3,000')).style!.color!;
      await pump(tester, swapPricedForm());
      expect(inReceive(find.text('≈')), findsOneWidget);
      expect(amountColor(), SwapPalette.dark.text);

      await emitSwapState(
        tester,
        swap,
        swapPricedForm(evaluation: SwapEvaluationStatus.expired),
      );
      expect(amountColor(), SwapPalette.dark.textTertiary);
      expect(
        inReceive(find.text(LocaleKeys.swapReviewExpiredBadge.tr())),
        findsOneWidget,
      );

      // No estimate, no sign.
      await emitSwapState(tester, swap, checking);
      expect(inReceive(find.text('≈')), findsNothing);
    });

    testWidgets('are read with their asset and network, as one phrase', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, swapPricedForm());
      expect(
        tester.getSemantics(find.text('3,000')).label,
        'swapA11yReceiveEstimateUsd'.tr(
          args: [SwapFormat.onNetwork('3,000 USDC', 'Ethereum'), r'$3,000.00'],
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('swap-amount'))),
        isSemantics(
          label: 'swapAmountToPayIn'.tr(
            args: [SwapFormat.onNetwork('ETH', 'Ethereum')],
          ),
          isTextField: true,
        ),
      );

      await emitSwapState(
        tester,
        swap,
        checking.copyWith(amountMode: SwapAmountMode.fiat),
      );
      expect(
        tester.getSemantics(inReceive(find.text(SwapFormat.unknown))).label,
        '${'swapA11yNoEstimate'.tr()}. ${'swapEstimateUpdating'.tr()}',
      );
      expect(
        tester.getSemantics(find.byKey(const Key('swap-amount'))),
        isSemantics(label: 'swapAmountToPayInUsd'.tr(), isTextField: true),
      );
      semantics.dispose();
    });
  });

  group('the keyboard and the pointer', () {
    testWidgets('Enter in the amount opens the review once it can be', (
      tester,
    ) async {
      await pump(tester, checking);
      await tester.showKeyboard(find.byKey(const Key('swap-amount')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(swap.events, isEmpty);

      await emitSwapState(tester, swap, swapPricedForm());
      await tester.showKeyboard(find.byKey(const Key('swap-amount')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(swap.events, [const UnifiedSwapReviewOpened()]);
    });

    testWidgets('the switch takes a tap anywhere on its 48 dp circle', (
      tester,
    ) async {
      await pump(tester, swapPricedForm());
      final button = find.byType(SwapSwitchButton);
      expect(tester.getSize(button), const Size.square(48));

      // On the outer band, outside the disc it is drawn around.
      await tester.tapAt(tester.getCenter(button) + const Offset(21, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(swap.events, [const UnifiedSwapSidesSwitched()]);
    });
  });
}
