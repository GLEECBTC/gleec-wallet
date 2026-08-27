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

Future<void> testCreateWallet(WidgetTester tester) async {
  print('🔍 CREATE WALLET: Starting wallet creation test');
  
  const String walletName = 'my-wallet-name';
  const String password = 'pppaaasssDDD555444@@@';
  final Finder createWalletButton =
      find.byKey(const Key('create-wallet-button'));
  final Finder nameField = find.byKey(const Key('name-wallet-field'));
  final Finder passwordField = find.byKey(const Key('create-password-field'));
  final Finder passwordConfirmField =
      find.byKey(const Key('create-password-field-confirm'));
  final Finder confirmButton = find.byKey(const Key('confirm-password-button'));
  final Finder authorizedWalletButton =
      find.widgetWithText(AccountSwitcher, walletName);
  final Finder walletsManagerWrapper =
      find.byKey(const Key('wallets-manager-wrapper'));

  print('🔍 CREATE WALLET: Connecting wallet via mobile interface');
  await tapOnMobileConnectWallet(tester, WalletType.iguana);

  // New wallet test
  print('🔍 CREATE WALLET: Verifying and tapping create wallet button');
  expect(createWalletButton, findsOneWidget);
  await tester.tapAndPump(createWalletButton);
  await tester.pumpAndSettle();

  // Wallet creation step
  print('🔍 CREATE WALLET: Starting wallet creation form process');
  expect(find.byKey(const Key('wallet-creation')), findsOneWidget);
  
  print('🔍 CREATE WALLET: Entering wallet details');
  await tester.tapAndPump(nameField);
  await tester.enterText(nameField, walletName);
  await tester.enterText(passwordField, password);
  await tester.enterText(passwordConfirmField, password);
  await tester.pumpNFrames(30);
  
  print('🔍 CREATE WALLET: Accepting terms and conditions');
  
  print('🔍 CREATE WALLET: Confirming wallet creation');
  await tester.tapAndPump(confirmButton);
  await tester.pumpUntilDisappear(walletsManagerWrapper);
  
  if (!isMobile) {
    print('🔍 CREATE WALLET: Verifying wallet creation on desktop');
    expect(authorizedWalletButton, findsOneWidget);
  }
  print('🔍 CREATE WALLET: Wallet creation completed');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Run Wallet Creation tests:',
    (WidgetTester tester) async {
      print('🔍 WALLET TESTS: Starting wallet creation test suite');
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();
      
      print('🔍 WALLET TESTS: Accepting alpha warning');
      await acceptAlphaWarning(tester);
      
      print('🔍 WALLET TESTS: Running wallet creation test');
      await testCreateWallet(tester);
      await tester.pumpAndSettle();

      print('🔍 WALLET TESTS: All wallet creation tests completed');
    },
    semanticsEnabled: false,
  );
}
