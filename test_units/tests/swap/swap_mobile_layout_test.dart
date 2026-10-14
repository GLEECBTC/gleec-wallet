// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/main_layout/main_layout.dart';
import 'package:web_dex/views/swap/common/swap_links.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/entry/swap_quote_strip.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';
import 'package:web_dex/views/swap/pickers/swap_slippage_sheet.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

part 'swap_mobile_layout_screens.dart';

const iPhoneSe = Size(375, 667);
const compactAndroid = Size(360, 740);
const sideways = Size(812, 375);
const tablet = Size(1024, 800);

final ethArb = assetOf(
  'ETH-ARB20',
  name: 'Ethereum',
  subClass: CoinSubClass.arbitrum,
  chainId: 42161,
);
final usdcArb = assetOf(
  'USDC-ARB20',
  subClass: CoinSubClass.arbitrum,
  parent: ethArb,
  chainId: 42161,
  decimals: 6,
);
final btcLegacy = assetOf(
  'BTC',
  name: 'Bitcoin',
  subClass: CoinSubClass.utxo,
  chainId: 0,
  decimals: 8,
);
final btcSegwit = assetOf(
  'BTC-segwit',
  name: 'Bitcoin',
  subClass: CoinSubClass.utxo,
  chainId: 0,
  decimals: 8,
);

late RecordingSwapBloc swap;
late FakeSwapServices services;

Future<void> pump(
  WidgetTester tester,
  UnifiedSwapState state, {
  Size size = iPhoneSe,
  Widget view = const SwapEntryView(),
}) async {
  swap.emit(state);
  await pumpSwapUi(tester, view, bloc: swap, services: services, size: size);
}

final footer = find.byType(SwapStickyFooter);

bool cut(WidgetTester tester, String text) => tester
    .renderObjectList<RenderParagraph>(find.text(text))
    .any((paragraph) => paragraph.didExceedMaxLines);

/// The most lines any [text] on screen sets on.
int lines(WidgetTester tester, String text) => tester
    .renderObjectList<RenderParagraph>(find.text(text))
    .map(
      (paragraph) => paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: text.length),
          )
          .map((box) => box.top.round())
          .toSet()
          .length,
    )
    .fold(0, (a, b) => a > b ? a : b);

/// The swap screens at real phone sizes: the main action always in reach,
/// nothing a phone has no room for, and every label whole.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
  });

  tearDown(() => swap.close());

  _formCases();
  _cardCases();
  _pickerCases();
  _reviewCases();
  _sheetCases();
  _fabCases();
}

void _formCases() {
  group('the form on a phone', () {
    testWidgets('pins the main action, in reach however far it scrolls', (
      tester,
    ) async {
      await pump(tester, swapPricedForm());

      expect(
        find.descendant(of: footer, matching: swapPrimaryAction),
        findsOneWidget,
      );
      expect(swapPrimaryAction.hitTestable(), findsOneWidget);
      final before = tester.getTopLeft(swapPrimaryAction);

      await tester.drag(find.byType(SwapQuoteStrip), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(swapPrimaryAction), before);
      expect(swapPrimaryAction.hitTestable(), findsOneWidget);
    });

    testWidgets('pins it too on a phone held sideways', (tester) async {
      await pump(tester, swapPricedForm(), size: sideways);

      expect(
        find.descendant(of: footer, matching: swapPrimaryAction),
        findsOneWidget,
      );
    });

    testWidgets('names the screen for screen readers, not with a title', (
      tester,
    ) async {
      await pump(tester, swapPricedForm());

      expect(find.text('Swap'), findsNothing);
      expect(
        find.semantics.byPredicate((node) {
          final data = node.getSemanticsData();
          return data.label == 'Swap' &&
              data.flagsCollection.isHeader &&
              data.flagsCollection.namesRoute;
        }),
        findsOneWidget,
      );
    });

    testWidgets('a drag or a tap elsewhere puts the keyboard away', (
      tester,
    ) async {
      await pump(tester, swapPricedForm());

      expect(
        tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );

      final amount = find.byKey(const Key('swap-amount'));
      await tester.showKeyboard(amount);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tapAt(tester.getTopLeft(find.text('You receive')));
      await tester.pumpAndSettle();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextField>(),
        isNull,
      );
    });

    testWidgets('a failed activation is said under the cards, leaving the '
        'pinned button free to try again', (tester) async {
      services.activationError = StateError('offline');
      await pump(
        tester,
        swapBaseForm().copyWith(
          issue: SwapFormIssue.assetInactive,
          catalog: SwapCatalog(
            sources: swapTestCatalog.sources,
            activated: {eth},
          ),
        ),
      );

      await tester.tap(swapPrimaryAction);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text("Couldn't activate USDC. Try again."), findsOneWidget);
      expect(swapPrimaryAction.hitTestable(), findsOneWidget);

      services.activationError = null;
      await tester.tap(swapPrimaryAction);
      await tester.pumpAndSettle();
      expect(services.activations, [usdc, usdc]);
      expect(find.text("Couldn't activate USDC. Try again."), findsNothing);
    });
  });

  group('the form on a wide screen', () {
    testWidgets('draws no title either, and the main action follows the '
        'quote', (tester) async {
      await pump(tester, swapPricedForm(), size: tablet);

      expect(footer, findsNothing);
      expect(find.text('Swap'), findsNothing);
      expect(
        find.semantics.byPredicate(
          (node) =>
              node.getSemanticsData().label == 'Swap' &&
              node.getSemanticsData().flagsCollection.isHeader,
        ),
        findsOneWidget,
      );
      expect(
        above(tester, find.byType(SwapQuoteStrip), swapPrimaryAction),
        isTrue,
      );
    });
  });
}

