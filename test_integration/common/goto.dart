import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/common/screen_type.dart';

import 'widget_tester_action_extensions.dart';
import 'widget_tester_find_extension.dart';
import 'widget_tester_pump_extension.dart';

Future<void> walletPage(WidgetTester tester, {ScreenType? type}) async {
  return await _go('main-menu-wallet', tester);
}

Future<void> dexPage(WidgetTester tester, {ScreenType? type}) async {
  return await _go('main-menu-dex', tester);
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
