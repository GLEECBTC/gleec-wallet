// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/goto.dart' as goto;
import '../../common/widget_tester_action_extensions.dart';
import '../../helpers/accept_alpha_warning.dart';

Future<void> testThemeSwitcher(WidgetTester tester) async {
  print('🔍 THEME TEST: Starting theme switcher test');

  final themeSwitcherFinder = find.byKey(const Key('theme-switcher'));
  final themeSettingsSwitcherLight = find.byKey(
    const Key('theme-settings-switcher-Light'),
  );
  final themeSettingsSwitcherDark = find.byKey(
    const Key('theme-settings-switcher-Dark'),
  );

  final currentBrightness = Theme.of(tester.element(themeSwitcherFinder))
      .brightness;
  print(
    '🔍 THEME TEST: Initial brightness: $currentBrightness, expected: ${Brightness.dark}',
  );
  expect(
    Theme.of(tester.element(themeSwitcherFinder)).brightness,
    equals(Brightness.dark),
    reason: 'Default theme should be dark theme',
  );
  print('🔍 THEME TEST: Verified default dark theme');

  // await tester.tap(themeSwitcherFinder);
  // await tester.pumpAndSettle();
  // expect(
  //   Theme.of(tester.element(themeSwitcherFinder)).brightness,
  //   equals(Brightness.light),
  //   reason: 'Current theme should be light theme',
  // );

  await goto.settingsPage(tester);
  final settings = tester.element(themeSwitcherFinder).read<SettingsBloc>();

  await tester.tapAndPump(themeSettingsSwitcherDark);
  print('🔍 THEME TEST: Tapped dark theme switcher');
  await _waitForTheme(
    tester,
    settings,
    themeSwitcherFinder,
    ThemeMode.dark,
    Brightness.dark,
  );
  expect(
    Theme.of(tester.element(themeSwitcherFinder)).brightness,
    equals(Brightness.dark),
    reason: 'Current theme should be dark theme',
  );
  print('🔍 THEME TEST: Verified dark theme selection');

  await tester.tapAndPump(themeSettingsSwitcherLight);
  print('🔍 THEME TEST: Tapped light theme switcher');
  await _waitForTheme(
    tester,
    settings,
    themeSwitcherFinder,
    ThemeMode.light,
    Brightness.light,
  );
  expect(
    Theme.of(tester.element(themeSwitcherFinder)).brightness,
    equals(Brightness.light),
    reason: 'Current theme should be light theme',
  );
  print('🔍 THEME TEST: Verified light theme selection');
}

Future<void> _waitForTheme(
  WidgetTester tester,
  SettingsBloc settings,
  Finder themeSwitcher,
  ThemeMode mode,
  Brightness brightness,
) async {
  Brightness? renderedBrightness() {
    final elements = themeSwitcher.evaluate().toList();
    return elements.length == 1 ? Theme.of(elements.single).brightness : null;
  }

  bool isReady() =>
      settings.state.themeMode == mode && renderedBrightness() == brightness;

  // Theme changes await persisted settings before emitting and rebuilding.
  // An idle frame does not prove that either operation has completed.
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!isReady() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(
    isReady(),
    isTrue,
    reason:
        'Theme $mode did not become ready: '
        'selected=${settings.state.themeMode}, '
        'rendered=${renderedBrightness()}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Run design tests:', (WidgetTester tester) async {
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();
    await acceptAlphaWarning(tester);
    print('ACCEPT ALPHA WARNING');
    await tester.pumpAndSettle();
    await testThemeSwitcher(tester);

    print('END THEME SWITCH TESTS');
  }, semanticsEnabled: false);
}
