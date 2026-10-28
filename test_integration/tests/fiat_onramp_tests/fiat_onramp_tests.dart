// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/report_failure.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'form_tests.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  fiatOnRampWidgetTests();
  // Accepted release limitation: Ramp credentials are unavailable. Keep its
  // status visible without preventing Banxa from running. The standalone Ramp
  // target can be run when service recovery is ready for verification.
  fiatOnRampWidgetTests(provider: 'Ramp', skip: true);
}

void fiatOnRampWidgetTests({
  String provider = 'Banxa',
  bool submitOrder = false,
  bool skip = false,
  int retryLimit = 0,
  Duration timeout = const Duration(minutes: 10),
}) {
  return testWidgets(
    '$provider on-ramp ${submitOrder ? 'checkout launch' : 'quotes and selection'}'
    '${skip ? ' (deferred)' : ''}',
    (WidgetTester tester) async {
      tester.testTextInput.register();
      await app.main();
      await tester.pumpAndSettle();
      await acceptAlphaWarning(tester);
      await restoreWalletToTest(tester);
      await reportingFailure(
        IntegrationTestWidgetsFlutterBinding.instance,
        '${provider.toLowerCase()}_onramp',
        () => testFiatFormInputs(
          tester,
          provider: provider,
          submitOrder: submitOrder,
        ),
      );

      print('END $provider on-ramp TESTS');
    },
    semanticsEnabled: false,
    skip: skip,
    retry: retryLimit,
    timeout: Timeout(timeout),
  );
}
