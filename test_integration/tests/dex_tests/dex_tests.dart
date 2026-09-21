// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/report_failure.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'maker_orders_test.dart';
import 'taker_orders_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  dexWidgetTests(binding);
}

void dexWidgetTests(
  IntegrationTestWidgetsFlutterBinding binding, {
  bool skip = false,
  int retryLimit = 0,
  Duration timeout = const Duration(minutes: 30),
}) {
  return testWidgets(
    'Run DEX tests:',
    (WidgetTester tester) async {
      // Report per stage: this suite is one test case, and a minified web
      // stack trace cannot say which half of it broke.
      await reportingFailure(binding, 'dex_startup', () async {
        tester.testTextInput.register();
        await app.main();
        await tester.pumpAndSettle();
        await acceptAlphaWarning(tester);
        await restoreWalletToTest(tester);
        await tester.pumpAndSettle();
      });
      await reportingFailure(binding, 'maker_order', () async {
        await testMakerOrder(tester);
        await tester.pumpAndSettle();
      });
      await reportingFailure(
        binding,
        'taker_order',
        () => testTakerOrder(tester),
      );

      print('END DEX TESTS');
    },
    semanticsEnabled: false,
    skip: skip,
    retry: retryLimit,
    timeout: Timeout(timeout),
  );
}
