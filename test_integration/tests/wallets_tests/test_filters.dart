// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_bloc.dart';
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
  final bloc = tester.element(filtersButton).read<CoinsManagerBloc>();

  await tester.tap(utxoFilterItem);
  print('🔍 FILTERS: Applied UTXO filter');
  await _waitForFilter(tester, bloc, rows, CoinSubClass.utxo);

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
  await _waitForFilter(tester, bloc, rows, null);
  await tester.tap(erc20FilterItem);
  print('🔍 FILTERS: Applied ERC20 filter');
  await _waitForFilter(tester, bloc, rows, CoinSubClass.erc20);

  expect(rows, findsWidgets);
  expect(
    tester
        .widgetList<CoinsManagerListItem>(rows)
        .map((row) => row.coin.id.subClass),
    everyElement(CoinSubClass.erc20),
  );
  print('🔍 FILTERS: Verified ERC20 filter results');
}

Future<void> _waitForFilter(
  WidgetTester tester,
  CoinsManagerBloc bloc,
  Finder rows,
  CoinSubClass? protocol,
) async {
  final expectedSelection = protocol == null ? <CoinSubClass>[] : [protocol];

  bool isReady() {
    final state = bloc.state;
    if (state.selectedCoinTypes.length != expectedSelection.length ||
        !state.selectedCoinTypes.every(expectedSelection.contains)) {
      return false;
    }
    if (protocol == null) return true;
    final rendered = tester.widgetList<CoinsManagerListItem>(rows).toList();
    return state.coins.isNotEmpty &&
        state.coins.every((coin) => coin.id.subClass == protocol) &&
        rendered.isNotEmpty &&
        rendered.every((row) => row.coin.id.subClass == protocol);
  }

  // Selection updates synchronously, but the coin refresh awaits wallet and
  // settings reads. Idle animations can still leave the previous rows visible.
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!isReady() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  final state = bloc.state;
  expect(
    isReady(),
    isTrue,
    reason:
        'Filter ${protocol?.name ?? "cleared"} did not become ready: '
        'selected=${state.selectedCoinTypes.map((type) => type.name).toList()}, '
        'state=${state.coins.map((coin) => coin.id.subClass.name).toSet()}, '
        'rendered=${tester.widgetList<CoinsManagerListItem>(rows).map((row) => row.coin.id.subClass.name).toSet()}',
  );
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
