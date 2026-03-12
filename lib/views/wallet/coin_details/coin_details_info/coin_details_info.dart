import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/analytics/events/portfolio_events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/portfolio_growth/portfolio_growth_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/profit_loss/profit_loss_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_bloc.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_event.dart';
import 'package:web_dex/bloc/coin_addresses/bloc/coin_addresses_state.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/coin_fiat_balance.dart';
import 'package:web_dex/shared/widgets/segwit_icon.dart';
import 'package:web_dex/views/common/page_header/disable_coin_button.dart';
import 'package:web_dex/views/common/page_header/page_header.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_growth_chart.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/portfolio_profit_loss_chart.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_addresses.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_common_buttons.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/coin_details_info_fiat.dart';
import 'package:web_dex/views/wallet/coin_details/coin_page_type.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_table.dart';

class CoinDetailsInfo extends StatefulWidget {
  const CoinDetailsInfo({
    required this.coin,
    required this.setPageType,
    required this.onBackButtonPressed,
    super.key,
  });
  final Coin coin;
  final void Function(CoinPageType) setPageType;
  final VoidCallback onBackButtonPressed;

  @override
  State<CoinDetailsInfo> createState() => _CoinDetailsInfoState();
}

class _CoinDetailsInfoState extends State<CoinDetailsInfo>
    with SingleTickerProviderStateMixin {
  Transaction? _selectedTransaction;
  final ScrollController _scrollController = ScrollController();

  String? get _walletId =>
      RepositoryProvider.of<AuthBloc>(context).state.currentUser?.walletId.name;

  late final _coinAddressesBloc = CoinAddressesBloc(
    context.sdk,
    widget.coin.abbr,
    context.read<AnalyticsBloc>(),
  )..add(const CoinAddressesStarted());

  @override
  void initState() {
    super.initState();
    const selectedDurationInitial = Duration(hours: 1);

    context.read<PortfolioGrowthBloc>().add(
      PortfolioGrowthLoadRequested(
        coins: [widget.coin],
        fiatCoinId: 'USDT',
        selectedPeriod: selectedDurationInitial,
        walletId: _walletId!,
      ),
    );

    context.read<ProfitLossBloc>().add(
      ProfitLossPortfolioChartLoadRequested(
        coins: [widget.coin],
        selectedPeriod: const Duration(hours: 1),
        fiatCoinId: 'USDT',
        walletId: _walletId!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _coinAddressesBloc,
      child: BlocListener<CoinAddressesBloc, CoinAddressesState>(
        listenWhen: (previous, current) =>
            previous.createAddressStatus != current.createAddressStatus &&
            current.createAddressStatus == FormStatus.success,
        listener: (context, state) {
          context.read<CoinsBloc>().add(
            CoinsPubkeysRequested(widget.coin.abbr),
          );
        },
        child: PageLayout(
          padding: const EdgeInsets.fromLTRB(15, 32, 15, 20),
          header: PageHeader(
            title: widget.coin.displayName,
            widgetTitle: widget.coin.mode == CoinMode.segwit
                ? const Padding(
                    padding: EdgeInsets.only(left: 6.0),
                    child: SegwitIcon(height: 22),
                  )
                : null,
            backText: _backText,
            onBackButtonPressed: _onBackButtonPressed,
            actions: [_buildDisableButton()],
          ),
          content: Expanded(child: _buildContent(context)),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (isMobile) {
      return _MobileContent(
        coin: widget.coin,
        selectedTransaction: _selectedTransaction,
        setPageType: widget.setPageType,
        setTransaction: _selectTransaction,
        scrollController: _scrollController,
      );
    }
    return _DesktopContent(
      coin: widget.coin,
      selectedTransaction: _selectedTransaction,
      setPageType: widget.setPageType,
      setTransaction: _selectTransaction,
      scrollController: _scrollController,
    );
  }

  Widget _buildDisableButton() {
    if (_haveTransaction) return const SizedBox();

    return DisableCoinButton(
      onClick: () {
        confirmBeforeDisablingCoin(
          widget.coin,
          context,
          onConfirm: () {
            widget.onBackButtonPressed();
          },
        );
      },
    );
  }

  void _selectTransaction(Transaction? tx) {
    setState(() {
      _selectedTransaction = tx;
    });
  }

  void _onBackButtonPressed() {
    if (_haveTransaction) {
      _selectTransaction(null);
      return;
    }
    widget.onBackButtonPressed();
  }

  String get _backText {
    if (_haveTransaction) return LocaleKeys.back.tr();
    return LocaleKeys.backToWallet.tr();
  }

  bool get _haveTransaction => _selectedTransaction != null;

  @override
  void dispose() {
    _coinAddressesBloc.close().ignore();
    _scrollController.dispose();
    super.dispose();
  }
}

class _DesktopContent extends StatelessWidget {
  const _DesktopContent({
    required this.coin,
    required this.selectedTransaction,
    required this.setPageType,
    required this.setTransaction,
    required this.scrollController,
  });

  final Coin coin;
  final Transaction? selectedTransaction;
  final void Function(CoinPageType) setPageType;
  final Function(Transaction?) setTransaction;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: DexScrollbar(
        scrollController: scrollController,
        isMobile: isMobile,
        child: CustomScrollView(
          controller: scrollController,
          slivers: <Widget>[
            if (selectedTransaction == null)
              SliverToBoxAdapter(
                child: _DesktopCoinDetails(
                  coin: coin,
                  setPageType: setPageType,
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            TransactionTable(
              coin: coin,
              selectedTransaction: selectedTransaction,
              setTransaction: setTransaction,
            ),
            if (selectedTransaction == null) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              CoinAddresses(coin: coin, setPageType: setPageType),
            ],
          ],
        ),
      ),
    );
  }
}

class _DesktopCoinDetails extends StatelessWidget {
  const _DesktopCoinDetails({required this.coin, required this.setPageType});

  final Coin coin;
  final void Function(CoinPageType) setPageType;

  @override
  Widget build(BuildContext context) {
    final tradingState = context.watch<TradingStatusBloc>().state;
    final canTradeCoin = tradingState.canTradeAssets([coin.id]);

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Column(
        children: [
          SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 5, 12, 0),
                child: AssetLogo.ofId(coin.id, size: 50),
              ),
              _Balance(coin: coin),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 18.0),
                child: _SpecificButton(coin: coin, selectWidget: setPageType),
              ),
              const Spacer(),
              CoinDetailsInfoFiat(coin: coin, isMobile: false),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 28.0, 0, 0),
            child: CoinDetailsCommonButtons(
              isMobile: false,
              selectWidget: setPageType,
              onClickSwapButton: canTradeCoin
                  ? () => _goToSwap(context, coin)
                  : null,
              coin: coin,
            ),
          ),
          const Gap(16),
          _CoinDetailsMarketMetricsTabBar(coin: coin),
        ],
      ),
    );
  }
}

