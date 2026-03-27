// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_find_extension.dart';
import '../../common/widget_tester_pump_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'wallet_tools.dart';

Future<void> _activateMarty(WidgetTester tester) async {
  final coinsList = find.byKeyName('wallet-page-scroll-view');
  final martyCoinItem = find.byKeyName('coins-manager-list-item-marty');
  final martyCoinActive = find.byKeyName('active-coin-item-marty');

  await addAsset(tester, asset: martyCoinItem, search: 'marty');
  await tester.pumpUntilVisible(
    martyCoinActive,
    timeout: const Duration(seconds: 30),
    throwOnError: false,
  );
  await tester.dragUntilVisible(
    martyCoinActive,
    coinsList,
    const Offset(0, -50),
  );
  await tester.tapAndPump(martyCoinActive);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('coin details core sections render after opening active coin', (
    tester,
  ) async {
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    await acceptAlphaWarning(tester);
    await restoreWalletToTest(tester);
    await _activateMarty(tester);

    expect(find.byKeyName('coin-details-send-button'), findsOneWidget);
    expect(find.byKeyName('coin-details-receive-button'), findsOneWidget);
    expect(find.byKeyName('coin-details-balance'), findsOneWidget);

    // Core navigation sanity: open send flow and return.
    await tester.tapAndPump(find.byKeyName('coin-details-send-button'));
    expect(find.byKeyName('withdraw-recipient-address-input'), findsOneWidget);
    await tester.tapAndPump(find.byKey(const Key('back-button')));

    // Receive flow can open and return cleanly.
    await tester.tapAndPump(find.byKeyName('coin-details-receive-button'));
    expect(find.byKeyName('coin-details-address-field'), findsOneWidget);
    await tester.tapAndPump(find.byKey(const Key('back-button')));
  });
}
