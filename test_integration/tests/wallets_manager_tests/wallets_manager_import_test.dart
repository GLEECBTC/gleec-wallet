// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/main.dart' as app;
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/common/header/actions/account_switcher.dart';

import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_pump_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/connect_wallet.dart';

Future<void> testImportWallet(WidgetTester tester) async {
  const String walletName = 'my-wallet-restored';
  const String password = 'pppaaasssDDD555444@@@';
  const String customSeed = 'my-custom-seed';
  final Finder importWalletButton =
      find.byKey(const Key('import-wallet-button'));

  await tapOnMobileConnectWallet(tester, WalletType.iguana);

  // New wallet test
  expect(importWalletButton, findsOneWidget);
  await tester.tapAndPump(importWalletButton);
  await tester.pumpAndSettle();

  await _createWallet(tester, customSeed: customSeed, walletName: walletName);
  await _enterPassword(tester, walletName: walletName, password: password);
}

Future<void> _enterPassword(
  WidgetTester tester, {
  required String password,
  required String walletName,
}) async {
  final Finder passwordField = find.byKey(const Key('create-password-field'));
  final Finder passwordConfirmField =
      find.byKey(const Key('create-password-field-confirm'));
  final Finder importConfirmButton =
      find.byKey(const Key('confirm-seed-button'));

  final Finder authorizedWalletButton =
      find.widgetWithText(AccountSwitcher, walletName);
  final Finder walletsManagerWrapper =
      find.byKey(const Key('wallets-manager-wrapper'));

  await tester.enterText(passwordField, password);
  await tester.pumpNFrames(10);
  await tester.enterText(passwordConfirmField, password);
  await tester.tapAndPump(importConfirmButton);
  await tester.pumpUntilDisappear(walletsManagerWrapper);
  if (!isMobile) {
    expect(authorizedWalletButton, findsOneWidget);
  }
}

Future<void> _createWallet(
  WidgetTester tester, {
  required String walletName,
  required String customSeed,
}) async {
  final Finder nameField = find.byKey(const Key('name-wallet-field'));
  final Finder importSeedField = find.byKey(const Key('import-seed-field'));
  final Finder allowCustomSeedCheckbox =
      find.byKey(const Key('checkbox-custom-seed'));
  final Finder customSeedDialogInput =
      find.byKey(const Key('custom-seed-dialog-input'));
  final Finder customSeedDialogOkButton =
      find.byKey(const Key('custom-seed-dialog-ok-button'));
  const String confirmCustomSeedText = 'I Understand';
  final Finder importConfirmButton =
      find.byKey(const Key('confirm-seed-button'));

  await tester.tapAndPump(nameField);
  await tester.enterText(nameField, walletName);
  await tester.enterText(importSeedField, customSeed);
  await tester.pumpNFrames(10);
  await tester.tapAndPump(allowCustomSeedCheckbox);
  await tester.enterText(customSeedDialogInput, confirmCustomSeedText);
  await tester.pumpNFrames(10);
  await tester.tapAndPump(customSeedDialogOkButton);
  await tester.tapAndPump(importConfirmButton);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Run Wallet Import tests:',
    (WidgetTester tester) async {
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();
      print('ACCEPT ALPHA WARNING');
      await acceptAlphaWarning(tester);
      await testImportWallet(tester);
      await tester.pumpAndSettle();

      print('END WALLET IMPORT TESTS');
    },
    semanticsEnabled: false,
  );
}
