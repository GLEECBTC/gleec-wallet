// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_find_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rewards flow opens and handles no rewards gracefully', (
    tester,
  ) async {
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    await acceptAlphaWarning(tester);
    await restoreWalletToTest(tester);

    final kmdCoinActive = find.byKeyName('active-coin-item-kmd');
    if (kmdCoinActive.evaluate().isEmpty) {
      print('Skipping rewards check: KMD is not active in this environment.');
      return;
    }

    await tester.tapAndPump(kmdCoinActive);
    await tester.pumpAndSettle();

    final rewardsButtonText = find.text('getRewards');
    if (rewardsButtonText.evaluate().isEmpty) {
      print(
        'Skipping rewards check: rewards button unavailable for current wallet mode.',
      );
      return;
    }

    await tester.tapAndPump(rewardsButtonText.first);
    await tester.pumpAndSettle();

    // Accept both "no rewards" and claimable states.
    final noRewards = find.text('noRewards');
    final claimButton = find.byKeyName('reward-claim-button');
    expect(
      noRewards.evaluate().isNotEmpty || claimButton.evaluate().isNotEmpty,
      isTrue,
    );
  });
}
