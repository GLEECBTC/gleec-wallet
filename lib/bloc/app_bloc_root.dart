import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;
import 'package:web_dex/analytics/events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/assets_overview/investment_repository.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/bitrefill/bloc/bitrefill_bloc.dart';
import 'package:web_dex/bloc/bridge_form/bridge_bloc.dart';
import 'package:web_dex/bloc/bridge_form/bridge_repository.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/generator.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/mock_transaction_history_repository.dart';
import 'package:web_dex/bloc/cex_market_data/mockup/performance_mode.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_repository.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/price_chart_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/price_chart_event.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_repository.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/coins_manager/coins_manager_bloc.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/faucet_button/faucet_button_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/bloc/nfts/nft_main_repo.dart';
import 'package:web_dex/bloc/platform/platform_bloc.dart';
import 'package:web_dex/bloc/platform/platform_event.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/system_health/system_clock_repository.dart';
import 'package:web_dex/bloc/system_health/system_health_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_repo.dart';
import 'package:web_dex/bloc/version_info/version_info_bloc.dart';
import 'package:web_dex/blocs/kmd_rewards_bloc.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/blocs/orderbook_bloc.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/main.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/router/navigators/app_router_delegate.dart';
import 'package:web_dex/router/navigators/back_dispatcher.dart';
import 'package:web_dex/router/parsers/root_route_parser.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/utils/debug_utils.dart';
import 'package:web_dex/shared/utils/ipfs_gateway_manager.dart';
import 'package:web_dex/shared/utils/utils.dart';

class AppBlocRoot extends StatelessWidget {
  const AppBlocRoot({
    required this.storedPrefs,
    required this.komodoDefiSdk,
    super.key,
  });

  final StoredSettings storedPrefs;
  final KomodoDefiSdk komodoDefiSdk;

