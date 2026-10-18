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
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/widgets/need_attention_mark.dart';
import 'package:web_dex/views/common/main_menu/main_menu_desktop.dart';
import 'package:web_dex/views/common/main_menu/main_menu_desktop_item.dart';

import 'swap_wiring_fakes.dart';

/// The Swap entry of the desktop side menu says when a swap needs the user.
void main() {
  group('Desktop menu Swap entry', () {
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

    Future<void> pumpMenu(WidgetTester tester, {KdfUser? user}) async {
      final auth = FakeAuthBloc(AuthBlocState.loggedIn(user ?? softwareUser()));
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
            value: FakeSwapServices(registry),
            child: Scaffold(
              body: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(width: 280, child: MainMenuDesktop()),
              ),
            ),
          ),
        ),
        size: const Size(1440, 900),
      );
    }

    Finder item(MainMenuValue menu) => find.byWidgetPredicate(
      (widget) => widget is DesktopMenuDesktopItem && widget.menu == menu,
    );

    DesktopMenuDesktopItem swapItem(WidgetTester tester) =>
        tester.widget<DesktopMenuDesktopItem>(item(MainMenuValue.dex));

    Color? markColour(WidgetTester tester, MainMenuValue menu) {
      final mark = tester.widget<Container>(
        find.descendant(
          of: find.descendant(
            of: item(menu),
            matching: find.byType(NeedAttentionMark),
          ),
          matching: find.byType(Container),
        ),
      );
      return (mark.decoration! as BoxDecoration).color;
    }

    testWidgets('marks the Swap entry while a followed swap needs the user', (
      tester,
    ) async {
      await registry.resumeInFlight();
      await pumpMenu(tester);

      expect(find.byKey(const Key('main-menu-dex')), findsOneWidget);
      expect(swapItem(tester).needAttention, isTrue);
      expect(markColour(tester, MainMenuValue.dex), theme.custom.warningColor);
      expect(markColour(tester, MainMenuValue.wallet), Colors.transparent);
      expect(markColour(tester, MainMenuValue.fiat), Colors.transparent);
    });

    testWidgets('follows the registry: mark on when needed, off once seen', (
      tester,
    ) async {
      await pumpMenu(tester);
      expect(swapItem(tester).needAttention, isFalse);
      expect(markColour(tester, MainMenuValue.dex), Colors.transparent);

      await registry.resumeInFlight();
      await tester.pump();
      expect(swapItem(tester).needAttention, isTrue);

      registry.acknowledge('swap-1');
      // The registry publishes in a microtask; a zero pump delivers it.
      await tester.pump(Duration.zero);
      expect(swapItem(tester).needAttention, isFalse);
      expect(markColour(tester, MainMenuValue.dex), Colors.transparent);
    });

    testWidgets('keeps the Swap entry off for a hardware wallet', (
      tester,
    ) async {
      routingState.selectedMenu = MainMenuValue.wallet;
      await registry.resumeInFlight();
      await pumpMenu(tester, user: trezorUser());

      expect(swapItem(tester).enabled, isFalse);
      expect(swapItem(tester).needAttention, isTrue);
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

    testWidgets('opens Swap on tap, and shows it selected when it is open', (
      tester,
    ) async {
      routingState.selectedMenu = MainMenuValue.wallet;
      await pumpMenu(tester);
      expect(swapItem(tester).enabled, isTrue);
      expect(swapItem(tester).isSelected, isFalse);

      await tester.tap(find.byKey(const Key('main-menu-dex')));
      expect(routingState.selectedMenu, MainMenuValue.dex);

      await pumpMenu(tester);
      expect(swapItem(tester).isSelected, isTrue);
    });
  });
}
