// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'feedback_tests.dart';
import 'menu_tests.dart';
import 'swap_destinations_test.dart';
import 'theme_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  miscWidgetTests();
}

void miscWidgetTests({
  bool skip = false,
  int retryLimit = 0,
  Duration timeout = const Duration(minutes: 10),
}) {
  return testWidgets(
    'Run misc tests:',
    (WidgetTester tester) async {
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();
      await acceptAlphaWarning(tester);
      await tester.pumpAndSettle();
      await testThemeSwitcher(tester);
      await tester.pumpAndSettle();
      await testFeedbackForm(tester);
      await tester.pumpAndSettle();
      await restoreWalletToTest(tester);
      await testMainMenu(tester);
      await tester.pumpAndSettle();
      await testSwapDestinations(tester);

      print('END MISC TESTS');
    },
    semanticsEnabled: false,
    skip: skip,
    retry: retryLimit,
    timeout: Timeout(timeout),
  );
}
