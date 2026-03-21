import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/analytics/events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/assets_overview/bloc/asset_overview_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/bridge_form/bridge_bloc.dart';
import 'package:web_dex/bloc/bridge_form/bridge_event.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/price_chart_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/price_chart_event.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/dispatchers/popup_dispatcher.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/wallet_state.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart';
import 'package:web_dex/views/wallet/wallet_page/charts/coin_prices_chart.dart';
import 'package:web_dex/views/wallet/wallet_page/common/assets_list.dart';
import 'package:web_dex/views/wallet/wallet_page/common/zhtlc/zhtlc_configuration_handler.dart'
    show ZhtlcConfigurationHandler;
import 'package:web_dex/views/wallet/wallet_page/wallet_main/active_coins_list.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/wallet_manage_section.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/wallet_overview.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';

class WalletMain extends StatefulWidget {
  const WalletMain({super.key = const Key('wallet-page')});

  @override
  State<WalletMain> createState() => _WalletMainState();
}

class _WalletMainState extends State<WalletMain> with TickerProviderStateMixin {
  final ValueNotifier<String> _searchPhraseNotifier = ValueNotifier<String>('');
  PopupDispatcher? _popupDispatcher;
  StreamSubscription<Wallet?>? _walletSubscription;
  late TabController _tabController;
  int _activeTabIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late final Stopwatch _walletListStopwatch;
  bool _walletHalfLogged = false;

