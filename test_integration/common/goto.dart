import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/common/screen_type.dart';

import 'widget_tester_action_extensions.dart';
import 'widget_tester_find_extension.dart';
import 'widget_tester_pump_extension.dart';

Future<void> walletPage(WidgetTester tester, {ScreenType? type}) async {
  return await _go('main-menu-wallet', tester);
}

/// Opens the Swap surface on its default destination, the swap form.
Future<void> swapPage(WidgetTester tester, {ScreenType? type}) async {
  return await _go('main-menu-dex', tester);
}

/// Opens the full trading interface.
///
/// The Swap menu entry lands on the swap form, and the shell builds only the
/// selected destination, so the orderbook, the maker form and the bot are not
/// in the tree until Advanced is chosen. Tapping the menu entry alone is no
/// longer enough to reach them.
Future<void> dexPage(WidgetTester tester, {ScreenType? type}) async {
  await _go('main-menu-dex', tester);
  await advancedSwapDestination(tester);
}

/// Switches the Swap surface to the destination that hosts the trading UI.
///
/// Safe to call when Advanced is already selected: tapping the current
/// destination changes nothing. Every layout mounts the Swap shell (the
/// mobile menu router builds it too), so the switcher is always present once
/// the menu entry has been tapped; the lookup stays tolerant only so helpers
/// that run before navigation do not fail here.
Future<void> advancedSwapDestination(WidgetTester tester) =>
    _swapDestination('advanced', tester);

/// Switches the Swap surface back to the swap form.
///
/// Unlike [advancedSwapDestination] this one asserts, because a caller that
/// wants the swap form has nothing to fall back on if the shell is absent.
Future<void> swapFormDestination(WidgetTester tester) =>
    _swapDestination('swap', tester, required: true);

Future<void> _swapDestination(
  String name,
  WidgetTester tester, {
  bool required = false,
}) async {
  final Finder finder = find.byKey(Key('swap-destination-$name'));
  if (finder.evaluate().isEmpty) {
    if (required) {
      expect(
        finder,
        findsOneWidget,
        reason: 'goto.dart _swapDestination($name): no swap shell on screen',
      );
    }
    return;
  }
  await tester.tapAndPump(finder);
  await tester.pumpNFrames(60);
}

Future<void> nftsPage(WidgetTester tester, {ScreenType? type}) async {
  return await _go('main-menu-nft', tester);
}

Future<void> settingsPage(WidgetTester tester, {ScreenType? type}) async {
  await _go('main-menu-settings', tester);
}

Future<void> supportPage(WidgetTester tester, {ScreenType? type}) async {
  return await _go('main-menu-support', tester);
}

Future<void> _go(String key, WidgetTester tester, {int nFrames = 60}) async {
  // ignore: avoid_print
  print('🔍 GOTO: navigating to $key');
  final Finder finder = find.byKeyName(key);
  expect(finder, findsOneWidget, reason: 'goto.dart _go($finder)');
  await tester.tapAndPump(finder);
  await tester.pumpNFrames(nFrames);
  // ignore: avoid_print
  print('🔍 GOTO: finished navigating to $key');
}
