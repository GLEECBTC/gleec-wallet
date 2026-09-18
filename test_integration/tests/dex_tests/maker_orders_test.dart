// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/widgets/focusable_widget.dart';
import 'package:web_dex/views/dex/entities_list/orders/order_item.dart';

import '../../common/pause.dart';
import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_find_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import '../wallets_tests/wallet_tools.dart';

Future<void> testMakerOrder(WidgetTester tester) async {
  print('🔍 MAKER ORDER: Starting maker order test');

  const String sellCoin = 'DOC';
  const String sellAmount = '0.012345';
  const String buyCoin = 'MARTY';
  const String buyAmount = '0.023456';

  String? truncatedUuid;

  final Finder dexSectionButton = find.byKey(const Key('main-menu-dex'));
  final Finder makeOrderTab = find.byKey(const Key('make-order-tab'));
  final Finder sellCoinSelectButton =
      find.byKey(const Key('maker-form-sell-switcher'));
  final Finder sellCoinSearchField = find.descendant(
    of: find.byKey(const Key('maker-sell-coins-table')),
    matching: find.byKey(const Key('search-field')),
  );
  final Finder sellCoinItem =
      find.byKey(const Key('Coin-table-item-$sellCoin'));
  final Finder sellAmountField =
      find.byKey(const Key('maker-sell-amount-input'));
  final Finder buyCoinSelectButton =
      find.byKey(const Key('maker-form-buy-switcher'));
  final Finder buyCoinSearchField = find.descendant(
    of: find.byKey(const Key('maker-buy-coins-table')),
    matching: find.byKey(const Key('search-field')),
  );
  final Finder buyCoinItem = find.byKey(const Key('Coin-table-item-$buyCoin'));
  final Finder buyAmountField = find.byKey(const Key('maker-buy-amount-input'));
  final Finder makeOrderButton = find.byKey(const Key('make-order-button'));
  final Finder makeOrderConfirmButton =
      find.byKey(const Key('make-order-confirm-button'));
  final Finder orderListItem = find.byType(OrderItem);
  final Finder orderUuidWidget = find.byKey(const Key('maker-order-uuid'));

  await useFaucetIfBalanceInsufficient(tester);

  // Open maker order form
  await tester.tapAndPump(dexSectionButton);
  print('🔍 MAKER ORDER: Tapped DEX section button');

  await tester.tapAndPump(makeOrderTab);
  print('🔍 MAKER ORDER: Opened make order tab');

  // Select sell coin, enter sell amount
  await tester.tapAndPump(sellCoinSelectButton);
  print('🔍 MAKER ORDER: Opening sell coin selector');

  await enterText(tester, finder: sellCoinSearchField, text: sellCoin);
  print('🔍 MAKER ORDER: Searching for sell coin: $sellCoin');

  await tester.tapAndPump(sellCoinItem);
  print('🔍 MAKER ORDER: Selected sell coin');

  await enterText(tester, finder: sellAmountField, text: sellAmount);
  print('🔍 MAKER ORDER: Entered sell amount: $sellAmount');

  // Select buy coin, enter buy amount
  await tester.tapAndPump(buyCoinSelectButton);
  print('🔍 MAKER ORDER: Opening buy coin selector');

  await enterText(tester, finder: buyCoinSearchField, text: buyCoin);
  print('🔍 MAKER ORDER: Searching for buy coin: $buyCoin');

  await tester.tapAndPump(buyCoinItem);
  print('🔍 MAKER ORDER: Selected buy coin');

  await enterText(tester, finder: buyAmountField, text: buyAmount);
  print('🔍 MAKER ORDER: Entered buy amount: $buyAmount');

  // Create order
  await tester.dragUntilVisible(
    makeOrderButton,
    find.byKey(const Key('maker-form-layout-scroll')),
    const Offset(0, -100),
  );
  print('🔍 MAKER ORDER: Scrolled to make order button');
  await tester.waitForButtonEnabled(
    makeOrderButton,
    // system health check runs on a 30-second timer, so allow for multiple
    // checks until the button is visible
    timeout: const Duration(seconds: 90),
  );
  await tester.tapAndPump(makeOrderButton, nFrames: 90);
  print('🔍 MAKER ORDER: Tapped make order button');

  await tester.dragUntilVisible(
    makeOrderConfirmButton,
    find.byKey(const Key('maker-order-conformation-scroll')),
    const Offset(0, -100),
  );
  print('🔍 MAKER ORDER: Scrolled to confirm button');

  await tester.waitForButtonEnabled(
    makeOrderConfirmButton,
    // system health check runs on a 30-second timer, so allow for multiple
    // checks until the button is visible
    timeout: const Duration(seconds: 90),
  );
  print('🔍 MAKER ORDER: Confirm button is now enabled');
  await tester.tapAndPump(makeOrderConfirmButton);
  // wait for confirm button loader and switch to new page - 30 frames is not
  // always enough, and would rather wait for settle to prevent random failures
  await tester.pumpAndSettle();
  print('🔍 MAKER ORDER: Confirmed order creation');
  await pause(sec: 5);

  // Open order details page
  expect(orderListItem, findsOneWidget);
  await tester.tap(
    find.descendant(
      of: orderListItem,
      matching: find.byType(FocusableWidget),
    ),
  );
  print('🔍 MAKER ORDER: Opened order details');
  await tester.pumpAndSettle();

  // Find order UUID on maker order details page
  expect(orderUuidWidget, findsOneWidget);
  truncatedUuid = (orderUuidWidget.evaluate().single.widget as Text).data;
  print('🔍 MAKER ORDER: Found order UUID: $truncatedUuid');
  expect(truncatedUuid != null, isTrue);
  expect(truncatedUuid?.isNotEmpty, isTrue);
}

