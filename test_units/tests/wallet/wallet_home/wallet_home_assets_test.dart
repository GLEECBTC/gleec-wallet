import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_assets.dart';

import 'wallet_home_fake_wallet.dart';
import 'wallet_home_harness.dart';

void main() {
  setUpAll(initWalletHomeLocalization);
  group('Wallet home assets', _assetCases);
}

FakeWallet _wallet() => FakeWallet([
  (
    id: 'KMD',
    name: 'Komodo',
    subClass: CoinSubClass.smartChain,
    price: 0.25,
    change: 4.67,
    amount: 0,
  ),
  (
    id: 'BTC',
    name: 'Bitcoin',
    subClass: CoinSubClass.utxo,
    price: 60052.95,
    change: -2.17,
    amount: 0.0821,
  ),
  (
    id: 'GLEEC',
    name: 'Gleec',
    subClass: CoinSubClass.grc20,
    price: 0.041,
    change: 5.12,
    amount: 15000,
  ),
]);

Future<List<bool>> _pump(
  WidgetTester tester,
  FakeWallet wallet, {
  String search = '',
  bool hideZero = false,
  bool hideBalances = false,
}) async {
  final toggles = <bool>[];
  await pumpWalletHome(
    tester,
    RepositoryProvider<KomodoDefiSdk>.value(
      value: wallet.sdk,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<CoinsBloc>(create: (_) => FakeWalletCoins(wallet.state)),
          BlocProvider<SettingsBloc>(
            create: (_) => FakeWalletSettings(hideBalances: hideBalances),
          ),
        ],
        child: CustomScrollView(
          slivers: [
            WalletHomeAssets(
              searchPhrase: search,
              hideZeroBalances: hideZero,
              onHideZeroBalances: toggles.add,
            ),
          ],
        ),
      ),
    ),
  );
  return toggles;
}

void _assetCases() {
  late String coinBefore;
  setUp(() => coinBefore = routingState.walletState.selectedCoin);
  tearDown(() => routingState.walletState.selectedCoin = coinBefore);

  testWidgets('lists what is held first, by value', (tester) async {
    await _pump(tester, _wallet());

    double top(String abbr) =>
        tester.getTopLeft(find.byKey(Key('coin-list-item-$abbr'))).dy;
    expect(top('btc'), lessThan(top('gleec')));
    expect(top('gleec'), lessThan(top('kmd')));
    expect(find.text(r'$4,930.35'), findsOneWidget);
    expect(find.text('0.0821 BTC'), findsOneWidget);
    expect(find.text('GRC-20'), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
  });

  testWidgets('hides empty assets and says how many', (tester) async {
    final toggles = await _pump(tester, _wallet(), hideZero: true);

    expect(find.byKey(const Key('coin-list-item-kmd')), findsNothing);
    expect(find.byKey(const Key('coin-list-item-btc')), findsOneWidget);
    expect(find.text('1 asset hidden'), findsOneWidget);

    await tester.tap(find.byKey(const Key('coins-with-balance-checkbox')));
    expect(toggles, [false]);
  });

  testWidgets('filters by search, and says when nothing matches', (
    tester,
  ) async {
    await _pump(tester, _wallet(), search: 'gle');
    expect(find.byKey(const Key('coin-list-item-gleec')), findsOneWidget);
    expect(find.byKey(const Key('coin-list-item-btc')), findsNothing);

    await _pump(tester, _wallet(), search: 'xyz');
    expect(find.text('No assets match search criteria'), findsOneWidget);
  });

  testWidgets('masks holdings but keeps public prices', (tester) async {
    await _pump(tester, _wallet(), hideBalances: true);

    expect(find.textContaining('4,930'), findsNothing);
    expect(find.text('**** BTC'), findsOneWidget);
    expect(find.textContaining(r'$60,052.95', findRichText: true), findsOne);
  });

  testWidgets('opens an asset\'s page from its row', (tester) async {
    await _pump(tester, _wallet());

    await tester.tap(find.byKey(const Key('coin-list-item-gleec')));
    expect(routingState.walletState.selectedCoin, 'GLEEC');
  });

  testWidgets('offers Add assets at the foot of the list', (tester) async {
    await _pump(tester, _wallet());

    expect(find.byKey(const Key('add-assets-button')), findsOneWidget);
  });
}
