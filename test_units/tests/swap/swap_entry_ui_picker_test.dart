import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers finding an asset in the picker: a wallet that cannot be read,
/// search, each group and its order, an activation that fails, and the
/// chosen asset's full identity.
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

  const usdcContract = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';

  Future<List<Object?>> open(
    WidgetTester tester, {
    SwapCatalog? catalog,
    AssetId? selected,
  }) => openSwapRoute(
    tester,
    SwapAssetPicker(
      side: SwapPickerSide.pay,
      catalog: catalog ?? swapTestCatalog,
      selected: selected,
      other: null,
      services: services,
      isBlocked: (_) => false,
    ),
    bloc: swap,
    services: services,
  );

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).first);
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pumpAndSettle();
  }

  testWidgets('a wallet that cannot be read says so, and is read again', (
    tester,
  ) async {
    services.loadError = StateError('locked');
    await open(tester);

    expect(find.text("We couldn't load assets"), findsOneWidget);
    expect(find.text('Your current swap stays unchanged.'), findsOneWidget);

    services.loadError = null;
    await tapText(tester, 'Try again');
    expect(find.text("We couldn't load assets"), findsNothing);
    expect(find.text('GLEEC'), findsWidgets);
  });

  group('search', () {
    testWidgets('finds a token by its contract, and names the contract', (
      tester,
    ) async {
      services.contracts = {usdc: usdcContract};
      await open(tester);
      await search(tester, 'a0b869');

      expect(find.text('USDC'), findsOneWidget);
      expect(find.text('Ethereum · 0xA0b8…eB48'), findsOneWidget);
      expect(find.text('GLEEC'), findsNothing);
      // The groups make no sense while searching.
      expect(find.text('My assets'), findsNothing);

      await tapText(tester, 'Clear');
      expect(find.text('My assets'), findsOneWidget);
      expect(find.text('GLEEC'), findsWidgets);
    });

    testWidgets('matches every word typed', (tester) async {
      await open(tester);
      await search(tester, 'usdc ethereum');

      expect(find.text('USDC'), findsOneWidget);
      expect(find.text('ETH'), findsNothing);
    });

    testWidgets('with no match says so, and clears from there', (tester) async {
      await open(tester);
      await search(tester, 'zzz');

      expect(find.text('No assets found for “zzz”'), findsOneWidget);
      expect(
        find.text('Search by asset, network, contract, or asset ID.'),
        findsOneWidget,
      );

      await tapText(tester, 'Clear search');
      expect(find.text('GLEEC'), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('the groups', () {
    testWidgets('My assets lists what is held, most valuable first', (
      tester,
    ) async {
      services
        ..balances = {eth: d('1'), usdc: d('5000'), btc: d('0.1')}
        ..prices = {eth: d('3000'), usdc: d('1'), btc: d('60000')};
      await open(tester);

      expect(above(tester, find.text('BTC').first, find.text('USDC')), isTrue);
      expect(above(tester, find.text('USDC'), find.text('ETH')), isTrue);
      expect(find.text(r'$6,000.00'), findsOneWidget);
      expect(find.text('5,000'), findsOneWidget);
      expect(find.text('GLEEC'), findsNothing);
    });

    testWidgets('empty groups say what would appear in them', (tester) async {
      await open(tester);

      // Nothing held and nothing recent: the picker opens on everything.
      expect(find.text('GLEEC'), findsWidgets);

      await tapText(tester, 'My assets');
      expect(find.text('No swappable balances'), findsOneWidget);
      expect(
        find.text('Assets you hold that can be swapped appear here.'),
        findsOneWidget,
      );

      await tapText(tester, 'Recent');
      expect(find.text('No recent assets'), findsOneWidget);
      expect(find.text('Assets you choose appear here.'), findsOneWidget);
    });

    testWidgets('Recent lists what was picked lately and is still offered', (
      tester,
    ) async {
      final doge = assetOf('DOGE', subClass: CoinSubClass.utxo, chainId: 0);
      for (final asset in [doge, btc, eth]) {
        await services.preferences.rememberAsset(asset);
      }
      await services.preferences.rememberAsset(assetOf('OLD'));
      services.tickers = {'ETH': eth, 'BTC': btc, 'DOGE': doge};
      await open(tester);

      // Opened there, since nothing is held.
      expect(find.text('ETH'), findsWidgets);
      expect(above(tester, find.text('ETH'), find.text('BTC').first), isTrue);
      expect(find.text('DOGE'), findsNothing);
      expect(find.text('GLEEC'), findsNothing);
    });

    testWidgets('Popular ranks the most traded first, by network on a tie', (
      tester,
    ) async {
      final ethOnArbitrum = assetOf(
        'ETH-ARB20',
        subClass: CoinSubClass.arbitrum,
        chainId: 42161,
      );
      final paxg = assetOf('PAXG-ERC20', parent: eth);
      services
        ..known = [eth, usdc, btc, gleec, ethOnArbitrum, paxg]
        ..activated = {eth, usdc, btc, gleec, ethOnArbitrum, paxg};
      await open(
        tester,
        catalog: SwapCatalog(
          sources: [
            SwapSourceAssets(
              source: SwapLiquiditySource.routed,
              quotable: {gleec, usdc, ethOnArbitrum, eth, btc, paxg},
            ),
          ],
        ),
      );
      await tapText(tester, 'Popular');

      expect(find.text('PAXG'), findsNothing);
      final eths = find.text('ETH');
      expect(eths, findsNWidgets(2));
      expect(above(tester, find.text('BTC').first, eths.first), isTrue);
      expect(
        above(tester, find.text('Arbitrum'), find.text('Ethereum').first),
        isTrue,
      );
      expect(above(tester, eths.last, find.text('USDC')), isTrue);
      expect(
        above(tester, find.text('USDC'), find.text('GLEEC').first),
        isTrue,
      );
    });

    testWidgets('Popular with nothing popular on offer says so', (
      tester,
    ) async {
      final paxg = assetOf('PAXG-ERC20', parent: eth);
      services.activated = {paxg};
      await open(
        tester,
        catalog: SwapCatalog(
          sources: [
            SwapSourceAssets(
              source: SwapLiquiditySource.routed,
              quotable: {paxg},
            ),
          ],
        ),
      );
      await tapText(tester, 'Popular');

      expect(find.text('No assets found'), findsOneWidget);
      expect(find.text('PAXG'), findsNothing);
    });

    testWidgets('All sorts by ticker, the native coin before its tokens', (
      tester,
    ) async {
      final bridgedEth = assetOf(
        'ETH-ARB20',
        subClass: CoinSubClass.arbitrum,
        chainId: 42161,
        parent: eth,
      );
      services
        ..known = [eth, usdc, btc, gleec, bridgedEth]
        ..activated = {eth, usdc, btc, gleec, bridgedEth};
      await open(
        tester,
        catalog: SwapCatalog(
          sources: [
            SwapSourceAssets(
              source: SwapLiquiditySource.routed,
              quotable: {usdc, bridgedEth, gleec, eth, btc},
            ),
          ],
        ),
      );

      final eths = find.text('ETH');
      expect(above(tester, find.text('BTC').first, eths.first), isTrue);
      // Ethereum sorts after Arbitrum, but the native coin comes first.
      expect(
        above(tester, find.text('Ethereum').first, find.text('Arbitrum')),
        isTrue,
      );
      expect(above(tester, eths.last, find.text('GLEEC').first), isTrue);
    });
  });

  testWidgets('an activation that fails says so on its row, and can retry', (
    tester,
  ) async {
    services
      ..activated = {eth, usdc, gleec}
      ..activationError = StateError('offline');
    final popped = await open(tester);

    expect(find.text('Not active'), findsOneWidget);
    await tapText(tester, 'BTC');
    expect(find.text("Couldn't activate BTC. Try again."), findsOneWidget);
    expect(popped, isEmpty);

    services.activationError = null;
    await tapText(tester, 'BTC');
    expect(services.activations, [btc, btc]);
    expect(popped, [btc]);
  });

  testWidgets('the chosen asset\'s identity gives its id and contract', (
    tester,
  ) async {
    services.contracts = {usdc: usdcContract};
    final copied = recordClipboard(tester);
    await open(tester, selected: usdc);

    await tapText(tester, 'Full asset identity');
    expect(find.text('USDC · Ethereum'), findsOneWidget);
    expect(find.text('USDC-ERC20'), findsOneWidget);
    expect(find.text(usdcContract), findsOneWidget);

    await tester.tap(find.text('Copy').last);
    await tester.pumpAndSettle();
    expect(copied, [usdcContract]);
    expect(find.text('Contract copied'), findsOneWidget);
  });

  testWidgets('what only cross-network routes reach is explained', (
    tester,
  ) async {
    final paxg = assetOf('PAXG-ERC20', parent: eth);
    services.activated = {eth, usdc, btc, gleec, paxg};
    final popped = await openSwapRoute(
      tester,
      SwapAssetPicker(
        side: SwapPickerSide.receive,
        catalog: SwapCatalog(
          sources: [
            SwapSourceAssets(
              source: SwapLiquiditySource.atomic,
              quotable: {eth, usdc, btc, gleec},
            ),
            SwapSourceAssets(
              source: SwapLiquiditySource.routed,
              quotable: {eth, usdc, paxg},
            ),
          ],
        ),
        selected: null,
        other: paxg,
        services: services,
        isBlocked: (_) => false,
      ),
      bloc: swap,
      services: services,
    );

    expect(find.text('Not available with PAXG'), findsOneWidget);
    expect(
      find.text(
        "PAXG can only be swapped across networks, which don't reach these "
        'assets yet.',
      ),
      findsOneWidget,
    );
    expect(
      above(
        tester,
        find.text('Not available with PAXG'),
        find.text('BTC').first,
      ),
      isTrue,
    );

    await tapText(tester, 'BTC');
    expect(popped, isEmpty);
    await tapText(tester, 'USDC');
    expect(popped, [usdc]);
  });
}
