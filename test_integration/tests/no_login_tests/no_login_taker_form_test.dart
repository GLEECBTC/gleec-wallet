// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/goto.dart' as goto;
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';

Future<void> testNoLoginTakerForm(WidgetTester tester) async {
  print('TEST DOGE SELECTION CRASH');
  const String dogeByName = 'doge';
  final mainMenuDexForm = find.byKey(const Key('main-menu-dex'));
  final takerFormBuySwitcher = find.byKey(const Key('taker-form-buy-switcher'));
  final searchTakerCoinField = find.byKey(const Key('search-field'));
  final tableItemDoge = find.byKey(const Key('orders-table-item-DOGE'));

  await tester.tap(mainMenuDexForm);
  await tester.pumpAndSettle();
  // The taker form is on the Advanced destination of the Swap surface.
  await goto.advancedSwapDestination(tester);
  await tester.tap(takerFormBuySwitcher);
  await tester.pumpAndSettle();
  await tester.tap(searchTakerCoinField);
  await tester.enterText(searchTakerCoinField, dogeByName);
  await tester.pumpAndSettle();
  await tester.tap(tableItemDoge);
  await tester.pumpAndSettle();

  print('DOGE COIN SELECTED, CHECK ORDERBOOK IS LOADED');
  final orderbooksTableContainer =
      find.byKey(const Key('orderbook-asks-bids-container'));
  final mainMenuWallet = find.byKey(const Key('main-menu-wallet'));

  await tester.ensureVisible(orderbooksTableContainer);
  await tester.tap(mainMenuWallet);

  print('TRY TO LOGIN');
  // Ensure wasm module is running in the background
  // We are loggin in, thus this test should be always last one in the group
  await restoreWalletToTest(tester);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run no login taker form tests:', (WidgetTester tester) async {
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();
    print('ACCEPT ALPHA WARNING');
    await acceptAlphaWarning(tester);
    await testNoLoginTakerForm(tester);
    await tester.pumpAndSettle();
  }, semanticsEnabled: false);
}
