// The analyzer does not treat test_units as tests, so test-only members
// read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
// No public API resets the package's global translations between groups.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/shared/swap/swap_catalog.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/pickers/swap_asset_picker.dart';

import 'swap_test_fixtures.dart';

class _EnglishAssetLoader extends AssetLoader {
  const _EnglishAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

/// Covers what the picker offers: every asset some source can trade, the
/// inactive ones activated only when chosen, and — for what to receive —
/// the assets the pay asset cannot reach, set apart with the reason. When
/// paying, assets without a balance can be hidden.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final gleecEvm = assetOf(
    'GLEEC',
    subClass: CoinSubClass.grc20,
    chainId: 11169,
  );
  final paxg = assetOf('PAXG-ERC20', parent: eth);
  final testEth = assetOf('SEPOLIAETH', chainId: 11155111);

  late _PickerServices services;
  late Set<AssetId> activated;

  SwapCatalog catalog({
    SwapCatalogStatus routedStatus = SwapCatalogStatus.fresh,
  }) => SwapCatalog(
    sources: [
      SwapSourceAssets(
        source: SwapLiquiditySource.atomic,
        quotable: {eth, usdc, gleecEvm, btc}.intersection(activated),
        onceActive: {eth, usdc, gleecEvm, btc}.difference(activated),
      ),
      SwapSourceAssets(
        source: SwapLiquiditySource.routed,
        quotable: {eth, usdc, paxg, testEth}.intersection(activated),
        onceActive: {eth, usdc, paxg, testEth}.difference(activated),
        status: routedStatus,
      ),
    ],
    activated: activated,
  );

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    activated = {eth, usdc, gleecEvm, btc, paxg};
    services = _PickerServices(() => activated);
  });

  tearDown(() => Localization.load(const Locale('en')));

  /// Opens the picker as a route and returns what it pops with.
  Future<List<AssetId?>> open(
    WidgetTester tester,
    SwapAssetPicker picker,
  ) async {
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final popped = <AssetId?>[];
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const _EnglishAssetLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: ThemeData.dark(),
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => popped.add(
                    await Navigator.of(context).push<AssetId>(
                      MaterialPageRoute(builder: (_) => Scaffold(body: picker)),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('what the pay asset cannot reach is set apart, with why', (
    tester,
  ) async {
    await open(
      tester,
      SwapAssetPicker(
        side: SwapPickerSide.receive,
        catalog: catalog(),
        selected: null,
        other: gleecEvm,
        services: services,
        isBlocked: (_) => false,
      ),
    );

    expect(find.text('Not available with GLEEC'), findsOneWidget);
    expect(
      find.text(
        "GLEEC trades only on the order book, where these assets aren't "
        'listed.',
      ),
      findsOneWidget,
    );
    // The unreachable token sits below the header; the reachable ones above.
    final header = tester.getTopLeft(find.text('Not available with GLEEC'));
    final paxgRow = tester.getTopLeft(find.text(SwapFormat.ticker(paxg)));
    final usdcRow = tester.getTopLeft(find.text(SwapFormat.ticker(usdc)));
    expect(paxgRow.dy, greaterThan(header.dy));
    expect(usdcRow.dy, lessThan(header.dy));
  });

  testWidgets('choosing an inactive asset activates it, then returns it', (
    tester,
  ) async {
    activated = {eth, gleecEvm};
    final popped = await open(
      tester,
      SwapAssetPicker(
        side: SwapPickerSide.pay,
        catalog: catalog(),
        selected: null,
        other: null,
        services: services,
        isBlocked: (_) => false,
      ),
    );

    // The ticker, not the network line that repeats it for a native coin.
    await tester.tap(find.text(SwapFormat.ticker(btc)).first);
    await tester.pumpAndSettle();

    expect(services.activated, [btc]);
    expect(popped, [btc]);
  });

  testWidgets('a list that could not load says so and offers a retry', (
    tester,
  ) async {
    var retries = 0;
    await open(
      tester,
      SwapAssetPicker(
        side: SwapPickerSide.pay,
        catalog: catalog(routedStatus: SwapCatalogStatus.stale),
        selected: null,
        other: null,
        services: services,
        isBlocked: (_) => false,
        onRetryCatalog: () => retries++,
      ),
    );

    expect(
      find.text(
        "Some swap options couldn't load, so this list may be incomplete.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('inactive test-network assets stay hidden when asked', (
    tester,
  ) async {
    await open(
      tester,
      SwapAssetPicker(
        side: SwapPickerSide.pay,
        catalog: catalog(),
        selected: null,
        other: null,
        services: services..testnets = {testEth},
        isBlocked: (_) => false,
        showTestCoins: false,
      ),
    );

    expect(find.text(SwapFormat.ticker(testEth)), findsNothing);
    expect(find.text(SwapFormat.ticker(paxg)), findsOneWidget);
  });

  group('hide 0 balance assets', () {
    const hideZero = 'Hide 0 balance assets';

    SwapAssetPicker picker(SwapPickerSide side) => SwapAssetPicker(
      side: side,
      catalog: catalog(),
      selected: null,
      other: null,
      services: services,
      isBlocked: (_) => false,
    );

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    testWidgets('is offered when paying, beside every group but My assets', (
      tester,
    ) async {
      services.balances = {eth: d('1.5')};
      await open(tester, picker(SwapPickerSide.pay));

      expect(find.text('My assets'), findsOneWidget);
      expect(find.text(hideZero), findsNothing);
      for (final tab in ['Recent', 'Popular', 'All']) {
        await tapText(tester, tab);
        expect(find.text(hideZero), findsOneWidget, reason: tab);
      }
    });

    testWidgets('is not offered when choosing what to receive', (tester) async {
      services.balances = {eth: d('1.5')};
      await open(tester, picker(SwapPickerSide.receive));

      await tapText(tester, 'All');
      expect(find.text(hideZero), findsNothing);
    });

    testWidgets('keeps what the wallet holds, counts the rest, and sticks', (
      tester,
    ) async {
      services.balances = {
        eth: d('1.5'),
        usdc: Decimal.zero,
        btc: Decimal.zero,
        gleecEvm: Decimal.zero,
      };
      await open(tester, picker(SwapPickerSide.pay));
      await tapText(tester, 'All');
      await tapText(tester, hideZero);

      // Zero balances and an inactive asset are hidden.
      expect(find.text(SwapFormat.ticker(usdc)), findsNothing);
      expect(find.text(SwapFormat.ticker(testEth)), findsNothing);
      expect(find.text('4 hidden'), findsOneWidget);
      expect(find.text(SwapFormat.ticker(eth)), findsWidgets);
      // PAXG's balance has not been read yet; it may hold funds.
      expect(find.text(SwapFormat.ticker(paxg)), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await open(tester, picker(SwapPickerSide.pay));
      await tapText(tester, 'All');
      expect(
        tester.widget<Switch>(find.byType(Switch)).value,
        isTrue,
        reason: 'the choice is remembered',
      );
    });

    testWidgets('a list it empties offers every asset back', (tester) async {
      services.balances = {for (final id in activated) id: Decimal.zero};
      await services.preferences.rememberHideZeroBalances(true);
      await open(tester, picker(SwapPickerSide.pay));

      // Nothing is held, so the picker opens on All, with everything hidden.
      expect(find.text('No assets with a balance here'), findsOneWidget);
      await tapText(tester, 'Show all assets');

      expect(find.text(SwapFormat.ticker(paxg)), findsOneWidget);
      expect(await services.preferences.hideZeroBalances(), isFalse);
    });

    testWidgets('search honours it, and says a match is hidden', (
      tester,
    ) async {
      services.balances = {eth: d('1.5'), paxg: Decimal.zero};
      await services.preferences.rememberHideZeroBalances(true);
      await open(tester, picker(SwapPickerSide.pay));

      await tester.enterText(find.byType(TextField), 'paxg');
      await tester.pumpAndSettle();
      expect(
        find.text('No assets with a balance match “paxg”'),
        findsOneWidget,
      );

      await tapText(tester, 'Show all assets');
      expect(find.text(SwapFormat.ticker(paxg)), findsOneWidget);
    });
  });
}

class _PickerServices implements SwapServices {
  _PickerServices(this._activated);

  final Set<AssetId> Function() _activated;
  final List<AssetId> activated = [];
  Set<AssetId> testnets = {};
  Map<AssetId, Decimal> balances = {};

  @override
  late final SwapPreferences preferences = SwapPreferences(
    walletKey: () async => 'w',
    storage: MemoryStorage(),
  );

  @override
  Future<Set<AssetId>> activatedAssets() async => _activated();

  @override
  Future<void> activate(AssetId id) async => activated.add(id);

  @override
  bool isTestnet(AssetId id) => testnets.contains(id);

  @override
  SwapNetworks networks() => SwapNetworks([eth, usdc, btc]);

  @override
  AssetId? resolveAsset(String ticker) => null;

  @override
  String? contractOf(AssetId id) => null;

  @override
  Decimal? lastKnownBalance(AssetId id) => balances[id];

  @override
  Decimal? usdPrice(AssetId id) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