void _cardCases() {
  group('the amount cards', () {
    testWidgets('signed out, hold no empty row for an address', (tester) async {
      await pump(
        tester,
        swapBaseForm().copyWith(signedIn: false, clearBalance: true),
      );

      expect(
        find.descendant(
          of: find.byType(SwapPayCard),
          matching: find.byType(Divider),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(SwapReceiveCard),
          matching: find.byType(Divider),
        ),
        findsNothing,
      );
    });

    testWidgets('signed in, keep the row an address is on its way to', (
      tester,
    ) async {
      await pump(
        tester,
        swapBaseForm(input: '').copyWith(issue: SwapFormIssue.amountMissing),
      );

      expect(
        find.descendant(
          of: find.byType(SwapReceiveCard),
          matching: find.byType(Divider),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an asset button keeps its whole label on a 360 px phone', (
      tester,
    ) async {
      await pump(
        tester,
        swapBaseForm(input: '').copyWith(clearPay: true, clearReceive: true),
        size: compactAndroid,
      );
      expect(find.text('Select asset'), findsNWidgets(3));
      expect(cut(tester, 'Select asset'), isFalse);

      services.known = [...services.known, ethArb, usdcArb];
      await pump(
        tester,
        swapBaseForm(
          pay: ethArb,
          receive: usdcArb,
          input: '',
        ).copyWith(issue: SwapFormIssue.amountMissing),
        size: compactAndroid,
      );
      expect(find.text('Arbitrum'), findsNWidgets(2));
      expect(cut(tester, 'Arbitrum'), isFalse);
      expect(lines(tester, 'Arbitrum'), 1);
    });

    testWidgets('a SegWit coin says so beside its network', (tester) async {
      services.known = [...services.known, btcSegwit];
      await pump(
        tester,
        swapBaseForm(
          pay: btcSegwit,
          input: '',
        ).copyWith(issue: SwapFormIssue.amountMissing),
      );

      expect(find.text('Bitcoin · SegWit'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(SwapAssetPill).first),
        isSemantics(label: 'You pay: BTC, Bitcoin · SegWit', isButton: true),
      );
    });

    testWidgets('a difference from the market that rounds to nothing is not '
        'shown', (tester) async {
      SwapQuote priced(String expectedUsd) => quoteOf(
        pricing: pricingOf(pay: '3000', expected: expectedUsd),
      );

      await pump(tester, swapPricedForm(ranked: [priced('2999')]));
      expect(find.textContaining('vs market'), findsNothing);

      await pump(tester, swapPricedForm(ranked: [priced('2970')]));
      expect(find.text('−1% vs market'), findsOneWidget);
    });
  });
}

void _pickerCases() {
  group('the picker', () {
    final bitcoins = SwapCatalog(
      sources: [
        SwapSourceAssets(
          source: SwapLiquiditySource.atomic,
          quotable: {btcLegacy, btcSegwit, eth},
        ),
      ],
      activated: {btcLegacy, btcSegwit, eth},
    );

    SwapAssetPicker picker({bool signedIn = true}) => SwapAssetPicker(
      side: SwapPickerSide.pay,
      catalog: bitcoins,
      selected: null,
      other: null,
      services: services,
      isBlocked: (_) => false,
      signedIn: signedIn,
    );

    testWidgets('tells legacy and SegWit bitcoin apart', (tester) async {
      services.known = [btcLegacy, btcSegwit, eth];
      services.activated = {btcLegacy, btcSegwit, eth};
      await openSwapRoute(
        tester,
        picker(),
        bloc: swap,
        services: services,
        size: iPhoneSe,
      );

      expect(find.text('Bitcoin'), findsOneWidget);
      expect(find.text('Bitcoin · SegWit'), findsOneWidget);
    });

    testWidgets('signed out, offers no My assets and opens on Popular', (
      tester,
    ) async {
      services.known = [btcLegacy, btcSegwit, eth];
      await openSwapRoute(
        tester,
        picker(signedIn: false),
        bloc: swap,
        services: services,
        size: iPhoneSe,
      );

      expect(find.text('My assets'), findsNothing);
      final popular = tester.getSemantics(find.text('Popular'));
      expect(popular, isSemantics(isSelected: true));
    });

    testWidgets('its search hint fits one line on a 360 px phone', (
      tester,
    ) async {
      services.known = [btcLegacy, btcSegwit, eth];
      await openSwapRoute(
        tester,
        picker(),
        bloc: swap,
        services: services,
        size: compactAndroid,
      );

      expect(lines(tester, 'Search asset, network or contract'), 1);
    });
  });
}
