// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/main.dart' as app;
import 'package:web_dex/model/settings_menu_value.dart';

import '../../helpers/accept_alpha_warning.dart';

Future<void> testNoLoginWalletAccess(WidgetTester tester) async {
  final Finder walletsManagerWrapper =
      find.byKey(const Key('wallets-manager-wrapper'));

  // App bar
  print('TEST ACCESS FROM APP BAR');
  final Finder connectWalletButton = isMobile
      ? find.byKey(const Key('connect-wallet-dex'))
      : find.byKey(const Key('connect-wallet-header'));
  final Finder appBarTotalBalance =
      find.byKey(const Key('app-bar-total-balance'));
  final Finder appBarAccountButton =
      find.byKey(const Key('app-bar-account-button'));

  expect(connectWalletButton, findsOneWidget);
  await _openWalletManagerPopupByKey(connectWalletButton, tester);
  expect(walletsManagerWrapper, findsOneWidget);
  await _closeWalletManagerPopup(tester);
  expect(walletsManagerWrapper, findsNothing);

  expect(appBarTotalBalance, findsNothing);
  expect(appBarAccountButton, findsNothing);

  // Wallet page
  print('TEST ACCESS FROM WALLET PAGE');
  final Finder walletMenuButton = find.byKey(const Key('main-menu-wallet'));
  final Finder coinsWithBalanceCheckbox =
      find.byKey(const Key('coins-with-balance-checkbox'));
  final Finder addAssetsButton = find.byKey(const Key('add-assets-button'));
  final Finder removeAssetsButton =
      find.byKey(const Key('remove-assets-button'));
  final coinsList = find.byKey(const Key('wallet-page-coins-list'));
  final Finder coinListItemKmd =
      find.byKey(const Key('wallet-coin-list-item-kmd'));

  await tester.tap(walletMenuButton);
  await tester.pumpAndSettle();

  expect(coinsWithBalanceCheckbox, findsNothing);
  expect(addAssetsButton, findsNothing);
  expect(removeAssetsButton, findsNothing);
  await tester.dragUntilVisible(
    coinListItemKmd,
    coinsList,
    const Offset(0, -15),
  );
  await tester.pumpAndSettle();
  await tester.tap(coinListItemKmd);
  await tester.pumpAndSettle();
  expect(walletsManagerWrapper, findsOneWidget);
  await _closeWalletManagerPopup(tester);
  expect(walletsManagerWrapper, findsNothing);

  // Dex page
  print('TEST ACCESS FROM DEX PAGE');
  final Finder connectWalletMakerForm =
      find.byKey(const Key('connect-wallet-maker-form'));
  final Finder connectWalletTakerForm =
      find.byKey(const Key('connect-wallet-taker-form'));
  final Finder dexMenuButton = find.byKey(const Key('main-menu-dex'));
  final Finder makeOrderTab = find.byKey(const Key('make-order-tab'));
  final Finder takeOrderTab = find.byKey(const Key('take-order-tab'));
  final Finder dexPageTabBar = find.byKey(const Key('dex-page-tab-bar'));

  await tester.tap(dexMenuButton);
  await tester.pumpAndSettle();

  expect(dexPageTabBar, findsNothing);
  await tester.tap(takeOrderTab);
  await tester.pumpAndSettle();

  expect(connectWalletTakerForm, findsOneWidget);
  await _openWalletManagerPopupByKey(connectWalletTakerForm, tester);
  expect(walletsManagerWrapper, findsOneWidget);
  await _closeWalletManagerPopup(tester);
  expect(walletsManagerWrapper, findsNothing);

  await tester.tap(makeOrderTab);
  await tester.pumpAndSettle();

  expect(connectWalletMakerForm, findsOneWidget);
  await _openWalletManagerPopupByKey(connectWalletMakerForm, tester);
  expect(walletsManagerWrapper, findsOneWidget);
  await _closeWalletManagerPopup(tester);
  expect(walletsManagerWrapper, findsNothing);

  // Settings page
  print('TEST ACCESS TO SETTINGS PAGE');
  final Finder settingsMenuButton = find.byKey(const Key('main-menu-settings'));
  final Finder settingsMenuItemSecurity = find.byKey(
    Key('settings-menu-item-${SettingsMenuValue.security.toString()}'),
  );
  await tester.tap(settingsMenuButton);
  await tester.pumpAndSettle();
  expect(settingsMenuItemSecurity, findsNothing);
}

Future<void> _openWalletManagerPopupByKey(
    Finder finder, WidgetTester tester) async {
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _closeWalletManagerPopup(WidgetTester tester) async {
  await tester.tapAt(const Offset(10.0, 10.0));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run wallets create tests:', (WidgetTester tester) async {
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();
    print('ACCEPT ALPHA WARNING');
    await acceptAlphaWarning(tester);
    await testNoLoginWalletAccess(tester);
    await tester.pumpAndSettle();
  }, semanticsEnabled: false);
}