Future<void> useFaucetIfBalanceInsufficient(WidgetTester tester) async {
  final walletTab = find.byKeyName('main-menu-wallet');
  final coinsList = find.byKey(const Key('wallet-page-coins-list'));
  final docItem = find.byKeyName('coins-manager-list-item-doc');
  final docCoinActive = find.byKeyName('coin-list-item-doc');
  final docCoinBalance = find.byKeyName('coin-balance-asset-doc');
  final martyItem = find.byKeyName('coins-manager-list-item-marty');
  final martyCoinActive = find.byKeyName('coin-list-item-marty');
  final martyCoinBalance = find.byKeyName('coin-balance-asset-marty');
  final walletPageScrollView = find.byKeyName('wallet-page-scroll-view');
  final faucetButton = find.byKeyName('coin-details-faucet-button');

  await tester.tap(walletTab);
  await tester.pumpAndSettle();

  await addAsset(tester, asset: docItem, search: 'DOC');
  print('🔍 Added doc asset');
  await addAsset(tester, asset: martyItem, search: 'MARTY');
  print('🔍 Added marty asset');

  await tester.dragUntilVisible(
    docCoinActive,
    walletPageScrollView,
    const Offset(0, -50),
  );
  await tester.pumpAndSettle();
  print('🔍 dragged until doc coin item visible');
  final docText = docCoinBalance.evaluate().single.widget as AutoScrollText;
  final String? docBalanceStr = docText.text.split(' ').firstOrNull;
  print('🔍 doc balance str: $docBalanceStr');
  final double? docBalance = double.tryParse(docBalanceStr ?? '');
  print('🔍 doc balance: $docBalance');
  if (docBalance != null && docBalance <= 0.2) {
    await tester.tapAndPump(docCoinActive);
    await tester.pumpAndSettle(); // wait for page and tx history
    print('🔍 navigated to doc coin details page');
    await tester.tap(faucetButton);
    await tester.pumpAndSettle(); // wait for page & loader
    print('🔍 pressed faucet button for doc');
    await pause(sec: 60);
  }

  await tester.tap(walletTab);
  await tester.pumpAndSettle();

  await tester.dragUntilVisible(
    coinsList,
    walletPageScrollView,
    const Offset(0, -50),
  );
  await tester.dragUntilVisible(
    martyCoinActive,
    walletPageScrollView,
    const Offset(0, -50),
  );
  final martyText = martyCoinBalance.evaluate().single.widget as AutoScrollText;
  final String? martyBalanceStr = martyText.text.split(' ').firstOrNull;
  print('🔍 marty balance str: $martyBalanceStr');
  final double? martyBalance = double.tryParse(martyBalanceStr ?? '');
  print('🔍 marty balance: $martyBalance');
  if (martyBalance != null && martyBalance <= 0.2) {
    await tester.tapAndPump(martyCoinActive);
    await tester.pumpAndSettle(); // wait for page and tx history
    print('🔍  navigated to marty coin details page');
    await tester.tap(faucetButton);
    await tester.pumpAndSettle(); // wait for page & loader
    print('🔍 pressed faucet button for marty');
    await pause(sec: 60);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Run maker order tests:',
    (WidgetTester tester) async {
      print('🔍 MAIN: Starting maker order test suite');
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();

      print('🔍 MAIN: Accepting alpha warning');
      await acceptAlphaWarning(tester);

      await restoreWalletToTest(tester);
      print('🔍 MAIN: Wallet restored');
      await tester.pumpAndSettle();

      await testMakerOrder(tester);
      print('🔍 MAIN: Maker order test completed successfully');
    },
    semanticsEnabled: false,
  );
}