  // TODO: Refactor to clean up the bloat in this main file
  Future<void> _clearCachesIfPerformanceModeChanged(
    PerformanceMode? performanceMode,
    ProfitLossRepository profitLossRepo,
    PortfolioGrowthRepository portfolioGrowthRepo,
  ) async {
    final sharedPrefs = await SharedPreferences.getInstance();

    final storedLastPerformanceMode = sharedPrefs.getString(
      'last_performance_mode',
    );

    if (storedLastPerformanceMode != performanceMode?.name) {
      profitLossRepo.clearCache().ignore();
      portfolioGrowthRepo.clearCache().ignore();
    }
    if (performanceMode == null) {
      sharedPrefs.remove('last_performance_mode').ignore();
    } else {
      sharedPrefs
          .setString('last_performance_mode', performanceMode.name)
          .ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final performanceMode = appDemoPerformanceMode;

    final mm2Api = RepositoryProvider.of<Mm2Api>(context);
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final myOrdersService = MyOrdersService(mm2Api);
    final tradingEntitiesBloc = TradingEntitiesBloc(
      komodoDefiSdk,
      mm2Api,
      myOrdersService,
    );
    final dexRepository = DexRepository(mm2Api);

    final transactionsRepo = performanceMode != null
        ? MockTransactionHistoryRepo(
            performanceMode: performanceMode,
            demoDataGenerator: DemoDataCache.withDefaults(komodoDefiSdk),
          )
        : SdkTransactionHistoryRepository(sdk: komodoDefiSdk);

    final profitLossRepo = ProfitLossRepository.withDefaults(
      transactionHistoryRepo: transactionsRepo,
      // Returns real data if performanceMode is null. Consider changing the
      // other repositories to use this pattern.
      demoMode: performanceMode,
      sdk: komodoDefiSdk,
    );

    final portfolioGrowthRepo = PortfolioGrowthRepository.withDefaults(
      transactionHistoryRepo: transactionsRepo,
      demoMode: performanceMode,
      coinsRepository: coinsRepository,
      sdk: komodoDefiSdk,
    );

    _clearCachesIfPerformanceModeChanged(
      performanceMode,
      profitLossRepo,
      portfolioGrowthRepo,
    );

    // startup bloc run steps
    tradingEntitiesBloc.runUpdate();
    routingState.selectedMenu = MainMenuValue.defaultMenu();

    return MultiRepositoryProvider(
      providers: [
        // Keep ipfs gateway manager near root to keep in-memory cache of failing
        // URLS to avoid repeated requests to the same failing URLs.
        RepositoryProvider(
          create: (_) => IpfsGatewayManager(),
          dispose: (manager) => manager.dispose(),
        ),
        RepositoryProvider(
          create: (_) => NftsRepo(api: mm2Api.nft, coinsRepo: coinsRepository),
        ),
        RepositoryProvider(create: (_) => tradingEntitiesBloc),
        RepositoryProvider(create: (_) => dexRepository),
        RepositoryProvider(
          create: (_) => MakerFormBloc(
            api: mm2Api,
            kdfSdk: komodoDefiSdk,
            coinsRepository: coinsRepository,
            dexRepository: dexRepository,
          ),
        ),
        RepositoryProvider(create: (_) => OrderbookBloc(sdk: komodoDefiSdk)),
        RepositoryProvider(create: (_) => myOrdersService),
        RepositoryProvider(
          create: (_) => KmdRewardsBloc(coinsRepository, mm2Api),
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) => CoinsBloc(
              komodoDefiSdk,
              coinsRepository,
              context.read<TradingStatusService>(),
            )..add(CoinsStarted()),
          ),
          BlocProvider<PriceChartBloc>(
            create: (context) => PriceChartBloc(komodoDefiSdk)
              ..add(
                const PriceChartStarted(
                  symbols: ['BTC'],
                  period: Duration(days: 30),
                ),
              ),
          ),
          BlocProvider<AssetOverviewBloc>(
            create: (context) => AssetOverviewBloc(
              profitLossRepo,
              InvestmentRepository(profitLossRepository: profitLossRepo),
              komodoDefiSdk,
            ),
          ),
          BlocProvider<ProfitLossBloc>(
            create: (context) => ProfitLossBloc(profitLossRepo, komodoDefiSdk),
          ),
          BlocProvider<PortfolioGrowthBloc>(
            create: (BuildContext ctx) => PortfolioGrowthBloc(
              portfolioGrowthRepository: portfolioGrowthRepo,
              sdk: komodoDefiSdk,
            ),
          ),
          BlocProvider<SettingsBloc>(
            create: (context) =>
                SettingsBloc(storedPrefs, SettingsRepository()),
          ),
          BlocProvider<AnalyticsBloc>(
            lazy: false,
            create: (context) => AnalyticsBloc(
              analytics: GetIt.I<AnalyticsRepo>(),
              storedData: storedPrefs,
              repository: SettingsRepository(),
            ),
          ),
          BlocProvider<TakerBloc>(
            create: (context) => TakerBloc(
              kdfSdk: komodoDefiSdk,
              dexRepository: dexRepository,
              coinsRepository: coinsRepository,
              analyticsBloc: BlocProvider.of<AnalyticsBloc>(context),
            ),
          ),
          BlocProvider<BridgeBloc>(
            create: (context) => BridgeBloc(
              kdfSdk: komodoDefiSdk,
              dexRepository: dexRepository,
              bridgeRepository: BridgeRepository(
                mm2Api,
                komodoDefiSdk,
                coinsRepository,
              ),
              coinsRepository: coinsRepository,
              analyticsBloc: BlocProvider.of<AnalyticsBloc>(context),
            ),
          ),
          BlocProvider(
            lazy: false,
            create: (context) =>
                NftMainBloc(repo: context.read<NftsRepo>(), sdk: komodoDefiSdk),
          ),
          if (isBitrefillIntegrationEnabled)
            BlocProvider(
              create: (context) =>
                  BitrefillBloc()..add(const BitrefillLoadRequested()),
            ),
          BlocProvider<MarketMakerBotBloc>(
            create: (context) => MarketMakerBotBloc(
              MarketMakerBotRepository(mm2Api, SettingsRepository()),
              MarketMakerBotOrderListRepository(
                myOrdersService,
                SettingsRepository(),
                coinsRepository,
              ),
            ),
          ),
          BlocProvider<TradingStatusBloc>(
            lazy: false,
            create: (context) =>
                TradingStatusBloc(context.read<TradingStatusService>())
                  ..add(TradingStatusWatchStarted()),
          ),
          BlocProvider<SystemHealthBloc>(
            create: (_) =>
                SystemHealthBloc(SystemClockRepository(), mm2Api)
                  ..add(SystemHealthPeriodicCheckStarted()),
          ),
          BlocProvider<CoinsManagerBloc>(
            create: (context) => CoinsManagerBloc(
              coinsRepo: coinsRepository,
              sdk: komodoDefiSdk,
              analyticsBloc: context.read<AnalyticsBloc>(),
              settingsRepository: SettingsRepository(),
              tradingEntitiesBloc: context.read<TradingEntitiesBloc>(),
            ),
          ),
          BlocProvider<FaucetBloc>(
            create: (context) =>
                FaucetBloc(kdfSdk: context.read<KomodoDefiSdk>()),
          ),
          BlocProvider<VersionInfoBloc>(
            lazy: false,
            create: (context) =>
                VersionInfoBloc(mm2Api: mm2Api, komodoDefiSdk: komodoDefiSdk)
                  ..add(const LoadVersionInfo())
                  ..add(const StartPeriodicPolling()),
          ),
          BlocProvider<PlatformBloc>(
            lazy: false,
            create: (context) =>
                PlatformBloc()..add(const PlatformInitRequested()),
          ),
        ],
        child: _MyAppView(),
      ),
    );
  }
}

