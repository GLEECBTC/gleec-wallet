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
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_state.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/blocs/update_bloc.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/widgets/quick_login_switch.dart';
import 'package:web_dex/views/main_layout/main_layout.dart';

import 'swap_wiring_fakes.dart';

/// Signing in lands on Wallet, except when the swap form started it: then
/// the user stays on Swap to finish the swap.
void main() {
  group('Main layout after a sign-in', () {
    late SwapExecutionRegistry registry;
    late FakeSwapServices services;
    late _AuthBloc auth;
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
      registry = SwapExecutionRegistry(
        executors: const [],
        inFlight: () async => const [],
      );
      services = FakeSwapServices(registry);
    });

    tearDown(() async {
      routingState.selectedMenu = previousMenu;
      QuickLoginSwitch.resetOnLogout();
      await registry.dispose();
      Localization.load(const Locale('en'));
    });

    void showSupport() {
      routingState.selectedMenu = MainMenuValue.settings;
      routingState.settingsState.selectedMenu = SettingsMenuValue.support;
    }

    /// The layout on Settings > Support, a page with few needs, signed out.
    Future<void> pumpLayout(WidgetTester tester) async {
      showSupport();
      auth = _AuthBloc();
      final settings = FakeSettingsBloc();
      final trading = FakeTradingStatusBloc();
      final analytics = _Analytics();
      addTearDown(auth.close);
      addTearDown(settings.close);
      addTearDown(trading.close);
      addTearDown(analytics.close);
      await pumpLocalized(
        tester,
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<SettingsBloc>.value(value: settings),
            BlocProvider<TradingStatusBloc>.value(value: trading),
            BlocProvider<AnalyticsBloc>.value(value: analytics),
          ],
          child: RepositoryProvider<SwapServices>.value(
            value: services,
            child: const MainLayout(),
          ),
        ),
      );
    }

    /// Signs in and returns where the layout sent the user, before a frame
    /// draws that page: this test provides nothing Wallet needs.
    Future<MainMenuValue> signIn(WidgetTester tester) async {
      auth.push(AuthBlocState.loggedIn(softwareUser()));
      await tester.idle();
      final menu = routingState.selectedMenu;
      showSupport();
      await tester.pump();
      updateBloc.dispose();
      return menu;
    }

    testWidgets('a sign-in the swap form started stays where it is', (
      tester,
    ) async {
      await pumpLayout(tester);
      services.signInFromSwap = true;

      expect(await signIn(tester), MainMenuValue.settings);
      expect(QuickLoginSwitch.hasBeenLoggedInThisSession, isTrue);
    });

    testWidgets('any other sign-in moves to Wallet', (tester) async {
      await pumpLayout(tester);

      expect(await signIn(tester), MainMenuValue.wallet);
    });
  });
}

/// Sign-in the test sets.
class _AuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _AuthBloc() : super(AuthBlocState.initial());

  void push(AuthBlocState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Analytics that records what it is asked to log.
class _Analytics extends Cubit<AnalyticsState> implements AnalyticsBloc {
  _Analytics() : super(AnalyticsState.initial());

  final List<AnalyticsEvent> events = [];

  @override
  void add(AnalyticsEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
