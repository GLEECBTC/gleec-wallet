// The analyzer does not treat test_units as tests, so test-only members
// read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_asset_row.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_assets_toolbar.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_balance_hero.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_assets.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_view.dart';

import 'wallet_home_fake_wallet.dart';
import 'wallet_home_harness.dart';

void main() {
  setUpAll(initWalletHomeLocalization);
  group('Wallet home on a wide screen', _wideCases);
  group('Wallet home view on a desktop', _desktopViewCases);
}

const _desktop = Size(1000, 800);

FakeWallet _wallet() => FakeWallet([
  (
    id: 'BTC',
    name: 'Bitcoin',
    subClass: CoinSubClass.utxo,
    price: 60052.95,
    change: -2.17,
    amount: 0.0821,
  ),
]);

class _FakeCoinsManager extends Cubit<CoinsManagerState>
    implements CoinsManagerBloc {
  _FakeCoinsManager() : super(CoinsManagerState.initial(coins: const []));

  final events = <CoinsManagerEvent>[];

  @override
  void add(CoinsManagerEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpAssets(
  WidgetTester tester, {
  required Size size,
  bool showAddAssets = true,
}) {
  final wallet = _wallet();
  return pumpWalletHome(
    tester,
    RepositoryProvider<KomodoDefiSdk>.value(
      value: wallet.sdk,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<CoinsBloc>(create: (_) => FakeWalletCoins(wallet.state)),
          BlocProvider<SettingsBloc>(create: (_) => FakeWalletSettings()),
        ],
        child: CustomScrollView(
          slivers: [
            WalletHomeAssets(
              searchPhrase: '',
              hideZeroBalances: false,
              onHideZeroBalances: (_) {},
              showAddAssets: showAddAssets,
            ),
          ],
        ),
      ),
    ),
    size: size,
  );
}

Future<({List<String> phrases, _FakeCoinsManager manager})> _pumpToolbar(
  WidgetTester tester, {
  required bool inline,
  bool addAssets = false,
  Size size = _desktop,
}) async {
  final phrases = <String>[];
  final manager = _FakeCoinsManager();
  final controller = TextEditingController();
  final focusNode = FocusNode();
  addTearDown(manager.close);
  addTearDown(controller.dispose);
  addTearDown(focusNode.dispose);
  await pumpWalletHome(
    tester,
    BlocProvider<CoinsManagerBloc>.value(
      value: manager,
      child: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: WalletAssetsToolbarDelegate(
              section: WalletHomeSection.assets,
              onSection: (_) {},
              searchOpen: false,
              onSearchOpen: () {},
              onSearchClose: () {},
              searchController: controller,
              searchFocusNode: focusNode,
              onSearchChanged: phrases.add,
              textScaler: TextScaler.noScaling,
              inlineSearch: inline,
              addAssets: addAssets,
            ),
          ),
        ],
      ),
    ),
    size: size,
  );
  return (phrases: phrases, manager: manager);
}

