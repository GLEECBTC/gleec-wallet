// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_find_extension.dart';
import '../../common/widget_tester_pump_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/get_funded_wif.dart';
import '../../helpers/restore_wallet.dart';
import 'wallet_tools.dart';

Future<void> testWithdraw(WidgetTester tester) async {
  try {
    print('🔍 WITHDRAW TEST: Starting withdraw test suite');
    Finder martyCoinItem = await _activateMarty(tester);
    print('🔍 WITHDRAW TEST: Marty coin activated');

    await _assertCoinDetailsCoreSections(tester);
    print('🔍 WITHDRAW TEST: Core coin details sections verified');

    await _testCopyAddressButton(tester);
    print('🔍 WITHDRAW TEST: Copy address button test completed');

    await _sendAmountToAddress(tester, address: getRandomAddress());
    print('🔍 WITHDRAW TEST: Amount sent to address');

    await _confirmSendAmountToAddress(tester);
    print('🔍 WITHDRAW TEST: Send amount confirmed');

    await removeAsset(tester, asset: martyCoinItem, search: 'marty');
    print('🔍 WITHDRAW TEST: Asset removed');

    print('🔍 WITHDRAW TEST: All tests completed successfully');
  } catch (e, s) {
    print('❌ WITHDRAW TEST: Error occurred during testing');
    print(e);
    print(s);
    rethrow;
  }
}

Future<void> _assertCoinDetailsCoreSections(WidgetTester tester) async {
  expect(find.byKeyName('coin-details-balance'), findsOneWidget);
  expect(find.byKeyName('coin-details-send-button'), findsOneWidget);
  expect(find.byKeyName('coin-details-receive-button'), findsOneWidget);

  // Some assets expose faucet; if it exists, at least verify the button can be found.
  final faucetFinder = find.byKeyName('coin-details-faucet-button');
  if (faucetFinder.evaluate().isNotEmpty) {
    expect(faucetFinder, findsWidgets);
  }
}

Future<Finder> _activateMarty(WidgetTester tester) async {
  print('🔍 ACTIVATE MARTY: Starting activation process');

  final Finder coinsList = find.byKeyName('wallet-page-scroll-view');
  final Finder martyCoinItem = find.byKeyName('coins-manager-list-item-marty');
  final Finder martyCoinActive = find.byKeyName('active-coin-item-marty');
  final Finder coinBalance = find.byKeyName('coin-details-balance');

  await addAsset(tester, asset: martyCoinItem, search: 'marty');
  print('🔍 ACTIVATE MARTY: Asset added');

  await tester.pumpUntilVisible(
    martyCoinActive,
    timeout: const Duration(seconds: 30),
    throwOnError: false,
  );
  print('🔍 ACTIVATE MARTY: Waited for coin to become visible');

  await tester.dragUntilVisible(
    martyCoinActive,
    coinsList,
    const Offset(0, -50),
  );
  print('🔍 ACTIVATE MARTY: Scrolled to coin');

  await tester.tapAndPump(martyCoinActive);
  print('🔍 ACTIVATE MARTY: Tapped on coin');

  await tester.pumpAndSettle();
  expect(coinBalance, findsOneWidget);
  print('🔍 ACTIVATE MARTY: Activation completed');
  return martyCoinItem;
}

Future<void> _testCopyAddressButton(WidgetTester tester) async {
  print('🔍 COPY ADDRESS: Starting copy address test');

  final Finder coinBalance = find.byKey(const Key('coin-details-balance'));
  final Finder exitButton = find.byKey(const Key('back-button'));
  final Finder receiveButton = find.byKey(
    const Key('coin-details-receive-button'),
  );
  final Finder copyAddressButton = find.byKey(
    const Key('coin-details-address-field'),
  );

  final AutoScrollText text =
      coinBalance.evaluate().single.widget as AutoScrollText;

  final String priceStr = text.text;
  final double? priceDouble = double.tryParse(priceStr);
  expect(priceDouble != null && priceDouble > 0, true);
  expect(receiveButton, findsOneWidget);
  await tester.tapAndPump(receiveButton);
  print('🔍 COPY ADDRESS: Tapped receive button');

  expect(copyAddressButton, findsOneWidget);
  await tester.tapAndPump(exitButton);
  print('🔍 COPY ADDRESS: Copy address test completed');
}

Future<void> _confirmSendAmountToAddress(WidgetTester tester) async {
  print('🔍 CONFIRM SEND: Starting send confirmation');

  final confirmBackButton = find.byKeyName('confirm-back-button');
  final confirmAgreeButton = find.byKeyName('confirm-agree-button');
  final completeButtons = find.byKeyName('complete-buttons');
  final viewOnExplorerButton = find.byKeyName('send-complete-view-on-explorer');
  final doneButton = find.byKeyName('send-complete-done');
  final exitButton = find.byKeyName('back-button');

  expect(confirmBackButton, findsOneWidget);
  expect(confirmAgreeButton, findsOneWidget);
  await tester.tapAndPump(confirmAgreeButton);
  print('🔍 CONFIRM SEND: Agreed to confirmation');
  await tester.pumpAndSettle();

  expect(completeButtons, findsOneWidget);
  expect(viewOnExplorerButton, findsOneWidget);
  expect(doneButton, findsOneWidget);
  await tester.tapAndPump(doneButton);
  print('🔍 CONFIRM SEND: Tapped done button');
  await tester.pumpAndSettle();

  expect(exitButton, findsOneWidget);
  await tester.tapAndPump(exitButton);
  print('🔍 CONFIRM SEND: Confirmation completed');
  await tester.pumpAndSettle();
}

Future<void> _sendAmountToAddress(
  WidgetTester tester, {
  String amount = '0.01',
  required String address,
}) async {
  print('🔍 SEND AMOUNT: Starting send amount process');

  final sendButton = find.byKeyName('coin-details-send-button');
  final addressInput = find.byKeyName('withdraw-recipient-address-input');
  final amountInput = find.byKeyName('enter-form-amount-input');
  final sendEnterButton = find.byKeyName('send-enter-button');

  expect(sendButton, findsOneWidget);
  await tester.tapAndPump(sendButton);
  print('🔍 SEND AMOUNT: Tapped send button');

  expect(addressInput, findsOneWidget);
  expect(amountInput, findsOneWidget);
  expect(sendEnterButton, findsOneWidget);

  await tester.tapAndPump(addressInput);
  await enterText(tester, finder: addressInput, text: address);
  print('🔍 SEND AMOUNT: Entered address: $address');

  await tester.tapAndPump(amountInput);
  await enterText(tester, finder: amountInput, text: amount);
  print('🔍 SEND AMOUNT: Entered amount: $amount');

  await tester.tapAndPump(sendEnterButton);
  print('🔍 SEND AMOUNT: Send process completed');
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run withdraw tests:', (WidgetTester tester) async {
    print('🔍 MAIN: Starting withdraw test suite');
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    print('🔍 MAIN: Accepting alpha warning');
    await acceptAlphaWarning(tester);

    await restoreWalletToTest(tester);
    print('🔍 MAIN: Wallet restored');

    await testWithdraw(tester);
    await tester.pumpAndSettle();

    print('🔍 MAIN: Withdraw tests completed successfully');
  }, semanticsEnabled: false);
}
