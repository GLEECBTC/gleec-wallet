import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/wallet.dart';

Future<void> tapOnAppBarConnectWallet(
    WidgetTester tester, WalletType walletType) async {
  final Finder connectWallet = find.byKey(const Key('connect-wallet-header'));
  final Finder connectAtomicDexWalletButton =
      find.byKey(Key('wallet-type-list-item-${walletType.name}'));
  await tester.ensureVisible(connectWallet);
  await tester.tap(connectWallet);
  await tester.pumpAndSettle();
  // The wallet-type router screen was merged into the entry screen. A compat
  // no-op target still carries this key, so the tap is harmless where it
  // exists and skipped where it does not.
  if (connectAtomicDexWalletButton.evaluate().isNotEmpty) {
    await tester.tap(connectAtomicDexWalletButton);
    await tester.pumpAndSettle();
  }
}

Future<void> tapOnMobileConnectWallet(
    WidgetTester tester, WalletType walletType) async {
  final mainMenuDexForm = find.byKey(const Key('main-menu-dex'));
  final Finder connectWallet = find.byKey(const Key('connect-wallet-dex'));
  final Finder connectAtomicDexWalletButton =
      find.byKey(Key('wallet-type-list-item-${walletType.name}'));
  await tester.tap(mainMenuDexForm);
  await tester.pumpAndSettle();
  await tester.ensureVisible(connectWallet);
  await tester.tap(connectWallet);
  await tester.pumpAndSettle();
  // The wallet-type router screen was merged into the entry screen. A compat
  // no-op target still carries this key, so the tap is harmless where it
  // exists and skipped where it does not.
  if (connectAtomicDexWalletButton.evaluate().isNotEmpty) {
    await tester.tap(connectAtomicDexWalletButton);
    await tester.pumpAndSettle();
  }
}