void _wideCases() {
  testWidgets('a wide row gives the price its own column', (tester) async {
    await _pumpAssets(tester, size: _desktop);

    final name = tester.getCenter(find.text('Bitcoin', findRichText: true));
    final price = tester.getCenter(find.text(r'$60,052.95'));
    final value = tester.getCenter(find.text(r'$4,930.35'));
    expect(find.text('−2.17%'), findsOneWidget);
    expect(price.dx, greaterThan(name.dx));
    expect(price.dx, lessThan(value.dx));
    expect(price.dy, closeTo(name.dy, 12));
  });

  testWidgets('a phone row keeps the price under the name', (tester) async {
    await _pumpAssets(tester, size: const Size(390, 844));

    expect(find.text(r'$60,052.95'), findsNothing);
    expect(
      find.textContaining(r'$60,052.95', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a row keys its price and the amount held', (tester) async {
    await _pumpAssets(tester, size: _desktop);
    expect(
      tester.widget<Text>(find.byKey(WalletAssetRow.priceKey)).data,
      r'$60,052.95',
    );
    expect(
      tester.widget<Text>(find.byKey(WalletAssetRow.amountKey('BTC'))).data,
      '0.0821 BTC',
    );

    await _pumpAssets(tester, size: const Size(390, 844));
    final line = tester.widget<Text>(find.byKey(WalletAssetRow.priceKey));
    expect(line.textSpan?.toPlainText(), startsWith(r'$60,052.95'));
  });

  testWidgets('a wide toolbar shows its search field without a tap', (
    tester,
  ) async {
    final (:phrases, manager: _) = await _pumpToolbar(tester, inline: true);

    expect(find.byKey(const Key('wallet-home-search-button')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('wallet-page-search-field')),
      'btc',
    );
    expect(phrases, ['btc']);
  });

  testWidgets('a phone toolbar opens search from its button', (tester) async {
    await _pumpToolbar(tester, inline: false);

    expect(find.byKey(const Key('wallet-home-search-button')), findsOneWidget);
    expect(find.byKey(const Key('wallet-page-search-field')), findsNothing);
    expect(find.byKey(WalletAddAssetsButton.buttonKey), findsNothing);
  });

  testWidgets('a wide toolbar opens the coins manager from Add assets', (
    tester,
  ) async {
    addTearDown(routingState.walletState.reset);
    final (phrases: _, :manager) = await _pumpToolbar(
      tester,
      inline: true,
      addAssets: true,
    );

    expect(find.text('Add assets'), findsOneWidget);
    await tester.tap(find.byKey(WalletAddAssetsButton.buttonKey));
    expect(
      manager.events.single,
      isA<CoinsManagerCoinsListReset>().having(
        (event) => event.action,
        'action',
        CoinsManagerAction.add,
      ),
    );
    expect(routingState.walletState.action, coinsManagerRouteAction.addAssets);
  });

  testWidgets('a narrow wide toolbar keeps Add assets to its icon', (
    tester,
  ) async {
    await _pumpToolbar(
      tester,
      inline: true,
      addAssets: true,
      size: const Size(700, 800),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(WalletAddAssetsButton.buttonKey), findsOneWidget);
    expect(find.text('Add assets'), findsNothing);
    expect(find.byTooltip('Add assets'), findsOneWidget);
  });

  testWidgets('a wide list leaves Add assets to the toolbar', (tester) async {
    await _pumpAssets(tester, size: _desktop, showAddAssets: false);

    expect(find.byKey(WalletAddAssetsButton.buttonKey), findsNothing);
    expect(find.byKey(const Key('coins-with-balance-checkbox')), findsOne);
  });

  testWidgets('the total keeps the key the desktop overview had', (
    tester,
  ) async {
    await pumpWalletHome(
      tester,
      BalanceHeroContent(
        total: 1234.56,
        change: null,
        hidden: false,
        onToggleHidden: () {},
      ),
      size: _desktop,
    );

    expect(find.byKey(BalanceHeroContent.totalKey), findsOneWidget);
  });

  testWidgets('sheets keep to a column off a phone', (tester) async {
    addTearDown(resetScreenType);
    expect(walletSheetConstraints, isNull);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1280, 800)),
        child: Builder(
          builder: (context) {
            updateScreenType(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(walletSheetConstraints?.maxWidth, 560);
  });
}

class _FakeOverview extends Cubit<AssetOverviewState>
    implements AssetOverviewBloc {
  _FakeOverview() : super(const AssetOverviewInitial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGrowth extends Cubit<PortfolioGrowthState>
    implements PortfolioGrowthBloc {
  _FakeGrowth() : super(const PortfolioGrowthInitial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Thirty assets: more than a desktop window shows at once.
FakeWallet _longWallet() => FakeWallet([
  for (var i = 0; i < 30; i++)
    (
      id: 'C$i',
      name: 'Coin $i',
      subClass: CoinSubClass.utxo,
      price: 1,
      change: 0,
      amount: 100.0 - i,
    ),
]);

/// The whole wallet home, laid out as on a 1600 by 1024 desktop window, as
/// the web integration tests run it.
Future<void> _pumpDesktopView(WidgetTester tester) async {
  addTearDown(resetScreenType);
  final wallet = _longWallet();
  final scroll = ScrollController();
  final manager = _FakeCoinsManager();
  addTearDown(scroll.dispose);
  addTearDown(manager.close);
  await pumpWalletHome(
    tester,
    RepositoryProvider<KomodoDefiSdk>.value(
      value: wallet.sdk,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<CoinsBloc>(create: (_) => FakeWalletCoins(wallet.state)),
          BlocProvider<SettingsBloc>(create: (_) => FakeWalletSettings()),
          BlocProvider<AssetOverviewBloc>(create: (_) => _FakeOverview()),
          BlocProvider<PortfolioGrowthBloc>(create: (_) => _FakeGrowth()),
          BlocProvider<CoinsManagerBloc>.value(value: manager),
        ],
        child: Builder(
          builder: (context) {
            updateScreenType(context);
            return WalletHomeView(scrollController: scroll);
          },
        ),
      ),
    ),
    size: const Size(1600, 1024),
  );
}

void _desktopViewCases() {
  testWidgets('Add assets sits in the toolbar, on screen and only once', (
    tester,
  ) async {
    await _pumpDesktopView(tester);

    final add = find.byKey(WalletAddAssetsButton.buttonKey);
    expect(add, findsOneWidget);
    expect(
      find.ancestor(of: add, matching: find.byType(SliverPersistentHeader)),
      findsOneWidget,
    );
    expect(tester.getRect(add).bottom, lessThan(1024));
    expect(
      find.byKey(const Key('coin-list-item-c29'), skipOffstage: false),
      findsNothing,
      reason: 'the foot of the list is not even built',
    );
  });

  testWidgets('a row scrolled into view lands below the pinned toolbar', (
    tester,
  ) async {
    await _pumpDesktopView(tester);

    // The first row built ahead of the viewport but not yet in it, as a row
    // is before a test scrolls it into view and taps it.
    Finder rowAt(int i, {bool onstage = true}) =>
        find.byKey(Key('coin-list-item-c$i'), skipOffstage: onstage);
    final index = List.generate(30, (i) => i).firstWhere(
      (i) =>
          rowAt(i).evaluate().isEmpty &&
          rowAt(i, onstage: false).evaluate().isNotEmpty,
    );
    final row = rowAt(index, onstage: false);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();

    final toolbar = find
        .descendant(
          of: find.byType(SliverPersistentHeader),
          matching: find.byType(ColoredBox),
        )
        .first;
    expect(tester.getRect(toolbar).top, 0, reason: 'the toolbar is pinned');
    expect(
      tester.getRect(row).top,
      greaterThanOrEqualTo(tester.getRect(toolbar).bottom - 0.5),
    );
    // A tap on the row reaches the row, not the toolbar over it.
    expect(
      tester
          .hitTestOnBinding(tester.getCenter(row))
          .path
          .any((entry) => entry.target == tester.renderObject(row)),
      isTrue,
    );
  });
}
