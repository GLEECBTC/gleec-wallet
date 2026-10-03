// test_units is analysed as app code, where the plugins' test mocks warn.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:easy_localization/easy_localization.dart';
// No public API resets the package's global translations between groups.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/blocs/update_bloc.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/router/navigators/main_layout/main_layout_router.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/main_layout/main_layout.dart';
import 'package:web_dex/views/swap/notices/swap_notices.dart';

import 'swap_test_fixtures.dart';
import 'swap_wiring_fakes.dart';

/// The main layout tells the user about their swaps on every page.
void main() {
  group('Main layout swap notices', () {
    late FakeHandle handle;
    late SwapExecutionRegistry registry;
    late FakeSwapServices services;
    late MainMenuValue previousMenu;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Gleec Wallet',
        packageName: 'com.gleec.wallet',
        version: '0.0.0',
        buildNumber: '0',
        buildSignature: '',
      );
      await EasyLocalization.ensureInitialized();
    });

    setUp(() {
      previousMenu = routingState.selectedMenu;
      handle = FakeHandle(snapshotOf());
      final executor = FakeExecutor(SwapLiquiditySource.routed);
      executor.resumable['swap-1'] = handle;
      registry = SwapExecutionRegistry(
        executors: [executor],
        inFlight: () async => [
          (id: 'swap-1', source: SwapLiquiditySource.routed),
        ],
      );
      services = FakeSwapServices(registry);
    });

    tearDown(() async {
      routingState.selectedMenu = previousMenu;
      await registry.dispose();
      Localization.load(const Locale('en'));
    });

    /// The layout on a phone, showing Settings > Support: a page with nothing
    /// to do with swaps.
    Future<void> pumpLayout(WidgetTester tester) async {
      routingState.selectedMenu = MainMenuValue.settings;
      routingState.settingsState.selectedMenu = SettingsMenuValue.support;
      final auth = FakeAuthBloc(AuthBlocState.loggedIn(softwareUser()));
      final settings = FakeSettingsBloc();
      final trading = FakeTradingStatusBloc();
      addTearDown(auth.close);
      addTearDown(settings.close);
      addTearDown(trading.close);
      await pumpLocalized(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TradingStatusBloc>.value(value: trading),
          ],
          child: RepositoryProvider<SwapServices>.value(
            value: services,
            child: const MainLayout(),
          ),
        ),
      );
    }

    /// The layout checks for app updates once it is up, on a five-minute timer.
    void stopUpdateChecks() => updateBloc.dispose();

    testWidgets('listens for swap notices around every page it routes to', (
      tester,
    ) async {
      await pumpLayout(tester);

      final listener = find.descendant(
        of: find.byKey(scaffoldKey),
        matching: find.byType(SwapNoticeListener),
      );
      expect(listener, findsOneWidget);
      expect(
        find.descendant(of: listener, matching: find.byType(MainLayoutRouter)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: listener,
          matching: find.byKey(const Key('support-page')),
        ),
        findsOneWidget,
      );
      stopUpdateChecks();
    });

    testWidgets('a swap finishing while the user is elsewhere is announced, '
        'with a way back to it', (tester) async {
      await pumpLayout(tester);
      await registry.resumeInFlight();

      handle.push(snapshotOf(outcome: completed()));
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.textContaining('Swap complete: you received'),
        findsOneWidget,
      );
      expect(find.textContaining('3,001'), findsOneWidget);

      await tester.tap(find.text('View'));
      await tester.pump();

      expect(services.requestedOpens, [
        (id: 'swap-1', source: SwapLiquiditySource.routed),
      ]);
      expect(routingState.selectedMenu, MainMenuValue.dex);
      stopUpdateChecks();
    });
  });
}
