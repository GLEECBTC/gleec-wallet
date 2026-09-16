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
  const String docByTicker = 'DOC';
  const String kmdBep20ByTicker = 'KMD';

  final Finder totalAmount = find.byKey(const Key('overview-current-value'));

  final Finder kmdBep20CoinActive = find.byKey(
    const Key('coin-list-item-kmd-bep20'),
  );
  final Finder page = find.byKey(const Key('wallet-page'));
  final Finder kmdBep20Item = find.byKey(
    const Key('coins-manager-list-item-kmd-bep20'),
  );
  final Finder docItem = find.byKey(const Key('coins-manager-list-item-doc'));
  final Finder searchCoinsField = find.byKey(
    const Key('wallet-page-search-field'),
  );
  final Finder coinsList = find.byKeyName('wallet-page-scroll-view');

  WidgetController.hitTestWarningShouldBeFatal = true;

  await goto.walletPage(tester);
  print('🔍 CEX PRICES: Navigated to wallet page');
  expect(page, findsOneWidget);
  expect(totalAmount, findsOneWidget);

  await addAsset(tester, asset: docItem, search: docByTicker);
  print('🔍 CEX PRICES: Added DOC asset');

  await addAsset(tester, asset: kmdBep20Item, search: kmdBep20ByTicker);
  print('🔍 CEX PRICES: Added KMD-BEP20 asset');

  expect(coinsList, findsOneWidget);

  print('🔍 CEX PRICES: Starting KMD-BEP20 price check');
  final hasKmdBep20 = await filterAsset(
    tester,
    assetScrollView: coinsList,
    asset: kmdBep20CoinActive,
    text: kmdBep20ByTicker,
    searchField: searchCoinsField,
  );

  expect(
    hasKmdBep20,
    isTrue,
    reason:
        'KMD-BEP20 must reach the wallet list after being added; it did '
        'not appear, so its activation never completed',
  );

  // Prices on the current wallet list use TrendPercentageText. The old
  // fiat-price key belongs to coin details, which this test has not opened.
  final price = find.descendant(
    of: kmdBep20CoinActive,
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
    reason: 'KMD-BEP20 must show an available positive market price',
  );
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: price, matching: find.textContaining(r'$')),
    findsOneWidget,
    reason: 'The market price must be rendered in the wallet row',
  );
  print('🔍 CEX PRICES: KMD-BEP20 wallet row displays a positive USD price');

  await goto.walletPage(tester);

  await removeAsset(tester, asset: docItem, search: docByTicker);
  print('🔍 CEX PRICES: Removed DOC asset');

  await removeAsset(tester, asset: kmdBep20Item, search: kmdBep20ByTicker);
  print('🔍 CEX PRICES: Removed KMD-BEP20 asset');
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
