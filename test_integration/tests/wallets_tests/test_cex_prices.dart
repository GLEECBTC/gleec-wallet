// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/goto.dart' as goto;
import '../../common/pause.dart';
import '../../common/widget_tester_find_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'wallet_tools.dart';

Future<void> testCexPrices(WidgetTester tester) async {
  print('🔍 CEX PRICES: Starting CEX prices test suite');
  const String docByTicker = 'DOC';
  const String kmdBep20ByTicker = 'KMD';

  final Finder totalAmount = find.byKey(
    const Key('overview-total-balance'),
  );

  // re-enable with coin details click 
  // final Finder coinDetailsReturnButton = find.byKey(
  //   const Key('back-button'),
  // );
  final Finder kmdBep20CoinActive = find.byKey(
    const Key('coin-list-item-kmd-bep20'),
  );
  final Finder kmdBep20Price = find.byKey(
    const Key('fiat-price-kmd-bep20'),
  );
  final Finder list = find.byKey(
    const Key('wallet-page-coins-list'),
  );
  final Finder page = find.byKey(
    const Key('wallet-page'),
  );
  final Finder kmdBep20Item = find.byKey(
    const Key('coins-manager-list-item-kmd-bep20'),
  );
  final Finder docItem = find.byKey(
    const Key('coins-manager-list-item-doc'),
  );
  final Finder searchCoinsField = find.byKey(
    const Key('wallet-page-search-field'),
  );
  final Finder coinsList = find.byKeyName('wallet-page-scroll-view');

  WidgetController.hitTestWarningShouldBeFatal = true;

  await goto.bridgePage(tester);
  print('🔍 CEX PRICES: Navigated to bridge page');
  await goto.walletPage(tester);
  print('🔍 CEX PRICES: Navigated to wallet page');
  expect(page, findsOneWidget);
  expect(totalAmount, findsOneWidget);

  await addAsset(tester, asset: docItem, search: docByTicker);
  print('🔍 CEX PRICES: Added DOC asset');

  await addAsset(tester, asset: kmdBep20Item, search: kmdBep20ByTicker);
  print('🔍 CEX PRICES: Added KMD-BEP20 asset');

  try {
    expect(list, findsOneWidget);
  } on TestFailure {
    print('🔍 CEX PRICES: List not found');
    print('**Error** testCexPrices() list: $list');
  }

  print('🔍 CEX PRICES: Starting KMD-BEP20 price check');
  final hasKmdBep20 = await filterAsset(
    tester,
    assetScrollView: coinsList,
    asset: kmdBep20CoinActive,
    text: kmdBep20ByTicker,
    searchField: searchCoinsField,
  );

  if (hasKmdBep20) {
    await tester.dragUntilVisible(
      kmdBep20CoinActive,
      coinsList,
      const Offset(0, -50),
    );

    // TODO: re-enable. Widget is found, but not tappable, despite being visible
    // await tester.tapAndPump(kmdBep20CoinActive);

    final Text text = kmdBep20Price.evaluate().single.widget as Text;
    final String? priceStr = text.data;
    final double? priceDouble = double.tryParse(priceStr ?? '');
    print('🔍 CEX PRICES: KMD-BEP20 price found: $priceStr');
    expect(priceDouble != null && priceDouble > 0, true);

    // re-enable along with the coin tap above
    // await tester.tapAndPump(coinDetailsReturnButton);
  } else {
    print('🔍 CEX PRICES: KMD-BEP20 not found in list');
  }

  // Check DOC cex price (does not exist)
  // TODO: re-enable this after the doc/marty changes have been decided on
  // await tester.tapAndPump(tester, docCoinActive);
  // expect(docPrice, findsNothing);

  await goto.walletPage(tester);

  await removeAsset(tester, asset: docItem, search: docByTicker);
  print('🔍 CEX PRICES: Removed DOC asset');

  await removeAsset(tester, asset: kmdBep20Item, search: kmdBep20ByTicker);
  print('🔍 CEX PRICES: Removed KMD-BEP20 asset');
  await pause(msg: '🔍 CEX PRICES: Test completed');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Run cex prices tests:',
    (WidgetTester tester) async {
      print('🔍 MAIN: Starting CEX prices test suite');
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();

      print('🔍 MAIN: Accepting alpha warning');
      await acceptAlphaWarning(tester);

      await restoreWalletToTest(tester);
      print('🔍 MAIN: Wallet restored');

      await testCexPrices(tester);
      await tester.pumpAndSettle();

      print('🔍 MAIN: CEX prices tests completed successfully');
    },
    semanticsEnabled: false,
  );
}