class _MyAppView extends StatefulWidget {
  @override
  State<_MyAppView> createState() => _MyAppViewState();
}

class _MyAppViewState extends State<_MyAppView> {
  final AppRouterDelegate _routerDelegate = AppRouterDelegate();
  late final RootRouteInformationParser _routeInformationParser;
  late final AirDexBackButtonDispatcher _airDexBackButtonDispatcher;
  late final DateTime _pageLoadStartTime;

  @override
  void initState() {
    _pageLoadStartTime = DateTime.now();
    final coinsBloc = context.read<CoinsBloc>();
    _routeInformationParser = RootRouteInformationParser(coinsBloc);
    _airDexBackButtonDispatcher = AirDexBackButtonDispatcher(_routerDelegate);
    routingState.selectedMenu = MainMenuValue.defaultMenu();

    unawaited(_hideAppLoader());

    // Attempt to restore previously authenticated session
    context.read<AuthBloc>().add(const AuthStateRestoreRequested());

    if (kDebugMode) {
      final walletsRepo = RepositoryProvider.of<WalletsRepository>(context);
      final authBloc = context.read<AuthBloc>();
      initDebugData(authBloc, walletsRepo).ignore();
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      onGenerateTitle: (_) => appTitle,
      themeMode: context.select(
        (SettingsBloc settingsBloc) => settingsBloc.state.themeMode,
      ),
      darkTheme: theme.global.dark,
      theme: theme.global.light,
      routerDelegate: _routerDelegate,
      locale: context.locale,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      routeInformationParser: _routeInformationParser,
      backButtonDispatcher: _airDexBackButtonDispatcher,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (isIconPrecachingEnabled) {
      final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
      _precacheCoinIcons(sdk).ignore();
    }
  }

  /// Hides the native app launch loader. Currently only implemented for web.
  // TODO: Consider using ab abstract class with separate implementations for
  // web and native to avoid web-code in code concerning all platforms.
  Future<void> _hideAppLoader() async {
    if (kIsWeb) {
      html.document.getElementById('main-content')?.style.display = 'block';

      final loadingElement = html.document.getElementById('loading');

      if (loadingElement == null) return;

      // Trigger the zoom out animation.
      loadingElement.classes.add('init_done');

      // Await 200ms so the user can see the animation.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Remove the loading indicator.
      loadingElement.remove();

      final delay = DateTime.now()
          .difference(_pageLoadStartTime)
          .inMilliseconds;
      context.read<AnalyticsBloc>().logEvent(
        PageInteractiveDelayEventData(
          pageName: 'app_root',
          interactiveDelayMs: delay,
          spinnerTimeMs: 200,
        ),
      );
    }
  }

  Completer<void>? _currentPrecacheOperation;

  Future<void> _precacheCoinIcons(KomodoDefiSdk sdk) async {
    if (_currentPrecacheOperation != null &&
        !_currentPrecacheOperation!.isCompleted) {
      // completeError throws an uncaught exception, which causes the UI
      // tests to fail when switching between light and dark theme
      log('New request to precache icons started.');
      _currentPrecacheOperation!.complete();
    }

    _currentPrecacheOperation = Completer<void>();

    try {
      final stopwatch = Stopwatch()..start();
      final availableAssetIds = sdk.assets.available.keys.where(
        (assetId) => !excludedAssetList.contains(assetId.symbol.configSymbol),
      );

      await for (final assetId in Stream.fromIterable(availableAssetIds)) {
        // TODO: Test if necessary to complete prematurely with error if build
        // context is stale. Alternatively, we can check if the context is
        // not mounted and return early with error.
        // ignore: use_build_context_synchronously
        // if (context.findRenderObject() == null) {
        //   _currentPrecacheOperation!.completeError('Build context is stale.');
        //   return;
        // }

        // ignore: use_build_context_synchronously
        await AssetIcon.precacheAssetIcon(
          context,
          assetId,
        ).onError((_, __) => debugPrint('Error precaching coin icon $assetId'));
      }

      _currentPrecacheOperation!.complete();

      if (!mounted) return;
      context.read<AnalyticsBloc>().logEvent(
        CoinsDataUpdatedEventData(
          updateSource: 'remote',
          updateDurationMs: stopwatch.elapsedMilliseconds,
          coinsCount: availableAssetIds.length,
        ),
      );
    } catch (e) {
      log('Error precaching coin icons: $e');
      _currentPrecacheOperation!.completeError(e);
    }
  }
}
