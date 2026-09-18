import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/fiat_state.dart';
import 'package:web_dex/router/state/main_menu_state.dart';
import 'package:web_dex/router/state/market_maker_bot_state.dart';
import 'package:web_dex/router/state/nfts_state.dart';
import 'package:web_dex/router/state/settings_section_state.dart';
import 'package:web_dex/router/state/wallet_state.dart';

class RoutingState {
  final WalletState walletState = WalletState();
  final FiatState fiatState = FiatState();
  final DexState dexState = DexState();
  final MarketMakerBotState marketMakerState = MarketMakerBotState();
  final NFTsState nftsState = NFTsState();
  final SettingsSectionState settingsState = SettingsSectionState();
  final MainMenuState _mainMenu = MainMenuState();

  MainMenuValue get selectedMenu => _mainMenu.selectedMenu;
  bool isBrowserNavigationBlocked = false;

  set selectedMenu(MainMenuValue menu) {
    if (_shouldCallResetWhenMenuChanged(menu)) {
      reset();
    }
    _mainMenu.selectedMenu = menu;
    if (menu == MainMenuValue.settings && !isMobile) {
      settingsState.selectedMenu = SettingsMenuValue.general;
    }
  }

  bool get isPageContentShown {
    return walletState.selectedCoin.isNotEmpty || walletState.action.isNotEmpty;
  }

  void resetDataForPageContent() {
    walletState.reset();
  }

  void reset() {
    walletState.reset();
    fiatState.reset();
    dexState.reset();
    marketMakerState.reset();
    nftsState.reset();
    settingsState.reset();
  }

  void addListener(void Function() notifyListeners) {
    _mainMenu.addListener(notifyListeners);
    walletState.addListener(notifyListeners);
    fiatState.addListener(notifyListeners);
    dexState.addListener(notifyListeners);
    marketMakerState.addListener(notifyListeners);
    nftsState.addListener(notifyListeners);
    settingsState.addListener(notifyListeners);
  }

  bool _shouldCallResetWhenMenuChanged(MainMenuValue menu) {
    if (_mainMenu.selectedMenu != menu) return true;
    if (_mainMenu.selectedMenu == menu &&
        menu == MainMenuValue.settings &&
        !isMobile) {
      return false;
    }
    return true;
  }

  void resetOnLogOut() {
    walletState.resetOnLogOut();
    fiatState.resetOnLogOut();
    dexState.resetOnLogOut();
    marketMakerState.resetOnLogOut();
    nftsState.resetOnLogOut();
    settingsState.resetOnLogOut();
  }
}

RoutingState routingState = RoutingState();
