// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:integration_test/integration_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/main.dart' as app;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_addresses.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/withdraw_form.dart';

import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_find_extension.dart';
import '../../common/widget_tester_pump_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/get_funded_wif.dart';
import '../../helpers/restore_wallet.dart';
import '../../helpers/verify_platform_clipboard_write.dart';
import 'wallet_tools.dart';
import 'withdraw_diagnostics.dart';

Future<void> testWithdraw(WidgetTester tester) async {
  try {
    print('🔍 WITHDRAW TEST: Starting withdraw test suite');
    final martyCoinItem = await _prepareFundedMarty(tester);

    final recipient = getRandomAddress();
    await _sendAmountToAddress(tester, address: recipient);
    print('🔍 WITHDRAW TEST: Amount sent to address');

    await _confirmSendAmountToAddress(tester, recipient: recipient);
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

/// Exercises only activation, funded balance and receiving an address.
/// This diagnostic path never opens the send form or submits a transaction.
Future<Finder> testWithdrawBalanceAndReceive(WidgetTester tester) async {
  final martyCoinItem = await _prepareFundedMarty(tester);
  await _testCopyAddressButton(tester);
  print('🔍 WITHDRAW TEST: Copy address button test completed');
  return martyCoinItem;
}

Future<Finder> _prepareFundedMarty(WidgetTester tester) async {
  final martyCoinItem = await _activateMarty(tester);
  print('🔍 WITHDRAW TEST: Marty coin activation requested');
  await _assertCoinDetailsCoreSections(tester);
  print('🔍 WITHDRAW TEST: Core coin details sections verified');
  await _waitForFundedMartyBalance(tester);
  return martyCoinItem;
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
  final Finder martyCoinActive = find.byKeyName('coin-list-item-marty');
  final Finder coinBalance = find.byKeyName('coin-details-balance');

  await addAsset(tester, asset: martyCoinItem, search: 'marty');
  print('🔍 ACTIVATE MARTY: Asset added');

  try {
    await tester.pumpUntilVisible(
      martyCoinActive,
      timeout: const Duration(seconds: 30),
    );
  } on TimeoutException {
    await printMartyActivationDiagnostics(tester.element(coinsList));
    rethrow;
  }
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

Future<void> _waitForFundedMartyBalance(WidgetTester tester) async {
  // The balance key also identifies the loading skeleton. Wait for an actual
  // funded value instead of casting that placeholder to AutoScrollText.
  final coinBalance = find.byWidgetPredicate(
    (widget) =>
        widget is AutoScrollText &&
        widget.key == const Key('coin-details-balance'),
  );
  final Finder receiveButton = find.byKey(
    const Key('coin-details-receive-button'),
  );
  await _waitFor(
    tester,
    () =>
        coinBalance.evaluate().length == 1 &&
        (double.tryParse(tester.widget<AutoScrollText>(coinBalance).text) ??
                0) >
            0,
    reason: 'The funded MARTY balance must finish loading before withdrawal',
    onTimeout: () => printMartyBalanceDiagnostics(tester, receiveButton),
  );
}

Future<void> _testCopyAddressButton(WidgetTester tester) async {
  print('🔍 COPY ADDRESS: Starting copy address test');

  final Finder receiveButton = find.byKey(
    const Key('coin-details-receive-button'),
  );
  expect(receiveButton, findsOneWidget);
  await _waitFor(
    tester,
    () => tester.widget<UiPrimaryButton>(receiveButton).onPressed != null,
    reason: 'Receive must become available once the address has loaded',
  );
  await tester.tapAndPump(receiveButton);
  print('🔍 COPY ADDRESS: Tapped receive button');

  // Use the actual address picker and gated receive route. This imported WIF
  // test wallet uses the ordinary test-coin exemption in the product gate.
  final addressChoice = find.textContaining('MARTY available');
  await tester.pumpUntilVisible(addressChoice);
  expect(addressChoice, findsOneWidget);
  await tester.tapAndPump(addressChoice);
  final dialog = find.byType(PubkeyReceiveDialog);
  await tester.pumpUntilVisible(dialog);
  expect(
    tester.widget<PubkeyReceiveDialog>(dialog).address.address,
    isNotEmpty,
  );
  final copyAddressButton = find.descendant(
    of: dialog,
    matching: find.byTooltip(
      LocaleKeys.copyAddressToClipboard.tr(args: ['MARTY']),
    ),
  );
  expect(copyAddressButton, findsOneWidget);
  await tester.ensureVisible(copyAddressButton);
  await verifyPlatformClipboardWrite(
    tester,
    expectedText: tester.widget<PubkeyReceiveDialog>(dialog).address.address,
    copyAction: () => tester.tap(copyAddressButton),
  );
  await tester.pump();
  final successFeedbackObserved = find
      .descendant(
        of: find.byType(SnackBar, skipOffstage: false),
        matching: find.text(
          LocaleKeys.copiedAddressToClipboard.tr(args: ['MARTY']),
          skipOffstage: false,
        ),
      )
      .evaluate()
      .isNotEmpty;
  print(
    'CLIPBOARD RESULT: platformAcknowledged=true; '
    'successFeedbackObserved=$successFeedbackObserved',
  );
  final close = find.descendant(
    of: dialog,
    matching: find.byTooltip(
      MaterialLocalizations.of(tester.element(dialog)).closeButtonTooltip,
    ),
  );
  await tester.tapAndPump(close);
  expect(dialog, findsNothing);
  print('🔍 COPY ADDRESS: Copy address test completed');
}

Future<void> _confirmSendAmountToAddress(
  WidgetTester tester, {
  required String recipient,
}) async {
  print('🔍 CONFIRM SEND: Starting send confirmation');

  final confirmation = find.byType(WithdrawFormConfirmSection);
  await tester.pumpUntilVisible(confirmation);
  final confirmBackButton = find.descendant(
    of: confirmation,
    matching: find.widgetWithText(OutlinedButton, LocaleKeys.back.tr()),
  );
  final confirmAgreeButton = find.descendant(
    of: confirmation,
    matching: find.widgetWithText(FilledButton, LocaleKeys.send.tr()),
  );

  expect(confirmBackButton, findsOneWidget);
  expect(confirmAgreeButton, findsOneWidget);
  expect(tester.widget<FilledButton>(confirmAgreeButton).onPressed, isNotNull);
  await tester.ensureVisible(confirmAgreeButton);
  final reviewed = tester.element(confirmation).read<WithdrawFormBloc>().state;
  expect(reviewed.asset.id.id, 'MARTY');
  expect(reviewed.asset.protocol.isTestnet, isTrue);
  expect(reviewed.amount, '0.01');
  expect(reviewed.isMaxAmount, isFalse);
  expect(reviewed.recipientAddress, recipient);
  expect(reviewed.preview, isNotNull);
  await tester.tapAndPump(confirmAgreeButton);
  print('🔍 CONFIRM SEND: Agreed to confirmation');
  await tester.pumpAndSettle();

  final receipt = find.byType(WithdrawSuccessReceipt);
  await tester.pumpUntilVisible(receipt);
  final receiptWidget = tester.widget<WithdrawSuccessReceipt>(receipt);
  expect(receiptWidget.asset.id.id, 'MARTY');
  expect(receiptWidget.asset.protocol.isTestnet, isTrue);
  final result = receiptWidget.result;
  expect(result.txHash, isNotEmpty);
  print(
    'TESTNET WITHDRAWAL RECEIPT: coin=MARTY; amount=0.01; tx=${result.txHash}',
  );
  final viewOnExplorerButton = find.descendant(
    of: receipt,
    matching: find.widgetWithText(FilledButton, LocaleKeys.viewOnExplorer.tr()),
  );
  final doneButton = find.descendant(
    of: receipt,
    matching: find.widgetWithText(OutlinedButton, LocaleKeys.done.tr()),
  );
  expect(viewOnExplorerButton, findsOneWidget);
  expect(doneButton, findsOneWidget);
  await tester.ensureVisible(doneButton);
  await tester.tapAndPump(doneButton);
  print('🔍 CONFIRM SEND: Tapped done button');
  await tester.pumpAndSettle();

  expect(receipt, findsNothing);
  expect(find.byKeyName('coin-details-send-button'), findsOneWidget);
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
  final addressInput = find.descendant(
    of: find.byType(RecipientAddressField),
    matching: find.byType(TextFormField),
  );
  final amountInput = find.descendant(
    of: find.byType(WithdrawAmountField),
    matching: find.byType(TextFormField),
  );
  final sendEnterButton = find.byType(PreviewWithdrawButton);

  expect(sendButton, findsOneWidget);
  final sdk = tester.element(sendButton).read<KomodoDefiSdk>();
  final asset = sdk.assets.findAssetsByConfigId('MARTY').single;
  expect(asset.protocol.isTestnet, isTrue);
  expect(amount, '0.01');
  await tester.tapAndPump(sendButton);
  print('🔍 SEND AMOUNT: Tapped send button');

  expect(addressInput, findsOneWidget);
  expect(amountInput, findsOneWidget);
  expect(sendEnterButton, findsOneWidget);

  await tester.ensureVisible(addressInput);
  await tester.tapAndPump(addressInput);
  await enterText(tester, finder: addressInput, text: address);
  print('🔍 SEND AMOUNT: Entered address: $address');

  await tester.ensureVisible(amountInput);
  await tester.tapAndPump(amountInput);
  await enterText(tester, finder: amountInput, text: amount);
  print('🔍 SEND AMOUNT: Entered amount: $amount');

  await _waitFor(
    tester,
    () =>
        tester.widget<PreviewWithdrawButton>(sendEnterButton).onPressed != null,
    reason: 'A valid recipient and amount must enable the withdrawal preview',
  );
  await tester.ensureVisible(sendEnterButton);
  await tester.tapAndPump(sendEnterButton);
  print('🔍 SEND AMOUNT: Send process completed');
  await tester.pumpAndSettle();
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() predicate, {
  required String reason,
  Duration timeout = const Duration(seconds: 60),
  Future<void> Function()? onTimeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await tester.pumpNFrames(10);
  }
  final succeeded = predicate();
  if (!succeeded) await onTimeout?.call();
  expect(succeeded, isTrue, reason: reason);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('MARTY testnet withdrawal (0.01)', (WidgetTester tester) async {
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
