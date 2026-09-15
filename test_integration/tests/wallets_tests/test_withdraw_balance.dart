import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'test_withdraw.dart' show testWithdrawBalanceAndReceive;

/// Safe diagnosis of withdrawal prerequisites; does not submit a transaction.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('MARTY balance and receive prerequisites', (tester) async {
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();
    await acceptAlphaWarning(tester);
    await restoreWalletToTest(tester);
    await testWithdrawBalanceAndReceive(tester);
  }, semanticsEnabled: false);
}
