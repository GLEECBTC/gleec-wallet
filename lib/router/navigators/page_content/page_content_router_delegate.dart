import 'package:flutter/material.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/bridge/bridge_page.dart';
import 'package:web_dex/views/fiat/fiat_page.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_bot_page.dart';
import 'package:web_dex/views/nfts/nft_page.dart';
import 'package:web_dex/views/settings/settings_page.dart';
import 'package:web_dex/views/settings/widgets/support_page/support_page.dart';
import 'package:web_dex/views/swap/swap_shell.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_page.dart';

class PageContentRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    switch (routingState.selectedMenu) {
      case MainMenuValue.fiat:
        return const FiatPage();
      case MainMenuValue.dex:
        // The Swap surface. The full trading interface is not removed — it is
        // the Advanced destination inside this shell.
        return const SwapShell();
      case MainMenuValue.bridge:
        return const BridgePage();
      case MainMenuValue.marketMakerBot:
        return const MarketMakerBotPage();
      case MainMenuValue.nft:
        return NftPage(
          key: const Key('nft-page'),
          pageState: routingState.nftsState.pageState,
          uuid: routingState.nftsState.uuid,
        );
      case MainMenuValue.settings:
        return SettingsPage(
          selectedMenu: routingState.settingsState.selectedMenu,
        );
      case MainMenuValue.support:
        return SupportPage();
      case MainMenuValue.wallet:
      default:
        return WalletPage(
          coinAbbr: routingState.walletState.selectedCoin,
          action: routingState.walletState.coinsManagerAction,
        );
    }
  }

  @override
  Future<void> setNewRoutePath(AppRoutePath configuration) async {}
}
