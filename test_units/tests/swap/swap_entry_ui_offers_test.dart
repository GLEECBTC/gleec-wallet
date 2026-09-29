// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/entry/swap_offer_alternatives.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers a pair only the order book trades: one no one offers says so
/// calmly, keeps checking and steers to the side worth changing, and one with
/// offers says what they take before an amount is typed.
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

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    List<BlocProvider> providers = const [],
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
      providers: providers,
    );
  }

  List<String> lines(WidgetTester tester) => [
    for (final line in tester.widgetList<SwapHelperLine>(
      find.byType(SwapHelperLine),
    ))
      line.text,
  ];

  Future<void> press(WidgetTester tester) async {
    await tester.tap(swapPrimaryAction);
    await tester.pumpAndSettle();
  }

  const none = SwapOrderBookOffers();

  /// [pay] for [receive] (ETH for GLEEC unless given), which no one offers.
  UnifiedSwapState noOffers({
    AssetId? pay,
    AssetId? receive,
    bool watching = true,
    SwapOfferCounts? payCounts,
    SwapOfferCounts? receiveCounts,
  }) {
    final paid = pay ?? eth;
    final received = receive ?? gleec;
    return swapBaseForm(pay: paid, receive: received).copyWith(
      issue: SwapFormIssue.noOffers,
      hints: SwapOrderBookHints(
        pair: (paid, received),
        offers: none,
        watching: watching,
        payCounts: payCounts,
        receiveCounts: receiveCounts,
      ),
    );
  }

  group('a pair no one offers', () {
    testWidgets('says so calmly, and that it keeps checking', (tester) async {
      await pump(tester, noOffers());

      expect(lines(tester), [
        'No one is offering GLEEC for ETH right now.',
        'GLEEC trades only on the order book, where offers come and go. '
            "We'll keep checking.",
      ]);
      for (final line in tester.widgetList<SwapHelperLine>(
        find.byType(SwapHelperLine),
      )) {
        expect(line.tone, SwapTone.neutral);
      }
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('keeps the order-book asset and changes the other', (
      tester,
    ) async {
      await pump(tester, noOffers());

      expect(swapPrimaryLabel(tester), 'Choose another asset');
      await press(tester);
      expect(find.text('What you pay with'), findsOneWidget);
    });

    testWidgets('selling an order-book asset changes what is received', (
      tester,
    ) async {
      await pump(tester, noOffers(pay: gleec, receive: eth));

      expect(
        lines(tester).first,
        'No one is offering ETH for GLEEC right now.',
      );
      await press(tester);
      expect(find.text('What you receive'), findsOneWidget);
    });

    testWidgets('an asset no one trades at all is the one to change', (
      tester,
    ) async {
      await pump(
        tester,
        noOffers(
          receiveCounts: SwapOfferCounts(gleec, {eth: false, btc: false}),
        ),
      );

      expect(
        lines(tester).first,
        'No one is trading GLEEC on the order book right now.',
      );
      await press(tester);
      expect(find.text('What you receive'), findsOneWidget);
    });

    testWidgets('signed out, asks for another asset rather than a wallet', (
      tester,
    ) async {
      await pump(tester, noOffers().copyWith(signedIn: false));

      expect(swapPrimaryLabel(tester), 'Choose another asset');
    });

    testWidgets('once it stops checking, offers to check again', (
      tester,
    ) async {
      await pump(tester, noOffers(watching: false));

      expect(
        lines(tester).last,
        'GLEEC trades only on the order book, where offers come and go.',
      );
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();
      expect(swap.events, [const UnifiedSwapOffersRequested(recount: true)]);
    });
  });

  group('shortcuts', () {
    AssetId coin(String id) =>
        assetOf(id, subClass: CoinSubClass.utxo, chainId: 0, decimals: 8);
    final kmd = coin('KMD');
    final ltc = coin('LTC');
    final doge = coin('DOGE');

    List<String> chips(WidgetTester tester) => [
      for (final chip in tester.widgetList<SwapButtonSemantics>(
        find.descendant(
          of: find.byType(SwapOfferAlternatives),
          matching: find.byType(SwapButtonSemantics),
        ),
      ))
        chip.label,
    ];

    testWidgets('offer up to three assets that trade it, held ones first', (
      tester,
    ) async {
      services
        ..balances = {ltc: d('3')}
        ..prices = {ltc: d('70')};
      await pump(
        tester,
        noOffers(
          receiveCounts: SwapOfferCounts(gleec, {
            eth: false,
            usdc: false,
            doge: true,
            btc: true,
            kmd: true,
            ltc: true,
          }),
        ),
      );

      expect(find.text('Get GLEEC with:'), findsOneWidget);
      expect(chips(tester), ['LTC, 3 held', 'BTC', 'KMD']);

      await tester.tap(find.text('BTC'));
      await tester.pumpAndSettle();
      expect(swap.events, [UnifiedSwapPayAssetChanged(btc)]);
    });

    testWidgets('selling an order-book asset, offer what it can buy', (
      tester,
    ) async {
      await pump(
        tester,
        noOffers(
          pay: gleec,
          receive: eth,
          payCounts: SwapOfferCounts(gleec, {btc: true}),
        ),
      );

      expect(find.text('Swap GLEEC for:'), findsOneWidget);
      await tester.tap(find.text('BTC'));
      await tester.pumpAndSettle();
      expect(swap.events, [UnifiedSwapReceiveAssetChanged(btc)]);
    });

    testWidgets('leave out assets unavailable here', (tester) async {
      final status = FakeTradingStatusBloc({btc});
      addTearDown(status.close);

      await pump(
        tester,
        noOffers(receiveCounts: SwapOfferCounts(gleec, {btc: true, kmd: true})),
        providers: [BlocProvider<TradingStatusBloc>.value(value: status)],
      );

      expect(chips(tester), ['KMD']);
    });

    testWidgets('none when no one trades the asset at all', (tester) async {
      await pump(
        tester,
        noOffers(receiveCounts: SwapOfferCounts(gleec, {btc: false})),
      );

      expect(find.byType(SwapOfferAlternatives), findsNothing);
    });
  });

  group('the pickers', () {
    Future<List<Object?>> openPicker(
      WidgetTester tester, {
      required SwapPickerSide side,
      required AssetId other,
      SwapOfferCounts? offered,
    }) => openSwapRoute(
      tester,
      SwapAssetPicker(
        side: side,
        catalog: swapTestCatalog,
        selected: null,
        other: other,
        services: services,
        isBlocked: (_) => false,
        offered: offered,
      ),
      bloc: swap,
      services: services,
    );

    double top(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text).first).dy;

    testWidgets('set apart what no one offers for the pay asset', (
      tester,
    ) async {
      final popped = await openPicker(
        tester,
        side: SwapPickerSide.receive,
        other: eth,
        offered: SwapOfferCounts(eth, {gleec: false, btc: true}),
      );

      const title = 'No offers with ETH right now';
      expect(find.text(title), findsOneWidget);
      expect(
        find.text(
          'No one is offering these for ETH right now. Offers come and go, '
          'so you can still pick one.',
        ),
        findsOneWidget,
      );
      expect(top(tester, 'GLEEC'), greaterThan(top(tester, title)));
      expect(top(tester, 'BTC'), lessThan(top(tester, title)));
      expect(find.text('No offers'), findsOneWidget);

      // Orders come and go, so it can still be chosen.
      await tester.tap(find.text('GLEEC').first);
      await tester.pumpAndSettle();
      expect(popped, [gleec]);
    });

    testWidgets('when paying, set apart what cannot buy the other asset', (
      tester,
    ) async {
      await openPicker(
        tester,
        side: SwapPickerSide.pay,
        other: gleec,
        offered: SwapOfferCounts(gleec, {eth: false, usdc: true}),
      );

      const title = 'No GLEEC offers for these right now';
      expect(find.text(title), findsOneWidget);
      expect(top(tester, 'ETH'), greaterThan(top(tester, title)));
      expect(top(tester, 'USDC'), lessThan(top(tester, title)));
    });

    testWidgets('counts for another asset set nothing apart', (tester) async {
      await openPicker(
        tester,
        side: SwapPickerSide.receive,
        other: eth,
        offered: SwapOfferCounts(usdc, {gleec: false}),
      );

      expect(find.text('No offers with ETH right now'), findsNothing);
      expect(find.text('No offers'), findsNothing);
    });

    testWidgets('open from the form with the counts it read', (tester) async {
      await pump(
        tester,
        noOffers(
          pay: usdc,
          receiveCounts: SwapOfferCounts(gleec, {usdc: false, btc: true}),
        ),
      );

      await press(tester);

      expect(find.text('What you pay with'), findsOneWidget);
      expect(find.text('No GLEEC offers for these right now'), findsOneWidget);
    });
  });

  testWidgets('before an amount, says what the offers take', (tester) async {
    final some = SwapOrderBookOffers([SwapOfferBand(d('0.5'), d('2'))]);

    await pump(
      tester,
      swapBaseForm(receive: gleec, input: '').copyWith(
        issue: SwapFormIssue.amountMissing,
        hints: SwapOrderBookHints(pair: (eth, gleec), offers: some),
      ),
    );

    expect(lines(tester), ['Offers take 0.5 ETH to 2 ETH.']);
  });
}
