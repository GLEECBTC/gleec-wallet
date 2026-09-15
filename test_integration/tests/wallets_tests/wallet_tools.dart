// ignore_for_file: avoid_print

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../common/goto.dart' as goto;
import '../../helpers/open_coins_manager.dart';
import '../../common/pause.dart';
import '../../common/widget_tester_action_extensions.dart';
import '../../common/widget_tester_pump_extension.dart';

Future<void> removeAsset(
  WidgetTester tester, {
  required Finder asset,
  required String search,
}) async {
  await goto.walletPage(tester);
  // The current manager uses one list for both adding and removing assets.
  await openAddAssetsView(tester);
  final list = find.byKey(const Key('coins-manager-list'));
  final searchField = find.byKey(const Key('coins-manager-search-field'));
  expect(list, findsOneWidget);
  await enterText(tester, finder: searchField, text: search);
  await tester.dragUntilVisible(asset, list, const Offset(0, -50));
  expect(asset, findsOneWidget);
  expect(
    _assetIsSelected(tester, asset),
    isTrue,
    reason: 'The asset must be selected before testing removal',
  );

  await tester.tapAndPump(asset);
  // Parent assets and open orders use the same explicit Disable confirmation
  // as ordinary users. An active-swap refusal must leave the toggle selected
  // and fail the assertion below; this helper never bypasses the trading gate.
  for (var confirmation = 0; confirmation < 2; confirmation++) {
    final dialog = find.byType(AlertDialog);
    if (dialog.evaluate().isEmpty) break;
    final disable = find.descendant(
      of: dialog,
      matching: find.widgetWithText(TextButton, LocaleKeys.disable.tr()),
    );
    expect(disable, findsOneWidget);
    await tester.tapAndPump(disable);
  }

  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (_assetIsSelected(tester, asset) && DateTime.now().isBefore(deadline)) {
    await tester.pumpNFrames(10);
  }
  expect(
    _assetIsSelected(tester, asset),
    isFalse,
    reason: 'Removing the asset must clear its selection toggle',
  );
  await tester.tapAndPump(find.byKey(const Key('back-button')));
}

bool _assetIsSelected(WidgetTester tester, Finder asset) {
  final toggle = find.descendant(of: asset, matching: find.byType(UiSwitcher));
  if (toggle.evaluate().isNotEmpty) {
    expect(toggle, findsOneWidget);
    return tester.widget<UiSwitcher>(toggle).value;
  }
  final checkbox = find.descendant(of: asset, matching: find.byType(Checkbox));
  expect(checkbox, findsOneWidget);
  return tester.widget<Checkbox>(checkbox).value!;
}

Future<void> addAsset(
  WidgetTester tester, {
  required Finder asset,
  required String search,
}) async {
  print('🔍 ADD ASSET: Starting add asset flow');

  final Finder list = find.byKey(const Key('coins-manager-list'));
  final Finder addAssetsButton = find.byKey(const Key('add-assets-button'));
  final Finder searchCoinsField = find.byKey(
    const Key('coins-manager-search-field'),
  );
  final Finder switchButton = find.byKey(const Key('back-button'));

  await goto.walletPage(tester);
  print('🔍 ADD ASSET: Navigated to wallet page');

  try {
    expect(asset, findsNothing);
  } on TestFailure {
    print('🔍 ADD ASSET: Asset already exists, skipping add');
    // asset already created
    return;
  }

  await tester.tap(addAssetsButton);
  await tester.pumpAndSettle(); // wait for page switch and list loading
  print('🔍 ADD ASSET: Tapped add assets button');

  try {
    expect(searchCoinsField, findsOneWidget);
  } on TestFailure {
    print('**Error** addAsset() no searchCoinsField');
  }

  await enterText(tester, finder: searchCoinsField, text: search);
  print('🔍 ADD ASSET: Entered search text: $search');

  await tester.dragUntilVisible(asset, list, const Offset(-250, 0));
  print('🔍 ADD ASSET: Scrolled to make asset visible');
  await tester.tapAndPump(asset);
  print('🔍 ADD ASSET: Tapped on asset');

  try {
    expect(switchButton, findsOneWidget);
  } on TestFailure {
    print('🔍 ADD ASSET: Switch button not found');
    print('**Error** addAsset(): switchButton: $switchButton');
  }

  await tester.tapAndPump(switchButton);
  print('🔍 ADD ASSET: Tapped switch button');
}

Future<bool> filterAsset(
  WidgetTester tester, {
  required Finder asset,
  required Finder assetScrollView,
  required String text,
  required Finder searchField,
}) async {
  print('🔍 FILTER ASSET: Starting filter with text: $text');

  await enterText(tester, finder: searchField, text: text);
  print('🔍 FILTER ASSET: Entered filter text');
  await tester.pumpAndSettle();

  try {
    await tester.dragUntilVisible(asset, assetScrollView, const Offset(0, -50));
    expect(asset, findsOneWidget);
  } on TestFailure {
    print('🔍 FILTER ASSET: Asset not found after filtering');
    await pause(msg: '**Error** filterAsset([$asset, $text])');
    return false;
  }
  print('🔍 FILTER ASSET: Successfully filtered asset');
  return true;
}

Future<void> enterText(
  WidgetTester tester, {
  required Finder finder,
  required String text,
  int frames = 60,
}) async {
  await tester.enterText(finder, text);
  await tester.pumpNFrames(frames);
  await pause();
}
