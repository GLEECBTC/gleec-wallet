// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/entry/swap_amount_cards.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers choosing an asset from the form: the picker opens for the side
/// tapped, what is chosen goes to the bloc for that side, and the wallet's
/// region and settings shape what is offered.
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

  final payPill = find.byType(SwapAssetPill).first;
  final receivePill = find.byType(SwapAssetPill).last;

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    bool panelOpen = false,
    List<BlocProvider> providers = const [],
  }) async {
    swap.emit(state);
    await pumpSwapUi(
      tester,
      SwapEntryView(panelOpen: panelOpen),
      bloc: swap,
      services: services,
      providers: providers,
    );
  }

  Future<void> open(WidgetTester tester, Finder pill) async {
    await tester.tap(pill);
    await tester.pumpAndSettle();
  }

  /// A row's ticker in the picker; a native coin's network line repeats it,
  /// below, and the form behind the picker may show it too.
  Finder row(String ticker) => find
      .descendant(of: find.byType(SwapAssetPicker), matching: find.text(ticker))
      .first;

  testWidgets('the asset chosen to pay with goes to the bloc', (tester) async {
    await pump(tester, swapPricedForm());
    await open(tester, payPill);

    expect(find.text('What you pay with'), findsOneWidget);
    // Nothing held and nothing recent, so everything, by ticker.
    expect(above(tester, row('BTC'), row('ETH')), isTrue);
    expect(above(tester, row('ETH'), row('GLEEC')), isTrue);
    expect(find.text('Selected'), findsOneWidget);

    await tester.tap(row('BTC'));
    await tester.pumpAndSettle();
    expect(find.text('What you pay with'), findsNothing);
    expect(swap.events, [UnifiedSwapPayAssetChanged(btc)]);
  });

  testWidgets('the asset chosen to receive goes to the bloc', (tester) async {
    await pump(tester, swapPricedForm());
    await open(tester, receivePill);

    expect(find.text('What you receive'), findsOneWidget);
    await tester.tap(row('GLEEC'));
    await tester.pumpAndSettle();
    expect(swap.events, [UnifiedSwapReceiveAssetChanged(gleec)]);
  });

  testWidgets('a picker closed without a choice changes nothing', (
    tester,
  ) async {
    await pump(tester, swapPricedForm());
    await open(tester, payPill);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('What you pay with'), findsNothing);
    expect(swap.events, isEmpty);
  });

  testWidgets('choosing with the review open beside the form closes it', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm().copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(quote: quoteOf(), status: SwapReviewStatus.ready),
      ),
      panelOpen: true,
    );
    await open(tester, payPill);
    await tester.tap(row('BTC'));
    await tester.pumpAndSettle();

    expect(swap.events, [
      const UnifiedSwapReviewClosed(),
      UnifiedSwapPayAssetChanged(btc),
    ]);
  });

  testWidgets('an asset unavailable in this region cannot be chosen', (
    tester,
  ) async {
    final status = FakeTradingStatusBloc({btc});
    addTearDown(status.close);
    await pump(
      tester,
      swapPricedForm(),
      providers: [BlocProvider<TradingStatusBloc>.value(value: status)],
    );
    await open(tester, payPill);

    expect(find.text('Unavailable here'), findsOneWidget);
    await tester.tap(row('BTC'));
    await tester.pumpAndSettle();
    expect(find.text('What you pay with'), findsOneWidget);
    expect(services.activations, isEmpty);
    expect(swap.events, isEmpty);

    await tester.tap(row('GLEEC'));
    await tester.pumpAndSettle();
    expect(swap.events, [UnifiedSwapPayAssetChanged(gleec)]);
  });

  testWidgets('a list that may be incomplete is reloaded through the bloc', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm().copyWith(
        catalog: SwapCatalog(
          sources: [
            swapTestCatalog.sources.first,
            SwapSourceAssets(
              source: SwapLiquiditySource.routed,
              quotable: {eth, usdc},
              status: SwapCatalogStatus.stale,
            ),
          ],
        ),
      ),
    );
    await open(tester, payPill);

    expect(
      find.text(
        "Some swap options couldn't load, so this list may be incomplete.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    expect(swap.events, [const UnifiedSwapCatalogRefreshRequested()]);
  });

  group('inactive test-network assets', () {
    setUp(() {
      services
        ..activated = {eth, usdc, gleec}
        ..testnets = {btc};
    });

    for (final (setting, offered) in [(false, false), (true, true)]) {
      testWidgets('are ${offered ? '' : 'not '}offered with test coins '
          '${setting ? 'on' : 'off'}', (tester) async {
        final settings = FakeSettingsBloc(testCoins: setting);
        addTearDown(settings.close);
        await pump(
          tester,
          swapPricedForm(),
          providers: [BlocProvider<SettingsBloc>.value(value: settings)],
        );
        await open(tester, payPill);

        expect(find.text('BTC'), offered ? findsWidgets : findsNothing);
        expect(find.text('GLEEC'), findsWidgets);
      });
    }

    testWidgets('are offered when the setting cannot be read', (tester) async {
      await pump(tester, swapPricedForm());
      await open(tester, payPill);

      expect(find.text('BTC'), findsWidgets);
      expect(find.text('Not active'), findsOneWidget);
    });
  });

  testWidgets('a picker opened while the assets load fills in as they do', (
    tester,
  ) async {
    await pump(
      tester,
      swapPricedForm().copyWith(
        loadingAssets: true,
        catalog: SwapCatalog.empty,
      ),
    );
    await tester.tap(payPill);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.bySemanticsLabel('Loading assets'), findsOneWidget);
    expect(find.text('GLEEC'), findsNothing);

    await emitSwapState(tester, swap, swapPricedForm());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Loading assets'), findsNothing);
    expect(find.text('GLEEC'), findsWidgets);
  });
}
