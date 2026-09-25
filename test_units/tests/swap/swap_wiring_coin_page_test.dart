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
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_repository.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_info.dart';

import 'swap_wiring_coin_fakes.dart';
import 'swap_wiring_fakes.dart';

/// A coin page's Swap button opens the Swap form paying with that coin.
void main() {
  group('Coin page Swap button', () {
    late SwapExecutionRegistry registry;
    late FakeSwapServices services;
    late RecordingTakerBloc taker;
    late MainMenuValue previousMenu;

    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });

    setUp(() {
      previousMenu = routingState.selectedMenu;
      registry = SwapExecutionRegistry(
        executors: const [],
        inFlight: () async => const [],
      );
      services = FakeSwapServices(registry);
      taker = RecordingTakerBloc();
    });

    tearDown(() async {
      routingState.selectedMenu = previousMenu;
      await registry.dispose();
      Localization.load(const Locale('en'));
    });

    // A test-network coin: its page's charts settle as unsupported at once.
    final coin = docAsset.toCoin().copyWith(state: CoinState.active);

    Future<void> pumpCoinPage(WidgetTester tester, Size size) async {
      final user = softwareUser();
      final auth = FakeAuthBloc(AuthBlocState.loggedIn(user));
      final settings = FakeSettingsBloc();
      final trading = FakeTradingStatusBloc();
      final coins = FakeCoinsBloc();
      final history = FakeTransactionHistoryBloc();
      for (final bloc in [auth, settings, trading, coins, history]) {
        addTearDown(bloc.close);
      }
      await pumpLocalized(
        tester,
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<KomodoDefiSdk>.value(value: CoinPageSdk(user)),
            RepositoryProvider<AnalyticsBloc>.value(value: SilentAnalytics()),
            RepositoryProvider<PortfolioGrowthRepository>.value(
              value: NoGrowthCharts(),
            ),
            RepositoryProvider<ProfitLossRepository>.value(
              value: NoProfitLoss(),
            ),
            RepositoryProvider<SwapServices>.value(value: services),
            RepositoryProvider<TakerBloc>.value(value: taker),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<SettingsBloc>.value(value: settings),
              BlocProvider<TradingStatusBloc>.value(value: trading),
              BlocProvider<CoinsBloc>.value(value: coins),
              BlocProvider<TransactionHistoryBloc>.value(value: history),
            ],
            child: Scaffold(
              body: CoinDetailsInfo(
                coin: coin,
                setPageType: (_) {},
                onBackButtonPressed: () {},
              ),
            ),
          ),
        ),
        size: size,
        theme: theme.global.light,
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    for (final (layout, size) in const [
      ('desktop', Size(1440, 1000)),
      ('phone', Size(390, 1400)),
    ]) {
      testWidgets('on $layout, Swap opens the swap form paying with the coin', (
        tester,
      ) async {
        routingState.selectedMenu = MainMenuValue.wallet;
        await pumpCoinPage(tester, size);

        await tester.tap(find.byKey(const Key('coin-details-swap-button')));
        await tester.pump();

        expect(services.requestedIntents, [
          (pay: 'DOC', receive: null, amount: null),
        ]);
        // Advanced's taker form is seeded too.
        expect(taker.events.single, isA<TakerSetSellCoin>());
        expect((taker.events.single as TakerSetSellCoin).coin, coin);
        expect(routingState.selectedMenu, MainMenuValue.dex);
      });
    }
  });
}
