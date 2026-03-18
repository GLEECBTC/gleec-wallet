import 'package:web_dex/model/first_uri_segment.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/router/state/bridge_section_state.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/fiat_state.dart';
import 'package:web_dex/router/state/market_maker_bot_state.dart';
import 'package:web_dex/router/state/nfts_state.dart';

abstract class AppRoutePath {
  final String location = '';
}

class WalletRoutePath implements AppRoutePath {
  WalletRoutePath.wallet() : location = '/${firstUriSegment.wallet}';

  WalletRoutePath.coinDetails(this.abbr)
    : location = '/${firstUriSegment.wallet}/${abbr.toLowerCase()}';
  WalletRoutePath.action(this.action)
    : location = '/${firstUriSegment.wallet}/$action';

  String abbr = '';
  String action = '';

  @override
  final String location;
}

class FiatRoutePath implements AppRoutePath {
  FiatRoutePath.fiat() : location = '/${firstUriSegment.fiat}', uuid = '';
  FiatRoutePath.swapDetails(this.action, this.uuid)
    : location = '/${firstUriSegment.fiat}/trading_details/$uuid';

  @override
  final String location;
  final String uuid;
  FiatAction action = FiatAction.none;
}

class DexRoutePath implements AppRoutePath {
  DexRoutePath.dex({
    this.fromCurrency = '',
    this.fromAmount = '',
    this.toCurrency = '',
    this.toAmount = '',
    this.orderType = '',
  }) : uuid = '';

  @override
  String get location {
    if (action == DexAction.tradingDetails) {
      return '/${firstUriSegment.dex}/trading_details/$uuid';
    }

    final List<String> queryParams = [];

    if (fromCurrency.isNotEmpty) queryParams.add('from_currency=$fromCurrency');
    if (fromAmount.isNotEmpty) queryParams.add('from_amount=$fromAmount');
    if (toCurrency.isNotEmpty) queryParams.add('to_currency=$toCurrency');
    if (toAmount.isNotEmpty) queryParams.add('to_amount=$toAmount');
    if (orderType.isNotEmpty) queryParams.add('order_type=$orderType');

    final String queryString = queryParams.isNotEmpty
        ? '?${queryParams.join('&')}'
        : '';
    return '/${firstUriSegment.dex}$queryString';
  }

  DexRoutePath.swapDetails(this.action, this.uuid)
    : fromCurrency = '',
      fromAmount = '',
      toCurrency = '',
      toAmount = '',
      orderType = '';

  final String uuid;
  DexAction action = DexAction.none;

  final String fromCurrency;
  final String fromAmount;
  final String toCurrency;
  final String toAmount;
  final String orderType;
}

class BridgeRoutePath implements AppRoutePath {
  BridgeRoutePath.bridge() : location = '/${firstUriSegment.bridge}', uuid = '';
  BridgeRoutePath.swapDetails(this.action, this.uuid)
    : location = '/${firstUriSegment.bridge}/trading_details/$uuid';

  @override
  final String location;
  final String uuid;
  BridgeAction action = BridgeAction.none;
}

class NftRoutePath implements AppRoutePath {
  NftRoutePath.nfts()
    : location = '/${firstUriSegment.nfts}',
      uuid = '',
      pageState = NFTSelectedState.none;
  NftRoutePath.nftDetails(this.uuid, bool isSend)
    : location = '/${firstUriSegment.nfts}/$uuid',
      pageState = isSend ? NFTSelectedState.send : NFTSelectedState.details;
  NftRoutePath.nftReceive()
    : location = '/${firstUriSegment.nfts}/receive',
      uuid = '',
      pageState = NFTSelectedState.receive;
  NftRoutePath.nftTransactions()
    : location = '/${firstUriSegment.nfts}/transactions',
      pageState = NFTSelectedState.transactions,
      uuid = '';

  @override
  final String location;
  final String uuid;
  final NFTSelectedState pageState;
}

class MarketMakerBotRoutePath implements AppRoutePath {
  MarketMakerBotRoutePath.marketMakerBot()
    : location = '/${firstUriSegment.marketMakerBot}',
      uuid = '';
  MarketMakerBotRoutePath.swapDetails(this.action, this.uuid)
    : location = '/${firstUriSegment.marketMakerBot}/trading_details/$uuid';

  @override
  final String location;
  final String uuid;
  MarketMakerBotAction action = MarketMakerBotAction.none;
}

class SettingsRoutePath implements AppRoutePath {
  SettingsRoutePath.root()
    : location = '/${firstUriSegment.settings}',
      selectedMenu = SettingsMenuValue.none;
  SettingsRoutePath.general()
    : location = '/${firstUriSegment.settings}/general',
      selectedMenu = SettingsMenuValue.general;
  SettingsRoutePath.security()
    : location = '/${firstUriSegment.settings}/security',
      selectedMenu = SettingsMenuValue.security;
  SettingsRoutePath.privacy()
    : location = '/${firstUriSegment.settings}/privacy',
      selectedMenu = SettingsMenuValue.privacy;
  SettingsRoutePath.kyc()
    : location = '/${firstUriSegment.settings}/kyc',
      selectedMenu = SettingsMenuValue.kycPolicy;
  SettingsRoutePath.passwordUpdate()
    : location = '/${firstUriSegment.settings}/security/passwordUpdate',
      selectedMenu = SettingsMenuValue.security;
  SettingsRoutePath.support()
    : location = '/${firstUriSegment.settings}/support',
      selectedMenu = SettingsMenuValue.support;
  SettingsRoutePath.feedback()
    : location = '/${firstUriSegment.settings}/feedback',
      selectedMenu = SettingsMenuValue.feedback;

  @override
  final String location;
  final SettingsMenuValue selectedMenu;
}