class _MobileContent extends StatelessWidget {
  const _MobileContent({
    required this.coin,
    required this.selectedTransaction,
    required this.setPageType,
    required this.setTransaction,
    required this.scrollController,
  });

  final Coin coin;
  final Transaction? selectedTransaction;
  final void Function(CoinPageType) setPageType;
  final Function(Transaction?) setTransaction;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return DexScrollbar(
      scrollController: scrollController,
      isMobile: isMobile,
      child: CustomScrollView(
        controller: scrollController,
        slivers: <Widget>[
          if (selectedTransaction == null)
            SliverToBoxAdapter(
              child: _CoinDetailsInfoHeader(
                coin: coin,
                setPageType: setPageType,
                context: context,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          if (selectedTransaction == null)
            CoinAddresses(coin: coin, setPageType: setPageType),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
          TransactionTable(
            coin: coin,
            selectedTransaction: selectedTransaction,
            setTransaction: setTransaction,
          ),
        ],
      ),
    );
  }
}

class _CoinDetailsInfoHeader extends StatelessWidget {
  const _CoinDetailsInfoHeader({
    required this.coin,
    required this.setPageType,
    required this.context,
  });

  final Coin coin;
  final void Function(CoinPageType p1) setPageType;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    final tradingState = context.watch<TradingStatusBloc>().state;
    final canTradeCoin = tradingState.canTradeAssets([coin.id]);

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 18, 15, 16),
      decoration: BoxDecoration(
        color: isMobile ? Theme.of(context).cardColor : null,
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: Column(
        children: [
          AssetIcon.ofTicker(coin.abbr, size: 35),
          const SizedBox(height: 8),
          _Balance(coin: coin),
          const SizedBox(height: 12),
          _SpecificButton(coin: coin, selectWidget: setPageType),
          Padding(
            padding: const EdgeInsets.only(top: 15.0),
            child: CoinDetailsInfoFiat(coin: coin, isMobile: true),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12.0, bottom: 14.0),
            child: CoinDetailsCommonButtons(
              isMobile: true,
              selectWidget: setPageType,
              onClickSwapButton: canTradeCoin
                  ? () => _goToSwap(context, coin)
                  : null,
              coin: coin,
            ),
          ),
          _CoinDetailsMarketMetricsTabBar(coin: coin),
        ],
      ),
    );
  }
}

