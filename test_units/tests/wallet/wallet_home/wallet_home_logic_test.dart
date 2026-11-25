import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/asset_display_name.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_assets_toolbar.dart';

import '../../utils/test_util.dart';
import 'wallet_home_harness.dart';

void main() {
  setUpAll(initWalletHomeLocalization);
  group('Wallet home quick action requests', _quickActionRequestCases);
  group('Wallet home asset names', _displayNameCases);
  group('Wallet home toolbar', _toolbarCases);
}

void _quickActionRequestCases() {
  test('a coin page takes its quick action once', () {
    final state = WalletState()
      ..openCoin('BTC', quickAction: CoinQuickAction.send);

    expect(state.selectedCoin, 'BTC');
    final request = state.takeQuickAction('BTC');
    expect(request?.action, CoinQuickAction.send);
    expect(state.takeQuickAction('BTC'), isNull);
  });

  test('another coin page does not take it', () {
    final state = WalletState()
      ..openCoin('BTC', quickAction: CoinQuickAction.receive);

    expect(state.takeQuickAction('ETH'), isNull);
    expect(state.takeQuickAction('BTC'), isNull);
  });

  test('opening a coin without an action clears an old one', () {
    final state = WalletState()
      ..openCoin('BTC', quickAction: CoinQuickAction.send)
      ..reset()
      ..openCoin('BTC');

    expect(state.takeQuickAction('BTC'), isNull);
  });

  test('a request starts its own action, and only the first time', () {
    final request = CoinQuickActionRequest(
      coin: 'BTC',
      action: CoinQuickAction.receive,
    );

    expect(request.start(CoinQuickAction.send), isFalse);
    expect(request.start(CoinQuickAction.receive), isTrue);
    expect(request.start(CoinQuickAction.receive), isFalse);
  });
}

final _eth = AssetId(
  id: 'ETH',
  name: 'Ethereum',
  parentId: null,
  symbol: AssetSymbol(assetConfigId: 'ETH'),
  derivationPath: null,
  chainId: AssetChainId(chainId: 1),
  subClass: CoinSubClass.erc20,
);

Coin _coin(
  String abbr,
  String name,
  CoinSubClass subClass, {
  AssetId? parent,
  bool isTestCoin = false,
}) => setCoin(coinAbbr: abbr).copyWith(
  isTestCoin: isTestCoin,
  id: AssetId(
    id: abbr,
    name: name,
    parentId: parent,
    symbol: AssetSymbol(assetConfigId: abbr),
    derivationPath: null,
    chainId: AssetChainId(chainId: 1),
    subClass: subClass,
  ),
);

void _displayNameCases() {
  test('moves a coin standard out of its name into the chip', () {
    expect(assetDisplayParts(_coin('ETH', 'Ethereum', CoinSubClass.erc20)), (
      name: 'Ethereum',
      network: 'ERC-20',
    ));
    expect(assetDisplayParts(_coin('GLEEC', 'Gleec', CoinSubClass.grc20)), (
      name: 'Gleec',
      network: 'GRC-20',
    ));
  });

  test('tells one token on two chains apart', () {
    final onEthereum = _coin(
      'USDT-ERC20',
      'Tether',
      CoinSubClass.erc20,
      parent: _eth,
    );
    final onTron = _coin('USDT-TRC20', 'Tether', CoinSubClass.trc20);

    expect(assetDisplayParts(onEthereum).network, 'ERC-20');
    expect(assetDisplayParts(onTron).network, 'TRC-20');
    expect(onEthereum.displayName, 'Tether');
  });

  test('gives a chain\'s own coin no chip', () {
    expect(assetDisplayParts(_coin('KMD', 'Komodo', CoinSubClass.smartChain)), (
      name: 'Komodo',
      network: null,
    ));
    expect(assetDisplayParts(_coin('BTC', 'Bitcoin', CoinSubClass.utxo)), (
      name: 'Bitcoin',
      network: null,
    ));
  });

  test('marks a test coin', () {
    expect(
      assetDisplayParts(
        _coin('DOC', 'Doc', CoinSubClass.smartChain, isTestCoin: true),
      ).network,
      'TEST',
    );
  });
}

void _toolbarCases() {
  Future<_Toolbar> pump(
    WidgetTester tester, {
    bool searchOpen = false,
    double textScale = 1,
    WalletHomeSection section = WalletHomeSection.assets,
  }) async {
    final toolbar = _Toolbar();
    await pumpWalletHome(
      tester,
      MediaQuery.withClampedTextScaling(
        minScaleFactor: textScale,
        maxScaleFactor: textScale,
        child: Builder(
          builder: (context) => CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: toolbar.delegate(
                  section: section,
                  searchOpen: searchOpen,
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return toolbar;
  }

  testWidgets('switches section from its pills', (tester) async {
    final toolbar = await pump(tester);

    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('Profit & Loss'), findsOneWidget);
    // On a narrow screen the last pill scrolls into view rather than clip.
    await tester.ensureVisible(find.text('Profit & Loss'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profit & Loss'));
    expect(toolbar.sections, [WalletHomeSection.profitLoss]);
  });

  testWidgets('opens search from Assets only', (tester) async {
    final toolbar = await pump(tester);

    await tester.tap(find.byKey(const Key('wallet-home-search-button')));
    expect(toolbar.searchOpened, 1);

    await pump(tester, section: WalletHomeSection.growth);
    expect(find.byKey(const Key('wallet-home-search-button')), findsNothing);
  });

  testWidgets('searching swaps the row for a field', (tester) async {
    final toolbar = await pump(tester, searchOpen: true);

    expect(find.byKey(const Key('wallet-page-search-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('wallet-page-search-field')),
      'tet',
    );
    expect(toolbar.phrases, ['tet']);
    await tester.tap(find.byKey(const Key('wallet-home-search-close')));
    expect(toolbar.searchClosed, 1);
  });

  testWidgets('fits at double text size without clipping', (tester) async {
    await pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('Profit & Loss'), findsOneWidget);
  });
}

class _Toolbar {
  final sections = <WalletHomeSection>[];
  final phrases = <String>[];
  final controller = TextEditingController();
  final focusNode = FocusNode();
  var searchOpened = 0;
  var searchClosed = 0;

  WalletAssetsToolbarDelegate delegate({
    required WalletHomeSection section,
    required bool searchOpen,
    required TextScaler textScaler,
  }) => WalletAssetsToolbarDelegate(
    section: section,
    onSection: sections.add,
    searchOpen: searchOpen,
    onSearchOpen: () => searchOpened++,
    onSearchClose: () => searchClosed++,
    searchController: controller,
    searchFocusNode: focusNode,
    onSearchChanged: phrases.add,
    textScaler: textScaler,
  );
}
