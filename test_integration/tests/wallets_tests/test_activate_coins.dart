// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/goto.dart' as goto;
import '../../common/pause.dart';
import '../../common/widget_tester_action_extensions.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'wallet_tools.dart';

Future<void> testActivateCoins(WidgetTester tester) async {
  await pause(sec: 2, msg: 'TEST COINS ACTIVATION');

  await pause(sec: 2, msg: '🔍 ACTIVATE COINS: Starting coins activation test');
  const String ethByTicker = 'ETH';
  const String dogeByName = 'gecoi';
  const String kmdBep20ByTicker = 'KMD';

  final Finder totalAmount = find.byKey(const Key('overview-current-value'));
  final Finder ethCoinItem = find.byKey(
    const Key('coins-manager-list-item-eth'),
  );
  final Finder dogeCoinItem = find.byKey(
    const Key('coins-manager-list-item-doge'),
  );
  final Finder kmdBep20CoinItem = find.byKey(
    const Key('coins-manager-list-item-kmd-bep20'),
  );

  await goto.walletPage(tester);
  print('🔍 ACTIVATE COINS: Navigated to wallet page');
  expect(totalAmount, findsOneWidget);

  await _testNoneExistCoin(tester);
  print('🔍 ACTIVATE COINS: Completed non-existent coin test');

  await addAsset(tester, asset: dogeCoinItem, search: dogeByName);
  print('🔍 ACTIVATE COINS: Added DOGE asset');

  await addAsset(tester, asset: kmdBep20CoinItem, search: kmdBep20ByTicker);
  print('🔍 ACTIVATE COINS: Added KMD-BEP20 asset');

  await removeAsset(tester, asset: ethCoinItem, search: ethByTicker);
  print('🔍 ACTIVATE COINS: Removed ETH asset');

  await removeAsset(tester, asset: dogeCoinItem, search: dogeByName);
  print('🔍 ACTIVATE COINS: Removed DOGE asset');

  await removeAsset(tester, asset: kmdBep20CoinItem, search: kmdBep20ByTicker);
  print('🔍 ACTIVATE COINS: Removed KMD-BEP20 asset');

  await goto.dexPage(tester);
  print('🔍 ACTIVATE COINS: Navigated to DEX page');

  await goto.walletPage(tester);
  await pause(msg: 'END TEST COINS ACTIVATION');
  print('🔍 ACTIVATE COINS: Returned to wallet page');
  await pause(msg: '🔍 ACTIVATE COINS: Test completed');
}

// Try to find non-existent coin
Future<void> _testNoneExistCoin(WidgetTester tester) async {
  print('🔍 NON-EXISTENT COIN: Starting test');

  final Finder addAssetsButton = find.byKey(const Key('add-assets-button'));
  final Finder searchCoinsField = find.byKey(
    const Key('coins-manager-search-field'),
  );
  final Finder ethCoinItem = find.byKey(
    const Key('coins-manager-list-item-eth'),
  );

  await goto.walletPage(tester);
  print('🔍 NON-EXISTENT COIN: Navigated to wallet page');

  await tester.tapAndPump(addAssetsButton);
  print('🔍 NON-EXISTENT COIN: Tapped add assets button');
  expect(searchCoinsField, findsOneWidget);

  await enterText(tester, finder: searchCoinsField, text: 'NOSUCHCOINEVER');
  print('🔍 NON-EXISTENT COIN: Searched for non-existent coin');
  expect(ethCoinItem, findsNothing);
  print('🔍 NON-EXISTENT COIN: Verified coin not found');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run coins activation tests:', (WidgetTester tester) async {
    print('🔍 MAIN: Starting coins activation test suite');
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    print('🔍 MAIN: Accepting alpha warning');
    await acceptAlphaWarning(tester);

    await restoreWalletToTest(tester);
    print('🔍 MAIN: Wallet restored');

    await testActivateCoins(tester);
    await tester.pumpAndSettle();

    print('🔍 MAIN: Coins activation tests completed successfully');
  }, semanticsEnabled: false);
}
