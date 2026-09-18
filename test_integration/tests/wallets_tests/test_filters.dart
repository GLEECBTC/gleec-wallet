// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/main.dart' as app;
import 'package:web_dex/views/wallet/coins_manager/coins_manager_list_item.dart';

import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';

Future<void> testFilters(WidgetTester tester) async {
  print('🔍 FILTERS: Starting filters test');

  final Finder walletTab = find.byKey(const Key('main-menu-wallet'));
  final Finder addAssetsButton = find.byKey(const Key('add-assets-button'));
  final coinsManagerList = find.byKey(const Key('coins-manager-list'));
  final Finder filtersButton = find.byKey(const Key('filters-dropdown'));
  final Finder utxoFilterItem = find.byKey(const Key('filter-item-utxo'));
  final Finder erc20FilterItem = find.byKey(const Key('filter-item-erc20'));
  final rows = find.descendant(
    of: coinsManagerList,
    matching: find.byType(CoinsManagerListItem),
  );

  await tester.tap(walletTab);
  print('🔍 FILTERS: Tapped wallet tab');
  await tester.pumpAndSettle();

  await tester.tap(addAssetsButton);
  print('🔍 FILTERS: Tapped add assets button');
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('coins-manager-search-field')),
    '',
  );
  await tester.pumpAndSettle();

  await tester.tap(filtersButton);
  print('🔍 FILTERS: Opened filters dropdown');
  await tester.pumpAndSettle();

  await tester.tap(utxoFilterItem);
  print('🔍 FILTERS: Applied UTXO filter');
  await tester.pumpAndSettle();

  expect(rows, findsWidgets);
  expect(
    tester
        .widgetList<CoinsManagerListItem>(rows)
        .map((row) => row.coin.id.subClass),
    everyElement(CoinSubClass.utxo),
  );
  print('🔍 FILTERS: Verified UTXO filter results');

  await tester.tap(utxoFilterItem);
  print('🔍 FILTERS: Removed UTXO filter');
  await tester.tap(erc20FilterItem);
  print('🔍 FILTERS: Applied ERC20 filter');
  await tester.pumpAndSettle();

  expect(rows, findsWidgets);
  expect(
    tester
        .widgetList<CoinsManagerListItem>(rows)
        .map((row) => row.coin.id.subClass),
    everyElement(CoinSubClass.erc20),
  );
  print('🔍 FILTERS: Verified ERC20 filter results');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run filters tests:', (WidgetTester tester) async {
    print('🔍 MAIN: Starting filters test suite');
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    print('🔍 MAIN: Accepting alpha warning');
    await acceptAlphaWarning(tester);

    await restoreWalletToTest(tester);
    print('🔍 MAIN: Wallet restored');

    await testFilters(tester);
    await tester.pumpAndSettle();

    print('🔍 MAIN: Filters tests completed successfully');
  }, semanticsEnabled: false);
}
