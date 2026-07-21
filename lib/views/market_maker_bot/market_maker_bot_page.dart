import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/dex_tab_bar/dex_tab_bar_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_bot/market_maker_bot_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_bot_order_list_repository.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_order_list/market_maker_order_list_bloc.dart';
import 'package:web_dex/bloc/market_maker_bot/market_maker_trade_form/market_maker_trade_form_bloc.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/views/dex/entity_details/trading_details.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_bot_view.dart';

class MarketMakerBotPage extends StatefulWidget {
  const MarketMakerBotPage() : super(key: const Key('market-maker-bot-page'));

  @override
  State<StatefulWidget> createState() => _MarketMakerBotPageState();
}

class _MarketMakerBotPageState extends State<MarketMakerBotPage> {
  bool isTradingDetails = false;

  @override
  void initState() {
    routingState.marketMakerState.addListener(_onRouteChange);
    super.initState();
  }

  @override
  void dispose() {
    routingState.marketMakerState.removeListener(_onRouteChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final myOrdersService = RepositoryProvider.of<MyOrdersService>(context);

    final orderListRepository = MarketMakerBotOrderListRepository(
      myOrdersService,
      SettingsRepository(),
      coinsRepository,
    );

    final pageContent = MultiBlocProvider(
      providers: [
        BlocProvider<DexTabBarBloc>(
          create: (BuildContext context) => DexTabBarBloc(
            RepositoryProvider.of<KomodoDefiSdk>(context),
            tradingEntitiesBloc,
            orderListRepository,
          )..add(const ListenToOrdersRequested()),
        ),
        BlocProvider<MarketMakerTradeFormBloc>(
          create: (BuildContext context) => MarketMakerTradeFormBloc(
            dexRepo: RepositoryProvider.of<DexRepository>(context),
            coinsRepo: coinsRepository,
          ),
        ),
        BlocProvider<MarketMakerOrderListBloc>(
          create: (BuildContext context) {
            final botBloc = context.read<MarketMakerBotBloc>();
            return MarketMakerOrderListBloc(
              MarketMakerBotOrderListRepository(
                myOrdersService,
                SettingsRepository(),
                coinsRepository,
              ),
              captureWalletSession: botBloc.captureWalletSession,
              captureOrderOwnership: botBloc.captureOrderOwnership,
              isFreshWalletSession: botBloc.isFreshWalletSession,
            );
          },
        ),
      ],
      child: BlocBuilder<DexTabBarBloc, DexTabBarState>(
        builder: (context, state) {
          final tab = _safeDexListType(state);
          final kind = _kindForTab(tab);
          final canShowDetails = isTradingDetails && tab != DexListType.orders;
          return canShowDetails
              ? TradingDetails(
                  uuid: routingState.marketMakerState.uuid,
                  kind: kind,
                )
              : MarketMakerBotView();
        },
      ),
    );
    return pageContent;
  }

  void _onRouteChange() {
    setState(
      () => isTradingDetails = routingState.marketMakerState.isTradingDetails,
    );
  }

  DexListType _safeDexListType(DexTabBarState state) {
    final index = state.tabIndex;
    if (index < 0 || index >= DexListType.values.length) {
      return DexListType.swap;
    }
    return DexListType.values[index];
  }

  TradingEntityKind _kindForTab(DexListType tab) {
    return switch (tab) {
      DexListType.orders => TradingEntityKind.order,
      DexListType.swap => TradingEntityKind.swap,
      DexListType.inProgress => TradingEntityKind.swap,
      DexListType.history => TradingEntityKind.swap,
    };
  }
}
