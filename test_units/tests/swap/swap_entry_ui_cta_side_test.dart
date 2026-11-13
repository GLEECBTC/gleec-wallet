// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers which picker "Choose another asset" opens for a pair no source
/// trades: the side holding an asset nothing here swaps, else what is
/// received.
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

  /// [pay] for [receive] where the order book trades [orderBook] and
  /// cross-network routes trade [routes].
  Future<void> pump(
    WidgetTester tester, {
    required AssetId pay,
    required AssetId receive,
    required Set<AssetId> orderBook,
    Set<AssetId> routes = const {},
  }) async {
    swap.emit(
      swapBaseForm(pay: pay, receive: receive).copyWith(
        issue: SwapFormIssue.pairUnsupported,
        catalog: SwapCatalog(
          sources: [
            SwapSourceAssets(
              source: SwapLiquiditySource.atomic,
              quotable: orderBook,
            ),
            SwapSourceAssets(
              source: SwapLiquiditySource.routed,
              quotable: routes,
            ),
          ],
        ),
      ),
    );
    await pumpSwapUi(
      tester,
      const SwapEntryView(),
      bloc: swap,
      services: services,
    );
  }

  Future<void> chooseAnother(WidgetTester tester) async {
    expect(swapPrimaryLabel(tester), 'Choose another asset');
    await tester.tap(swapPrimaryAction);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String ticker) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(SwapAssetPicker),
            matching: find.text(ticker),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  const btcUntradable =
      "BTC can't be swapped in this wallet. Choose another asset.";

  group('an asset nothing here swaps', () {
    testWidgets('is replaced where it is paid', (tester) async {
      await pump(tester, pay: btc, receive: eth, orderBook: {eth, gleec});

      expect(find.text(btcUntradable), findsOneWidget);
      await chooseAnother(tester);
      expect(find.text('What you pay with'), findsOneWidget);

      await choose(tester, 'GLEEC');
      expect(swap.events, [UnifiedSwapPayAssetChanged(gleec)]);
    });

    testWidgets('is replaced where it is received', (tester) async {
      await pump(tester, pay: eth, receive: btc, orderBook: {eth, gleec});

      expect(find.text(btcUntradable), findsOneWidget);
      await chooseAnother(tester);
      expect(find.text('What you receive'), findsOneWidget);

      await choose(tester, 'GLEEC');
      expect(swap.events, [UnifiedSwapReceiveAssetChanged(gleec)]);
    });

    testWidgets('on both sides is replaced first where the message names it', (
      tester,
    ) async {
      await pump(tester, pay: btc, receive: gleec, orderBook: {eth});

      expect(find.text(btcUntradable), findsOneWidget);
      await chooseAnother(tester);
      expect(find.text('What you pay with'), findsOneWidget);
    });
  });

  testWidgets('a pair split between sources changes what is received', (
    tester,
  ) async {
    // GLEEC is the limiting asset and is paid, but changing either side
    // fixes the pair.
    await pump(
      tester,
      pay: gleec,
      receive: usdc,
      orderBook: {eth, btc, gleec},
      routes: {eth, usdc},
    );

    expect(
      find.text(
        'USDC can only be swapped across networks, and GLEEC trades only on '
        'the order book. Choose another asset.',
      ),
      findsOneWidget,
    );
    await chooseAnother(tester);
    expect(find.text('What you receive'), findsOneWidget);
  });
}
