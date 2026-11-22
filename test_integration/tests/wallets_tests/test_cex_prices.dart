// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/goto.dart' as goto;
import '../../common/pause.dart';
import '../../common/widget_tester_find_extension.dart';
import '../../common/widget_tester_pump_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';
import 'wallet_tools.dart';

Future<void> testCexPrices(WidgetTester tester) async {
  print('🔍 CEX PRICES: Starting CEX prices test suite');

  final Finder totalAmount = find.byKey(const Key('overview-current-value'));
  final Finder page = find.byKey(const Key('wallet-page'));
  final Finder trxRow = find.byKey(const Key('coin-list-item-trx'));
  final Finder searchCoinsField = find.byKey(
    const Key('wallet-page-search-field'),
  );
  final Finder coinsList = find.byKeyName('wallet-page-scroll-view');

  WidgetController.hitTestWarningShouldBeFatal = true;

  await goto.walletPage(tester);
  print('🔍 CEX PRICES: Navigated to wallet page');
  expect(page, findsOneWidget);
  expect(totalAmount, findsOneWidget);
  expect(coinsList, findsOneWidget);

  // TRX is restored by default and has a quote in the Gleec ticker feed.
  // KMD-BEP20 activation is exercised in testActivateCoins.
  final hasTrx = await filterAsset(
    tester,
    assetScrollView: coinsList,
    asset: trxRow,
    text: 'TRX',
    searchField: searchCoinsField,
  );

  expect(hasTrx, isTrue, reason: 'TRX must appear in the restored wallet');

  // Prices on the current wallet list use TrendPercentageText. The old
  // fiat-price key belongs to coin details, which this test has not opened.
  final price = find.descendant(
    of: trxRow,
    matching: find.byType(TrendPercentageText),
  );
  expect(price, findsOneWidget);
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while ((tester.widget<TrendPercentageText>(price).value ?? 0) <= 0 &&
      DateTime.now().isBefore(deadline)) {
    await tester.pumpNFrames(10);
  }
  expect(
    tester.widget<TrendPercentageText>(price).value,
    greaterThan(0),
    reason: 'TRX must show an available positive market price',
  );
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: price, matching: find.textContaining(r'$')),
    findsOneWidget,
    reason: 'The market price must be rendered in the wallet row',
  );
  print('🔍 CEX PRICES: TRX wallet row displays a positive USD price');
  await enterText(tester, finder: searchCoinsField, text: '');
  await pause(msg: '🔍 CEX PRICES: Test completed');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run cex prices tests:', (WidgetTester tester) async {
    print('🔍 MAIN: Starting CEX prices test suite');
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    print('🔍 MAIN: Accepting alpha warning');
    await acceptAlphaWarning(tester);

    await restoreWalletToTest(tester);
    print('🔍 MAIN: Wallet restored');

    await testCexPrices(tester);
    await tester.pumpAndSettle();

    print('🔍 MAIN: CEX prices tests completed successfully');
  }, semanticsEnabled: false);
}
