import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openWalletSection(WidgetTester tester) async {
  await tester.pumpAndSettle();

  final Finder walletMenuItem = find.byKey(const Key('main-menu-wallet'));
  expect(
    walletMenuItem,
    findsOneWidget,
    reason: 'Test error: Wallet main menu item not found',
  );
  await tester.tap(walletMenuItem);
  await tester.pumpAndSettle();

  final Finder totalAmount = find.byKey(const Key('overview-current-value'));
  expect(
    totalAmount,
    findsOneWidget,
    reason:
        'Test error: Wallet main menu item pressed, but no Total balance shown',
  );
}
