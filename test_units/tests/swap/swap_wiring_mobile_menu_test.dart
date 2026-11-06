// test_units is analysed as app code, where the plugins' test mocks warn.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
// No public API resets the package's global translations between groups.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/common/main_menu/main_menu_bar_mobile.dart';
import 'package:web_dex/views/common/main_menu/main_menu_bar_mobile_item.dart';

import 'swap_wiring_fakes.dart';

/// The Swap entry of the phone menu bar says when a swap needs the user.
void main() {
  group('Phone menu Swap entry', () {
    late SwapExecutionRegistry registry;
    late MainMenuValue previousMenu;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });

    setUp(() {
      previousMenu = routingState.selectedMenu;
      registry = attentionRegistry();
    });

    tearDown(() async {
      routingState.selectedMenu = previousMenu;
      await registry.dispose();
      Localization.load(const Locale('en'));
    });

    Finder dotOn(MainMenuValue menu) => find.descendant(
      of: find.byKey(Key('main-menu-item-icon-${menu.name}')),
      matching: find.byType(Positioned),
    );

    group('menu bar item', () {
      Future<void> pumpItem(WidgetTester tester, {required bool attention}) =>
          pumpLocalized(
            tester,
            Scaffold(
              body: Center(
                child: SizedBox(
                  width: 80,
                  height: 75,
                  child: MainMenuBarMobileItem(
                    value: MainMenuValue.dex,
                    isActive: false,
                    needAttention: attention,
                  ),
                ),
              ),
            ),
          );

      testWidgets(
        'marks its icon with a small red dot when it needs attention',
        (tester) async {
          await pumpItem(tester, attention: true);

          expect(dotOn(MainMenuValue.dex), findsOneWidget);
          final dot = tester.widget<Positioned>(dotOn(MainMenuValue.dex));
          expect((dot.top, dot.right), (-2.0, -4.0));
          final mark = tester.widget<Container>(
            find.descendant(
              of: dotOn(MainMenuValue.dex),
              matching: find.byType(Container),
            ),
          );
          final decoration = mark.decoration! as BoxDecoration;
          expect(decoration.color, theme.currentGlobal.colorScheme.error);
          expect(decoration.shape, BoxShape.circle);
          expect(
            tester.getSize(
              find.descendant(
                of: dotOn(MainMenuValue.dex),
                matching: find.byType(Container),
              ),
            ),
            const Size(8, 8),
          );
          // It overhangs the icon's corner rather than being cut off by it.
          final stack = tester.widget<Stack>(
            find.ancestor(
              of: dotOn(MainMenuValue.dex),
              matching: find.byType(Stack),
            ),
          );
          expect(stack.clipBehavior, Clip.none);
          expect(
            find.descendant(
              of: find.byWidget(stack),
              matching: find.byType(NavIcon),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets('shows only its icon otherwise', (tester) async {
        await pumpItem(tester, attention: false);

        expect(dotOn(MainMenuValue.dex), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('main-menu-item-icon-dex')),
            matching: find.byType(NavIcon),
          ),
          findsOneWidget,
        );
      });
    });

    group('menu bar', () {
      Future<void> pumpBar(
        WidgetTester tester, {
        KdfUser? user,
        SwapServices? services,
      }) async {
        final auth = FakeAuthBloc(
          AuthBlocState.loggedIn(user ?? softwareUser()),
        );
        final settings = FakeSettingsBloc();
        final trading = FakeTradingStatusBloc();
        addTearDown(auth.close);
        addTearDown(settings.close);
        addTearDown(trading.close);
        final bar = Scaffold(bottomNavigationBar: MainMenuBarMobile());
        await pumpLocalized(
          tester,
          MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<TradingStatusBloc>.value(value: trading),
            ],
            child: RepositoryProvider<SwapServices>.value(
              value: services ?? FakeSwapServices(registry),
              child: bar,
            ),
          ),
        );
      }

      MainMenuBarMobileItem swapItem(WidgetTester tester) =>
          tester.widget<MainMenuBarMobileItem>(
            find.byKey(const Key('main-menu-dex')),
          );

      testWidgets('dots the Swap entry while a followed swap needs the user', (
        tester,
      ) async {
        await registry.resumeInFlight();
        await pumpBar(tester);

        expect(swapItem(tester).needAttention, isTrue);
        expect(dotOn(MainMenuValue.dex), findsOneWidget);
        for (final other in [
          MainMenuValue.wallet,
          MainMenuValue.fiat,
          MainMenuValue.settings,
        ]) {
          expect(dotOn(other), findsNothing, reason: other.name);
        }
      });

      testWidgets('follows the registry: dot on when needed, off once seen', (
        tester,
      ) async {
        await pumpBar(tester);
        expect(dotOn(MainMenuValue.dex), findsNothing);

        await registry.resumeInFlight();
        await tester.pump();
        expect(dotOn(MainMenuValue.dex), findsOneWidget);

        registry.acknowledge('swap-1');
        // The registry publishes in a microtask; a zero pump delivers it.
        await tester.pump(Duration.zero);
        expect(swapItem(tester).needAttention, isFalse);
        expect(dotOn(MainMenuValue.dex), findsNothing);
      });

      testWidgets('keeps the Swap entry off for a hardware wallet', (
        tester,
      ) async {
        routingState.selectedMenu = MainMenuValue.wallet;
        await registry.resumeInFlight();
        await pumpBar(tester, user: trezorUser());

        final item = swapItem(tester);
        expect(item.enabled, isFalse);
        // A swap needing attention is still worth marking.
        expect(item.needAttention, isTrue);
        final opacity = tester.widget<Opacity>(
          find.descendant(
            of: find.byKey(const Key('main-menu-dex')),
            matching: find.byType(Opacity),
          ),
        );
        expect(opacity.opacity, 0.5);
        expect(
          tester
              .widget<Tooltip>(
                find
                    .ancestor(
                      of: find.byKey(const Key('main-menu-dex')),
                      matching: find.byType(Tooltip),
                    )
                    .first,
              )
              .message,
          LocaleKeys.trezorWalletOnlyTooltip.tr(),
        );

        await tester.tap(find.byKey(const Key('main-menu-dex')));
        expect(routingState.selectedMenu, MainMenuValue.wallet);
      });

      testWidgets('opens Swap on tap, and shows it active when selected', (
        tester,
      ) async {
        routingState.selectedMenu = MainMenuValue.wallet;
        await pumpBar(tester);
        expect(swapItem(tester).isActive, isFalse);
        expect(swapItem(tester).enabled, isTrue);

        await tester.tap(find.byKey(const Key('main-menu-dex')));
        expect(routingState.selectedMenu, MainMenuValue.dex);

        await pumpBar(tester);
        expect(swapItem(tester).isActive, isTrue);
      });
    });
  });
}
