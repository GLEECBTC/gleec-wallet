// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/goto.dart' as goto;
import '../../common/pause.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';

Future<void> testMainMenu(WidgetTester tester) async {
  final Finder general = find.byKey(
    const Key('settings-menu-item-general'),
  );
  final Finder security = find.byKey(
    const Key('settings-menu-item-security'),
  );
  final Finder feedback = find.byKey(
    const Key('settings-menu-item-feedback'),
  );

  await goto.walletPage(tester);
  expect(find.byKey(const Key('wallet-page-coins-list')), findsOneWidget);

  await goto.dexPage(tester);
  expect(find.byKey(const Key('dex-page')), findsOneWidget);

  await goto.nftsPage(tester);
  expect(find.byKey(const Key('nft-page')), findsOneWidget);

  await goto.settingsPage(tester);
  expect(general, findsOneWidget);
  expect(security, findsOneWidget);
  expect(feedback, findsOneWidget);

  // TODO: restore if/when support page is added back to a menu
  // await goto.supportPage(tester);
  // await tester.pumpAndSettle();

  await pause(msg: 'END TEST MENU');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Run menu tests:',
    (WidgetTester tester) async {
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();
      await acceptAlphaWarning(tester);
      print('ACCEPT ALPHA WARNING');
      await restoreWalletToTest(tester);
      await testMainMenu(tester);
      await tester.pumpAndSettle();

      print('END MAIN MENU TESTS');
    },
    semanticsEnabled: false,
  );
}
