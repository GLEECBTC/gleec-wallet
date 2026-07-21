import 'package:easy_localization/easy_localization.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

enum MainMenuValue {
  wallet,
  dex,
  card,
  fiat,
  bridge,
  marketMakerBot,
  nft,
  settings,
  support,
  more,
  none;

  static MainMenuValue defaultMenu() => MainMenuValue.wallet;

  bool isEnabledInCurrentMode({required bool tradingEnabled}) {
    return tradingEnabled || !isDisabledWhenWalletOnly;
  }

  // Getter to determine if the item is disabled if the wallet is in wallet-only mode

  bool get isDisabledWhenWalletOnly {
    switch (this) {
      case MainMenuValue.dex:
      case MainMenuValue.bridge:
      case MainMenuValue.marketMakerBot:
        return true;
      case MainMenuValue.wallet:
      case MainMenuValue.card:
      case MainMenuValue.fiat:
      case MainMenuValue.nft:
      case MainMenuValue.settings:
      case MainMenuValue.support:
      case MainMenuValue.more:
        return false;
      case MainMenuValue.none:
        return false;
    }
  }

  String get title {
    switch (this) {
      case MainMenuValue.wallet:
        return LocaleKeys.wallet.tr();
      case MainMenuValue.fiat:
        return LocaleKeys.fiat.tr();
      case MainMenuValue.dex:
        return LocaleKeys.swap.tr();
      case MainMenuValue.bridge:
        return LocaleKeys.bridge.tr();
      case MainMenuValue.card:
        return LocaleKeys.card.tr();
      case MainMenuValue.marketMakerBot:
        return LocaleKeys.tradingBot.tr();
      case MainMenuValue.nft:
        return LocaleKeys.nfts.tr();
      case MainMenuValue.settings:
        return LocaleKeys.settings.tr();
      case MainMenuValue.support:
        return LocaleKeys.support.tr();
      case MainMenuValue.more:
        return LocaleKeys.more.tr();
      case MainMenuValue.none:
        return '';
    }
  }

  bool get isNew {
    switch (this) {
      case MainMenuValue.wallet:
      case MainMenuValue.dex:
      case MainMenuValue.settings:
      case MainMenuValue.support:
      case MainMenuValue.none:
      case MainMenuValue.bridge:
      case MainMenuValue.more:
        return false;
      case MainMenuValue.card:
      case MainMenuValue.fiat:
      case MainMenuValue.marketMakerBot:
      case MainMenuValue.nft:
        return true;
    }
  }

  int get currentIndex {
    switch (this) {
      case MainMenuValue.wallet:
        return 0;
      case MainMenuValue.dex:
        return 1;
      case MainMenuValue.card:
        return 2;
      case MainMenuValue.fiat:
        return 3;
      case MainMenuValue.more:
        return 4;
      case MainMenuValue.bridge:
        return 5;
      case MainMenuValue.nft:
        return 6;
      case MainMenuValue.settings:
        return 7;
      case MainMenuValue.marketMakerBot:
        return 8;
      case MainMenuValue.support:
        return 9;
      case MainMenuValue.none:
        return 0;
    }
  }
}
