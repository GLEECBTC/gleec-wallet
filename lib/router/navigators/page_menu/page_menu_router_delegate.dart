import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/routes.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/fiat/fiat_page.dart';
import 'package:web_dex/views/market_maker_bot/market_maker_bot_page.dart';
import 'package:web_dex/views/nfts/nft_page.dart';
import 'package:web_dex/views/settings/settings_page.dart';
import 'package:web_dex/views/settings/widgets/support_page/support_page.dart';
import 'package:web_dex/views/swap/swap_shell.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_page.dart';

class PageMenuRouterDelegate extends RouterDelegate<AppRoutePath>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppRoutePath> {
  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    const empty = SizedBox();
    switch (routingState.selectedMenu) {
      case MainMenuValue.wallet:
        return WalletPage(
          coinAbbr: routingState.walletState.selectedCoin,
          action: routingState.walletState.coinsManagerAction,
        );
      case MainMenuValue.fiat:
        return isMobile ? const FiatPage() : empty;
      case MainMenuValue.dex:
        // The same Swap surface the wide layout gets. This built
        // `DexPage` directly, so on any screen under 768px - a phone,
        // or simply a narrow browser window - the unified swap form
        // was unreachable and the menu entry opened the old trading
        // page instead.
        return isMobile ? const SwapShell() : empty;
      case MainMenuValue.marketMakerBot:
        return isMobile ? const MarketMakerBotPage() : empty;
      case MainMenuValue.nft:
        return isMobile
            ? NftPage(
                key: const Key('nft-page'),
                pageState: routingState.nftsState.pageState,
                uuid: routingState.nftsState.uuid,
              )
            : empty;
      case MainMenuValue.settings:
        return isMobile
            ? SettingsPage(
                selectedMenu: routingState.settingsState.selectedMenu,
              )
            : empty;
      case MainMenuValue.support:
        return isMobile
            ? WalletPage(
                coinAbbr: routingState.walletState.selectedCoin,
                action: routingState.walletState.coinsManagerAction,
              )
            : SupportPage();
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