class _CoinDetailsMarketMetricsTabBar extends StatefulWidget {
  const _CoinDetailsMarketMetricsTabBar({required this.coin});

  final Coin coin;

  @override
  _CoinDetailsMarketMetricsTabBarState createState() =>
      _CoinDetailsMarketMetricsTabBarState();
}

class _CoinDetailsMarketMetricsTabBarState
    extends State<_CoinDetailsMarketMetricsTabBar>
    with TickerProviderStateMixin {
  TabController? _tabController;
  int _currentIndex = 0;

  void _initializeTabController(int numTabs) {
    _tabController = TabController(
      length: numTabs,
      vsync: this,
      initialIndex: _currentIndex < numTabs ? _currentIndex : 0,
    );

    _tabController!.addListener(() {
      if (_tabController!.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController!.index;
        });
      }

      if (!_tabController!.indexIsChanging) {
        if (_tabController!.index == 0) {
          final growthState = context.read<PortfolioGrowthBloc>().state;
          if (growthState is PortfolioGrowthChartLoadSuccess) {
            final period = _formatDuration(growthState.selectedPeriod);
            context.read<AnalyticsBloc>().logEvent(
              PortfolioGrowthViewedEventData(
                period: period,
                growthPct: growthState.percentageIncrease,
              ),
            );
          }
        } else if (_tabController!.index == 1) {
          final profitLossState = context.read<ProfitLossBloc>().state;
          if (profitLossState is PortfolioProfitLossChartLoadSuccess) {
            final timeframe = _formatDuration(profitLossState.selectedPeriod);
            context.read<AnalyticsBloc>().logEvent(
              PortfolioPnlViewedEventData(
                timeframe: timeframe,
                realizedPnl: profitLossState.totalValue,
                unrealizedPnl: 0,
              ),
            );
          }
        }
      }
    });
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays >= 365) return '${duration.inDays ~/ 365}y';
    if (duration.inDays >= 30) return '${duration.inDays ~/ 30}M';
    if (duration.inDays >= 1) return '${duration.inDays}d';
    if (duration.inHours >= 1) return '${duration.inHours}h';
    if (duration.inMinutes >= 1) return '${duration.inMinutes}m';
    return '${duration.inSeconds}s';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final portfolioGrowthState = context.watch<PortfolioGrowthBloc>().state;
    final profitLossState = context.watch<ProfitLossBloc>().state;
    final isPortfolioGrowthSupported =
        portfolioGrowthState is! PortfolioGrowthChartUnsupported;
    final isProfitLossSupported =
        profitLossState is! PortfolioProfitLossChartUnsupported;
    final areChartsSupported =
        isPortfolioGrowthSupported || isProfitLossSupported;
    final numChartsSupported =
        (isPortfolioGrowthSupported ? 1 : 0) + (isProfitLossSupported ? 1 : 0);

    if (areChartsSupported) {
      if (_tabController == null ||
          _tabController!.length != numChartsSupported) {
        _initializeTabController(numChartsSupported);
      }
    } else {
      _tabController?.dispose();
      _tabController = null;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portfolioGrowthState = context.watch<PortfolioGrowthBloc>().state;
    final profitLossState = context.watch<ProfitLossBloc>().state;
    final isPortfolioGrowthSupported =
        portfolioGrowthState is! PortfolioGrowthChartUnsupported;
    final isProfitLossSupported =
        profitLossState is! PortfolioProfitLossChartUnsupported;
    final areChartsSupported =
        isPortfolioGrowthSupported || isProfitLossSupported;
    final numChartsSupported =
        (isPortfolioGrowthSupported ? 1 : 0) + (isProfitLossSupported ? 1 : 0);

    if (!areChartsSupported) {
      return const SizedBox.shrink();
    }

    if (_tabController == null) {
      _initializeTabController(numChartsSupported);
    }

    return Column(
      children: [
        Card(
          child: TabBar(
            controller: _tabController,
            tabs: [
              if (isPortfolioGrowthSupported) Tab(text: LocaleKeys.growth.tr()),
              if (isProfitLossSupported)
                Tab(text: LocaleKeys.profitAndLoss.tr()),
            ],
          ),
        ),
        SizedBox(
          height: isMobile ? 340 : 260,
          child: TabBarView(
            controller: _tabController,
            children: [
              if (isPortfolioGrowthSupported)
                SizedBox(
                  width: double.infinity,
                  height: isMobile ? 340 : 260,
                  child: PortfolioGrowthChart(initialCoins: [widget.coin]),
                ),
              if (isProfitLossSupported)
                SizedBox(
                  width: double.infinity,
                  height: isMobile ? 340 : 260,
                  child: PortfolioProfitLossChart(initialCoins: [widget.coin]),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.coin});
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    final balance = coin.balance(context.sdk);
    final value = hideBalances
        ? maskedBalanceText
        : balance == null
        ? null
        : doubleToString(balance);

    return Column(
      crossAxisAlignment: isMobile
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isMobile)
          const SizedBox.shrink()
        else
          Text(
            LocaleKeys.yourBalance.tr(),
            style: themeData.textTheme.titleMedium!.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.custom.headerFloatBoxColor,
            ),
          ),
        Flexible(
          child: Row(
            mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: isMobile
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: AutoScrollText(
                  key: const Key('coin-details-balance'),
                  text: value ?? '',
                  isSelectable: true,
                  style: themeData.textTheme.titleMedium!.copyWith(
                    fontSize: isMobile ? 25 : 22,
                    fontWeight: FontWeight.w700,
                    color: theme.custom.headerFloatBoxColor,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                Coin.normalizeAbbr(coin.abbr),
                style: themeData.textTheme.titleSmall!.copyWith(
                  fontSize: isMobile ? 25 : 20,
                  fontWeight: FontWeight.w500,
                  color: theme.custom.headerFloatBoxColor,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        if (!isMobile) _FiatBalance(coin: coin),
      ],
    );
  }
}

class _FiatBalance extends StatelessWidget {
  const _FiatBalance({required this.coin});
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        children: [
          Text(
            LocaleKeys.fiatBalance.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6.0),
            child: CoinFiatBalance(
              coin,
              isSelectable: true,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecificButton extends StatelessWidget {
  const _SpecificButton({required this.coin, required this.selectWidget});
  final Coin coin;
  final void Function(CoinPageType) selectWidget;

  @override
  Widget build(BuildContext context) {
    final currentWallet = context.watch<AuthBloc>().state.currentUser?.wallet;
    final walletType = currentWallet?.config.type;

    if (coin.abbr == 'KMD' &&
        (walletType == WalletType.iguana ||
            walletType == WalletType.hdwallet)) {
      return _GetRewardsButton(
        coin: coin,
        onTap: () => selectWidget(CoinPageType.claim),
      );
    }
    return const SizedBox.shrink();
  }
}

class _GetRewardsButton extends StatelessWidget {
  const _GetRewardsButton({required this.coin, required this.onTap});
  final Coin coin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusDecorator(
      child: InkWell(
        onTap: coin.isSuspended ? null : onTap,
        child: Opacity(
          opacity: coin.isSuspended ? 0.4 : 1,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 110),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.custom.specificButtonBorderColor),
              color: theme.custom.specificButtonBackgroundColor,
            ),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 5),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: SvgPicture.asset(
                    '$assetsPath/ui_icons/rewards.svg',
                    colorFilter: ColorFilter.mode(
                      Theme.of(context).textTheme.labelLarge?.color ??
                          Colors.white,
                      BlendMode.srcIn,
                    ),
                    allowDrawingOutsideViewBox: true,
                  ),
                ),
                Text(
                  LocaleKeys.getRewards.tr(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _goToSwap(BuildContext context, Coin coin) {
  context.read<TakerBloc>().add(TakerSetSellCoin(coin));
  routingState.selectedMenu = MainMenuValue.dex;
}