  void _initTabController(bool authenticated) {
    _tabController = TabController(length: authenticated ? 3 : 2, vsync: this)
      ..addListener(() {
        if (_activeTabIndex != _tabController.index) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() => _activeTabIndex = _tabController.index);
          });
        }
      });
  }

  void _updateTabController(bool authenticated) {
    final newLength = authenticated ? 3 : 2;
    if (_tabController.length != newLength) {
      _tabController.dispose();
      _initTabController(authenticated);
    }
  }

  @override
  void initState() {
    super.initState();

    _walletListStopwatch = Stopwatch()..start();
    _scrollController.addListener(_onScroll);

    final authBloc = context.read<AuthBloc>();
    if (authBloc.state.currentUser != null) {
      _loadWalletData(authBloc.state.currentUser!.wallet.id).ignore();
    }

    _initTabController(authBloc.state.currentUser != null);
  }

  @override
  void dispose() {
    _walletSubscription?.cancel();
    _popupDispatcher?.close();
    _popupDispatcher = null;
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchPhraseNotifier.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthBloc, AuthBlocState>(
      // This should only load / refresh wallet data if the user changes
      listenWhen: (previous, current) =>
          previous.currentUser != current.currentUser,
      listener: (context, state) {
        if (state.currentUser?.wallet != null) {
          _loadWalletData(state.currentUser!.wallet.id).ignore();
          _updateTabController(true);
        } else {
          _clearWalletData();
          _updateTabController(false);
        }
      },
      builder: (authContext, authState) {
        final authStateMode = authState.currentUser == null
            ? AuthorizeMode.noLogin
            : AuthorizeMode.logIn;
        final isLoggedIn = authStateMode == AuthorizeMode.logIn;
        final walletType = authState.currentUser?.wallet.config.type;
        final showMultiAddressNotice =
            isLoggedIn && walletType == WalletType.hdwallet;

        return ZhtlcConfigurationHandler(
          child: PageLayout(
            noBackground: true,
            header: (isMobile && !isLoggedIn)
                ? PageHeader(title: LocaleKeys.wallet.tr())
                : null,
            padding: EdgeInsets.zero,
            // Removed page padding here
            content: Expanded(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: _onPointerSignal,
                child: DexScrollbar(
                  scrollController: _scrollController,
                  isMobile: isMobile,
                  child: CustomScrollView(
                    key: const Key('wallet-page-scroll-view'),
                    controller: _scrollController,
                    slivers: [
                      // Add a SizedBox at the top of the sliver list for spacing
                      if (isLoggedIn) ...[
                        if (!isMobile)
                          const SliverToBoxAdapter(child: SizedBox(height: 32)),
                        SliverToBoxAdapter(
                          child: WalletOverview(
                            key: const Key('wallet-overview'),
                            onPortfolioGrowthPressed: () =>
                                _tabController.animateTo(1),
                            onPortfolioProfitLossPressed: () =>
                                _tabController.animateTo(2),
                            onAssetsPressed: () => _tabController.animateTo(0),
                          ),
                        ),
                        const SliverToBoxAdapter(child: Gap(24)),
                        if (showMultiAddressNotice) ...[
                          const SliverToBoxAdapter(
                            child: _MultiAddressWalletNotice(),
                          ),
                          const SliverToBoxAdapter(child: Gap(16)),
                        ],
                      ],
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _SliverTabBarDelegate(
                          TabBar(
                            controller: _tabController,
                            tabs: [
                              Tab(text: LocaleKeys.assets.tr()),
                              if (isLoggedIn)
                                Tab(text: LocaleKeys.portfolioGrowth.tr())
                              else
                                Tab(text: LocaleKeys.statistics.tr()),
                              if (isLoggedIn)
                                Tab(text: LocaleKeys.profitAndLoss.tr()),
                            ],
                          ),
                        ),
                      ),
                      if (!isMobile) SliverToBoxAdapter(child: Gap(24)),
                      ..._buildTabSlivers(authStateMode),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadWalletData(String walletId) async {
    final portfolioGrowthBloc = context.read<PortfolioGrowthBloc>();
    final profitLossBloc = context.read<ProfitLossBloc>();
    final assetOverviewBloc = context.read<AssetOverviewBloc>();
    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);

    // Use the historical (previously activated) wallet coins here, as the
    // [CoinsBloc] state might not be updated yet if the user signs in on this
    // page. Having this function refresh on [CoinsBloc] state changes is not
    // ideal, as it would spam API requests each time a coin is activated, or
    // balance updated.
    // TODO: update to event-based approach based on soon-to-be-implemented
    // balance events from the SDK
    final walletCoins = await sdk.getWalletCoins();

    portfolioGrowthBloc.add(
      PortfolioGrowthLoadRequested(
        coins: walletCoins,
        fiatCoinId: 'USDT',
        selectedPeriod: portfolioGrowthBloc.state.selectedPeriod,
        walletId: walletId,
      ),
    );

    profitLossBloc.add(
      ProfitLossPortfolioChartLoadRequested(
        coins: walletCoins,
        selectedPeriod: profitLossBloc.state.selectedPeriod,
        fiatCoinId: 'USDT',
        walletId: walletId,
      ),
    );

    // Subscribe fires an immediate load event, so no need to also call load
    assetOverviewBloc.add(
      PortfolioAssetsOverviewSubscriptionRequested(
        coins: walletCoins,
        walletId: walletId,
        updateFrequency: const Duration(minutes: 1),
      ),
    );
  }

  void _clearWalletData() {
    final portfolioGrowthBloc = context.read<PortfolioGrowthBloc>();
    final profitLossBloc = context.read<ProfitLossBloc>();
    final assetOverviewBloc = context.read<AssetOverviewBloc>();

    portfolioGrowthBloc.add(const PortfolioGrowthClearRequested());
    profitLossBloc.add(const ProfitLossPortfolioChartClearRequested());
    assetOverviewBloc.add(const AssetOverviewClearRequested());
  }

  void _onShowCoinsWithBalanceClick(bool value) {
    context.read<SettingsBloc>().add(
      HideZeroBalanceAssetsChanged(hideZeroBalanceAssets: value),
    );
  }

  void _onSearchChange(String searchKey) {
    final normalizedSearchKey = searchKey.toLowerCase();
    if (_searchPhraseNotifier.value == normalizedSearchKey) {
      return;
    }

    _searchPhraseNotifier.value = normalizedSearchKey;
  }

  void _onActiveCoinItemTap(Coin coin) {
    routingState.walletState.selectedCoin = coin.abbr;
    routingState.walletState.action = coinsManagerRouteAction.none;
  }

  void _onAssetItemTap(Coin coin) {
    _popupDispatcher = _createPopupDispatcher();
    _popupDispatcher!.show();
  }

  void _onAssetStatisticsTap(AssetId assetId, Duration period) {
    context.read<PriceChartBloc>().add(
      PriceChartStarted(symbols: [assetId.symbol.configSymbol], period: period),
    );
    _tabController.animateTo(1);
  }

  List<Widget> _buildTabSlivers(AuthorizeMode mode) {
    switch (_activeTabIndex) {
      case 0:
        return [
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverSearchBarDelegate(
              searchController: _searchController,
              searchFocusNode: _searchFocusNode,
              withBalance: context
                  .watch<SettingsBloc>()
                  .state
                  .hideZeroBalanceAssets,
              onSearchChange: _onSearchChange,
              onWithBalanceChange: _onShowCoinsWithBalanceClick,
              mode: mode,
            ),
          ),
          if (!isMobile) const SliverToBoxAdapter(child: SizedBox(height: 22)),
          ValueListenableBuilder<String>(
            valueListenable: _searchPhraseNotifier,
            builder: (context, searchPhrase, child) {
              return CoinListView(
                mode: mode,
                searchPhrase: searchPhrase,
                withBalance: context
                    .watch<SettingsBloc>()
                    .state
                    .hideZeroBalanceAssets,
                onActiveCoinItemTap: _onActiveCoinItemTap,
                onAssetItemTap: _onAssetItemTap,
                onAssetStatisticsTap: _onAssetStatisticsTap,
              );
            },
          ),
        ];
      case 1:
        if (mode != AuthorizeMode.logIn) {
          return const [
            SliverToBoxAdapter(
              child: SizedBox(
                width: double.infinity,
                height: 340,
                child: PriceChartPage(),
              ),
            ),
          ];
        }
        return [
          BlocSelector<CoinsBloc, CoinsState, List<Coin>>(
            selector: (state) => state.walletCoins.values.toList(),
            builder: (context, walletCoins) {
              return SliverToBoxAdapter(
                child: SizedBox(
                  width: double.infinity,
                  height: 340,
                  child: PortfolioGrowthChart(initialCoins: walletCoins),
                ),
              );
            },
          ),
        ];
      case 2:
        if (mode != AuthorizeMode.logIn) return [];
        return [
          BlocSelector<CoinsBloc, CoinsState, List<Coin>>(
            selector: (state) => state.walletCoins.values.toList(),
            builder: (context, walletCoins) {
              return SliverToBoxAdapter(
                child: SizedBox(
                  width: double.infinity,
                  height: 340,
                  child: PortfolioProfitLossChart(initialCoins: walletCoins),
                ),
              );
            },
          ),
        ];
      default:
        return [];
    }
  }

  void _onScroll() {
    if (_walletHalfLogged || !_scrollController.hasClients) return;

    final half = MediaQuery.of(context).size.height / 2;
    if (_scrollController.offset >= half) {
      _walletHalfLogged = true;
      final coinsCount = context.read<CoinsBloc>().state.walletCoins.length;
      context.read<AnalyticsBloc>().logEvent(
        WalletListHalfViewportReachedEventData(
          timeToHalfMs: _walletListStopwatch.elapsedMilliseconds,
          walletSize: coinsCount,
        ),
      );
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final double newOffset = (_scrollController.offset + event.scrollDelta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    if (newOffset == _scrollController.offset) {
      return;
    }

    _scrollController.jumpTo(newOffset);
  }

  PopupDispatcher _createPopupDispatcher() {
    final TakerBloc takerBloc = context.read<TakerBloc>();
    final BridgeBloc bridgeBloc = context.read<BridgeBloc>();

    return PopupDispatcher(
      width: 320,
      context: scaffoldKey.currentContext ?? context,
      barrierColor: isMobile ? Theme.of(context).colorScheme.onSurface : null,
      barrierDismissible: false,
      borderColor: theme.custom.specificButtonBorderColor,
      popupContent: WalletsManagerWrapper(
        eventType: WalletsManagerEventType.wallet,
        onSuccess: (_) async {
          takerBloc.add(TakerReInit());
          bridgeBloc.add(const BridgeReInit());
          await reInitTradingForms(context);
          _popupDispatcher?.close();
        },
      ),
    );
  }
}

class CoinListView extends StatelessWidget {
  const CoinListView({
    super.key,
    required this.mode,
    required this.searchPhrase,
    required this.withBalance,
    required this.onActiveCoinItemTap,
    required this.onAssetItemTap,
    required this.onAssetStatisticsTap,
  });

  final AuthorizeMode mode;
  final String searchPhrase;
  final bool withBalance;
  final Function(Coin) onActiveCoinItemTap;
  final Function(Coin) onAssetItemTap;
  final void Function(AssetId, Duration period) onAssetStatisticsTap;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case AuthorizeMode.logIn:
        return ActiveCoinsList(
          searchPhrase: searchPhrase,
          withBalance: withBalance,
          onCoinItemTap: onActiveCoinItemTap,
          onStatisticsTap: (coin) =>
              onAssetStatisticsTap(coin.assetId, const Duration(days: 1)),
          arrrActivationService: RepositoryProvider.of<ArrrActivationService>(
            context,
          ),
        );
      case AuthorizeMode.hiddenLogin:
      case AuthorizeMode.noLogin:
        return BlocSelector<CoinsBloc, CoinsState, List<Coin>>(
          selector: (state) => state.coins.values.toList(),
          builder: (context, coins) {
            // Assets are sorted by priority at the group level in AssetsList._groupAssetsByTicker()
            return AssetsList(
              useGroupedView: true,
              assets: coins.map((coin) => coin.assetId).toList(),
              withBalance: false,
              searchPhrase: searchPhrase,
              onAssetItemTap: (assetId) => onAssetItemTap(
                coins.firstWhere((coin) => coin.assetId == assetId),
              ),
              onStatisticsTap: onAssetStatisticsTap,
            );
          },
        );
    }
  }
}

class _MultiAddressWalletNotice extends StatelessWidget {
  const _MultiAddressWalletNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.primary.withValues(alpha: 0.2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.multiAddressWalletNoticeTitle.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  LocaleKeys.multiAddressWalletNoticeDescription.tr(),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SliverSearchBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverSearchBarDelegate({
    required this.searchController,
    required this.searchFocusNode,
    required this.withBalance,
    required this.onSearchChange,
    required this.onWithBalanceChange,
    required this.mode,
  });
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final bool withBalance;
  final ValueChanged<String> onSearchChange;
  final ValueChanged<bool> onWithBalanceChange;
  final AuthorizeMode mode;

  @override
  double get minExtent => isMobile ? 64 : 46;
  @override
  double get maxExtent =>
      isMobile ? (mode == AuthorizeMode.logIn ? 112 : 64) : 46;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // Apply collapse progress on both mobile and desktop
    final collapseProgress = (shrinkOffset / (maxExtent - minExtent)).clamp(
      0.0,
      1.0,
    );

    return SizedBox(
      height: (maxExtent - shrinkOffset).clamp(minExtent, maxExtent),
      child: WalletManageSection(
        withBalance: withBalance,
        searchController: searchController,
        searchFocusNode: searchFocusNode,
        onSearchChange: onSearchChange,
        onWithBalanceChange: onWithBalanceChange,
        mode: mode,
        pinned: shrinkOffset > 0,
        collapseProgress: collapseProgress,
      ),
    );
  }

  @override
  bool shouldRebuild(_SliverSearchBarDelegate oldDelegate) {
    return withBalance != oldDelegate.withBalance ||
        mode != oldDelegate.mode ||
        searchController != oldDelegate.searchController ||
        searchFocusNode != oldDelegate.searchFocusNode;
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
          topLeft: Radius.circular(0),
          topRight: Radius.circular(0),
        ),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
