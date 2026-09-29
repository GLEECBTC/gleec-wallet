// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_order_book_offers.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';

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

  Future<void> pump(WidgetTester tester, UnifiedSwapState state) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
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
