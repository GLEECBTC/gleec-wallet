// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/report_failure.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'test_activate_coins.dart';
import 'test_cex_prices.dart';
import 'test_coin_assets.dart';
import 'test_filters.dart';
import 'test_withdraw.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  walletsWidgetTests(binding);
}

void walletsWidgetTests(
  IntegrationTestWidgetsFlutterBinding binding, {
  bool skip = false,
}) {
  return testWidgets(
    'Run wallet tests:',
    (WidgetTester tester) async {
      // Each stage reports under its own key so a failure names the phase it
      // came from: the suite is a single test case, and a minified web stack
      // trace cannot distinguish them.
      await reportingFailure(binding, 'startup', () async {
        tester.testTextInput.register();
        await app.main();
        await tester.pumpAndSettle();
        await acceptAlphaWarning(tester);
      });
      await reportingFailure(
        binding,
        'restore_wallet',
        () => restoreWalletToTest(tester),
      );
      await reportingFailure(
        binding,
        'coin_icons',
        () => testCoinIcons(tester),
      );
      await reportingFailure(
        binding,
        'activate_coins',
        () => testActivateCoins(tester),
      );
      await reportingFailure(
        binding,
        'cex_prices',
        () => testCexPrices(tester),
      );
      await reportingFailure(binding, 'withdraw', () => testWithdraw(tester));
      await reportingFailure(binding, 'filters', () => testFilters(tester));

      // Disabled until the bitrefill feature is re-enabled
      // await tester.pumpAndSettle();
      // await testBitrefillIntegration(tester);
    },
    semanticsEnabled: false,
    skip: skip,
  );
}
