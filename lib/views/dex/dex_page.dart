import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_tab_bar/dex_tab_bar_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/ui/clock_warning_banner.dart';
import 'package:web_dex/shared/widgets/hidden_without_wallet.dart';
import 'package:web_dex/views/common/pages/page_layout.dart';
import 'package:web_dex/views/dex/dex_tab_bar.dart';
import 'package:web_dex/views/dex/common/dex_responsive.dart';
import 'package:web_dex/views/dex/entities_list/dex_list_wrapper.dart';
import 'package:web_dex/views/dex/entity_details/trading_details.dart';
import 'package:web_dex/views/wallet/wallet_page/common/zhtlc/zhtlc_configuration_handler.dart';

class DexPage extends StatefulWidget {
  const DexPage({super.key});

  @override
  State<DexPage> createState() => _DexPageState();
}

class _DexPageState extends State<DexPage> {
  bool isTradingDetails = false;

  @override
  void initState() {
    routingState.dexState.addListener(_onRouteChange);
    super.initState();
  }

  @override
  void dispose() {
    routingState.dexState.removeListener(_onRouteChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final myOrdersService = RepositoryProvider.of<MyOrdersService>(context);
    final pageContent = MultiBlocProvider(
      providers: [
        BlocProvider<DexTabBarBloc>(
          key: const Key('dex-page'),
          create: (BuildContext context) => DexTabBarBloc(
            RepositoryProvider.of<KomodoDefiSdk>(context),
            tradingEntitiesBloc,
            MarketMakerBotOrderListRepository(
              myOrdersService,
              SettingsRepository(),
              coinsRepository,
            ),
          )..add(const ListenToOrdersRequested()),
        ),
      ],
      child: BlocBuilder<DexTabBarBloc, DexTabBarState>(
        builder: (context, state) {
          // Defensive bounds check for tabIndex
          final bool inRange =
              state.tabIndex >= 0 && state.tabIndex < DexListType.values.length;
          final tab = inRange
              ? DexListType.values[state.tabIndex]
              : DexListType.swap;
          // Explicit mapping: only orders tab shows order entities, all others show swaps
          final kind = switch (tab) {
            DexListType.orders => TradingEntityKind.order,
            DexListType.swap => TradingEntityKind.swap,
            DexListType.inProgress => TradingEntityKind.swap,
            DexListType.history => TradingEntityKind.swap,
          };
          return isTradingDetails
              ? TradingDetails(uuid: routingState.dexState.uuid, kind: kind)
              : _DexContent();
        },
      ),
    );
    return ZhtlcConfigurationHandler(child: pageContent);
  }

  void _onRouteChange() {
    setState(() => isTradingDetails = routingState.dexState.isTradingDetails);
  }
}

class _DexContent extends StatefulWidget {
  @override
  State<_DexContent> createState() => _DexContentState();
}

class _DexContentState extends State<_DexContent> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DexTabBarBloc, DexTabBarState>(
      builder: (BuildContext context, DexTabBarState state) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final spec = DexResponsiveSpec.fromWidth(constraints.maxWidth);
            final colors = GleecColorTokens.of(context);
            final geometry = GleecGeometry.of(context);

            return PageLayout(
              content: Flexible(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: spec.maxContentWidth),
                    child: Container(
                      margin: spec.usesMobileLists
                          ? EdgeInsets.only(top: geometry.space12)
                          : null,
                      padding: EdgeInsets.symmetric(horizontal: spec.gutter),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.border),
                        borderRadius: geometry.borderRadius24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const HiddenWithoutWallet(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 12.0),
                              child: DexTabBar(),
                            ),
                          ),
                          const ClockWarningBanner(),
                          Flexible(
                            child: shouldShowTabContent(state.tabIndex)
                                ? DexListWrapper(
                                    key: Key(
                                      'dex-list-wrapper-${state.tabIndex}',
                                    ),
                                    state.tabIndex >= 0 &&
                                            state.tabIndex <
                                                DexListType.values.length
                                        ? DexListType.values[state.tabIndex]
                                        : DexListType.swap,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool shouldShowTabContent(int tabIndex) {
    return tabIndex >= 0 && tabIndex < DexListType.values.length;
  }
}
