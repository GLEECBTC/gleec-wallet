import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/bridge_form/bridge_bloc.dart';
import 'package:web_dex/bloc/bridge_form/bridge_event.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/bridge_section_state.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/fiat_state.dart';
import 'package:web_dex/router/state/market_maker_bot_state.dart';
import 'package:web_dex/router/state/nfts_state.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/main_layout/main_layout.dart';

class AppRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  AppRouterDelegate() : navigatorKey = GlobalKey<NavigatorState>() {
    routingState.addListener(notifyListeners);
  }

  @override
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    updateScreenType(context);

    final MaterialPage<dynamic> page1 = MaterialPage<dynamic>(
      key: const ValueKey('MainPage'),
      child: Builder(
        builder: (context) {
          materialPageContext = context;
          return GestureDetector(
            onTap: () => runDropdownDismiss(context),
            child: MainLayout(key: ValueKey('${routingState.selectedMenu}')),
          );
        },
      ),
    );

    final List<Page<dynamic>> pages = <Page<dynamic>>[page1];

    return Navigator(
      key: navigatorKey,
      pages: pages,
      onDidRemovePage: (Page<Object?> page) => pages.remove(page),
    );
  }

  void runDropdownDismiss(BuildContext context) {
    // Taker form
    context.read<TakerBloc>().add(TakerCoinSelectorOpen(false));
    context.read<TakerBloc>().add(TakerOrderSelectorOpen(false));

    // Maker form
    final makerFormBloc = RepositoryProvider.of<MakerFormBloc>(context);
    makerFormBloc.showSellCoinSelect = false;
    makerFormBloc.showBuyCoinSelect = false;

    // Bridge form
    context.read<BridgeBloc>().add(const BridgeShowTickerDropdown(false));
    context.read<BridgeBloc>().add(const BridgeShowSourceDropdown(false));
    context.read<BridgeBloc>().add(const BridgeShowTargetDropdown(false));
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {
    final configurationToSet = routingState.isBrowserNavigationBlocked
        ? currentConfiguration
        : configuration;

    if (configurationToSet is WalletRoutePath) {
      _setNewWalletRoutePath(configurationToSet);
    } else if (configurationToSet is FiatRoutePath) {
      _setNewFiatRoutePath(configurationToSet);
    } else if (configurationToSet is DexRoutePath) {
      _setNewDexRoutePath(configurationToSet);
    } else if (configurationToSet is BridgeRoutePath) {
      _setNewBridgeRoutePath(configurationToSet);
    } else if (configurationToSet is NftRoutePath) {
      _setNewNftsRoutePath(configurationToSet);
    } else if (configurationToSet is SettingsRoutePath) {
      _setNewSettingsRoutePath(configurationToSet);
    } else if (configurationToSet is MarketMakerBotRoutePath) {
      _setNewMarketMakerBotRoutePath(configurationToSet);
    } else {
      routingState.reset();
    }
  }

  void _setNewWalletRoutePath(WalletRoutePath path) {
    routingState.selectedMenu = MainMenuValue.wallet;
    if (path.abbr.isNotEmpty) {
      routingState.walletState.selectedCoin = path.abbr.toUpperCase();
    } else if (path.action.isNotEmpty) {
      routingState.walletState.action = path.action;
    } else {
      routingState.resetDataForPageContent();
    }
  }

  void _setNewBridgeRoutePath(BridgeRoutePath path) {
    routingState.selectedMenu = MainMenuValue.bridge;
    routingState.bridgeState.action = path.action;
    routingState.bridgeState.uuid = path.uuid;
  }

  void _setNewNftsRoutePath(NftRoutePath path) {
    routingState.selectedMenu = MainMenuValue.nft;
    routingState.nftsState.uuid = path.uuid;
    routingState.nftsState.pageState = path.pageState;
  }

  void _setNewFiatRoutePath(FiatRoutePath path) {
    routingState.selectedMenu = MainMenuValue.fiat;
    routingState.fiatState.action = path.action;
    routingState.fiatState.uuid = path.uuid;
  }

  void _setNewDexRoutePath(DexRoutePath path) {
    routingState.selectedMenu = MainMenuValue.dex;
    routingState.dexState.action = path.action;
    routingState.dexState.uuid = path.uuid;
    routingState.dexState.fromCurrency = path.fromCurrency;
    routingState.dexState.fromAmount = path.fromAmount;
    routingState.dexState.toCurrency = path.toCurrency;
    routingState.dexState.toAmount = path.toAmount;
    routingState.dexState.orderType = path.orderType;
  }

  void _setNewMarketMakerBotRoutePath(MarketMakerBotRoutePath path) {
    routingState.selectedMenu = MainMenuValue.marketMakerBot;
    routingState.marketMakerState.action = path.action;
    routingState.marketMakerState.uuid = path.uuid;
  }

  void _setNewSettingsRoutePath(SettingsRoutePath path) {
    routingState.selectedMenu = MainMenuValue.settings;
    routingState.settingsState.selectedMenu = path.selectedMenu;
  }

  Map<MainMenuValue, AppRoutePath> get _menuConfiguration {
    return {
      MainMenuValue.wallet: _currentWalletConfiguration,
      MainMenuValue.fiat: _currentFiatConfiguration,
      MainMenuValue.dex: _currentDexConfiguration,
      MainMenuValue.bridge: _currentBridgeConfiguration,
      MainMenuValue.marketMakerBot: _currentMarketMakerBotConfiguration,
      MainMenuValue.nft: _currentNftConfiguration,
      MainMenuValue.settings: _currentSettingsConfiguration,
      MainMenuValue.support: _currentSettingsConfiguration,
    };
  }

  @override
  AppRoutePath? get currentConfiguration {
    return _menuConfiguration.containsKey(routingState.selectedMenu)
        ? _menuConfiguration[routingState.selectedMenu]
        : null;
  }

  AppRoutePath get _currentWalletConfiguration {
    if (routingState.walletState.selectedCoin.isNotEmpty) {
      return WalletRoutePath.coinDetails(routingState.walletState.selectedCoin);
    } else if (routingState.walletState.action.isNotEmpty) {
      return WalletRoutePath.action(routingState.walletState.action);
    }
    return WalletRoutePath.wallet();
  }

  AppRoutePath get _currentFiatConfiguration {
    if (routingState.fiatState.action == FiatAction.tradingDetails) {
      return FiatRoutePath.swapDetails(
        routingState.fiatState.action,
        routingState.fiatState.uuid,
      );
    }

    return FiatRoutePath.fiat();
  }

  AppRoutePath get _currentDexConfiguration {
    if (routingState.dexState.action == DexAction.tradingDetails) {
      return DexRoutePath.swapDetails(
        routingState.dexState.action,
        routingState.dexState.uuid,
      );
    }

    return DexRoutePath.dex(
      fromAmount: routingState.dexState.fromAmount,
      fromCurrency: routingState.dexState.fromCurrency,
      toAmount: routingState.dexState.toAmount,
      toCurrency: routingState.dexState.toCurrency,
      orderType: routingState.dexState.orderType,
    );
  }

  AppRoutePath get _currentMarketMakerBotConfiguration {
    if (routingState.marketMakerState.action ==
        MarketMakerBotAction.tradingDetails) {
      return MarketMakerBotRoutePath.swapDetails(
        routingState.marketMakerState.action,
        routingState.marketMakerState.uuid,
      );
    }

    return MarketMakerBotRoutePath.marketMakerBot();
  }

  AppRoutePath get _currentBridgeConfiguration {
    if (routingState.bridgeState.action == BridgeAction.tradingDetails) {
      return BridgeRoutePath.swapDetails(
        routingState.bridgeState.action,
        routingState.bridgeState.uuid,
      );
    }

    return BridgeRoutePath.bridge();
  }

  AppRoutePath get _currentNftConfiguration {
    switch (routingState.nftsState.pageState) {
      case NFTSelectedState.send:
        return NftRoutePath.nftDetails(routingState.nftsState.uuid, true);
      case NFTSelectedState.details:
        return NftRoutePath.nftDetails(routingState.nftsState.uuid, false);
      case NFTSelectedState.receive:
        return NftRoutePath.nftReceive();
      case NFTSelectedState.transactions:
        return NftRoutePath.nftTransactions();
      case NFTSelectedState.none:
        return NftRoutePath.nfts();
    }
  }

  AppRoutePath get _currentSettingsConfiguration {
    switch (routingState.settingsState.selectedMenu) {
      case SettingsMenuValue.general:
        return SettingsRoutePath.general();
      case SettingsMenuValue.security:
        return SettingsRoutePath.security();
      case SettingsMenuValue.privacy:
        return SettingsRoutePath.privacy();
      case SettingsMenuValue.support:
        return SettingsRoutePath.support();
      case SettingsMenuValue.feedback:
        return SettingsRoutePath.feedback();
      case SettingsMenuValue.none:
        return SettingsRoutePath.root();
    }
  }
}
