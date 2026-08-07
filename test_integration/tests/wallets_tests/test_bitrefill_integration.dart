// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/goto.dart' as goto;
import '../../common/pause.dart';
import '../../common/widget_tester_action_extensions.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'wallet_tools.dart';

Future<void> testBitrefillIntegration(WidgetTester tester) async {
  await pause(sec: 2, msg: 'TEST BITREFILL INTEGRATION');

  const String ltcSearchTerm = 'litecoin';

  final Finder totalAmount = find.byKey(
    const Key('overview-total-balance'),
  );
  final Finder ltcActiveCoinItem = find.byKey(
    const Key('coin-list-item-ltc-segwit'),
  );
  final Finder ltcCoinSearchItem = find.byKey(
    const Key('coins-manager-list-item-ltc-segwit'),
  );
  final Finder bitrefillButton = find.byKey(
    const Key('coin-details-bitrefill-button-ltc-segwit'),
  );

  await goto.walletPage(tester);
  expect(totalAmount, findsOneWidget);

  final bool isLtcVisible = await tester.isWidgetVisible(ltcActiveCoinItem);
  if (!isLtcVisible) {
    await addAsset(tester, asset: ltcCoinSearchItem, search: ltcSearchTerm);
    await goto.dexPage(tester);
    await goto.walletPage(tester);
  }

  await tester.pumpAndSettle();
  expect(ltcActiveCoinItem, findsOneWidget);
  await tester.tapAndPump(ltcActiveCoinItem);
  await tester.pumpAndSettle();

  expect(bitrefillButton, findsOneWidget);
  await tester.tapAndPump(bitrefillButton);

  await pause(msg: 'END TEST BITREFILL INTEGRATION');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Run bitrefill integration tests:',
    (WidgetTester tester) async {
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();
      print('ACCEPT ALPHA WARNING');
      await acceptAlphaWarning(tester);
      await restoreWalletToTest(tester);
      await testBitrefillIntegration(tester);
      await tester.pumpAndSettle();

      print('END BITREFILL INTEGRATION TESTS');
    },
    semanticsEnabled: false,
  );
}
