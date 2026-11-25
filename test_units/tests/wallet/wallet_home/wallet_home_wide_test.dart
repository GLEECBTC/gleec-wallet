// The analyzer does not treat test_units as tests, so test-only members
// read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_assets_toolbar.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_balance_hero.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_assets.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';

import 'wallet_home_fake_wallet.dart';
import 'wallet_home_harness.dart';

void main() {
  setUpAll(initWalletHomeLocalization);
  group('Wallet home on a wide screen', _wideCases);
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

Future<void> _pumpAssets(WidgetTester tester, {required Size size}) {
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
            ),
          ],
        ),
      ),
    ),
    size: size,
  );
}

Future<List<String>> _pumpToolbar(
  WidgetTester tester, {
  required bool inline,
}) async {
  final phrases = <String>[];
  final controller = TextEditingController();
  final focusNode = FocusNode();
  addTearDown(controller.dispose);
  addTearDown(focusNode.dispose);
  await pumpWalletHome(
    tester,
    CustomScrollView(
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
          ),
        ),
      ],
    ),
    size: _desktop,
  );
  return phrases;
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

  testWidgets('a wide toolbar shows its search field without a tap', (
    tester,
  ) async {
    final phrases = await _pumpToolbar(tester, inline: true);

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
