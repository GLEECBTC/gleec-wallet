import 'package:web_dex/model/first_uri_segment.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/router/state/bridge_section_state.dart';
import 'package:web_dex/router/state/dex_state.dart';
import 'package:web_dex/router/state/fiat_state.dart';
import 'package:web_dex/router/state/market_maker_bot_state.dart';
import 'package:web_dex/router/state/nfts_state.dart';
import 'package:web_dex/router/state/unified_swap_section_state.dart';

abstract class AppRoutePath {
  final String location = '';
}

class UnifiedSwapRoutePath implements AppRoutePath {
  UnifiedSwapRoutePath._(this.route);

  factory UnifiedSwapRoutePath.swap({
    UnifiedSwapLegacyHints legacyHints = const UnifiedSwapLegacyHints(),
  }) => UnifiedSwapRoutePath._(
    UnifiedSwapRouteState.swap(legacyHints: legacyHints),
  );

  factory UnifiedSwapRoutePath.activity() =>
      UnifiedSwapRoutePath._(const UnifiedSwapRouteState.activity());

  factory UnifiedSwapRoutePath.activityDetails(String routeExecutionId) {
    final normalizedId = normalizeTradingEntityUuid(routeExecutionId);
    return normalizedId == null
        ? UnifiedSwapRoutePath.activity()
        : UnifiedSwapRoutePath._(
            UnifiedSwapRouteState.activityDetails(normalizedId),
          );
  }

  factory UnifiedSwapRoutePath.advanced({
    UnifiedSwapLegacyHints legacyHints = const UnifiedSwapLegacyHints(),
  }) => UnifiedSwapRoutePath._(
    UnifiedSwapRouteState.advanced(legacyHints: legacyHints),
  );

  final UnifiedSwapRouteState route;

  @override
  String get location {
    switch (route.destination) {
      case UnifiedSwapDestination.swap:
        return '/${firstUriSegment.swap}';
      case UnifiedSwapDestination.activity:
        return '/${firstUriSegment.activity}';
      case UnifiedSwapDestination.activityDetails:
        return '/${firstUriSegment.activity}/'
            '${Uri.encodeComponent(route.routeExecutionId!)}';
      case UnifiedSwapDestination.advanced:
        return '/${firstUriSegment.advanced}';
    }
  }
}

class CardRoutePath implements AppRoutePath {
  CardRoutePath.card() : location = '/${firstUriSegment.card}';

  @override
  final String location;
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
  }) : uuid = '',
       entityKind = DexTradingEntityKind.swap;

  @override
  String get location {
    if (action == DexAction.tradingDetails) {
      return '/${firstUriSegment.dex}/trading_details/${entityKind.name}/'
          '${Uri.encodeComponent(uuid)}';
    }

    final List<String> queryParams = [];

    void addParameter(String key, String value) {
      if (value.isNotEmpty) {
        queryParams.add('$key=${Uri.encodeQueryComponent(value)}');
      }
    }

    addParameter('from_currency', fromCurrency);
    addParameter('from_amount', fromAmount);
    addParameter('to_currency', toCurrency);
    addParameter('to_amount', toAmount);
    addParameter('order_type', orderType);

    final String queryString = queryParams.isNotEmpty
        ? '?${queryParams.join('&')}'
        : '';
    return '/${firstUriSegment.dex}$queryString';
  }

  DexRoutePath.swapDetails(
    DexAction action,
    String uuid, {
    this.entityKind = DexTradingEntityKind.swap,
  }) : action = normalizeTradingEntityUuid(uuid) == null
           ? DexAction.none
           : action,
       uuid = normalizeTradingEntityUuid(uuid) ?? '',
       fromCurrency = '',
       fromAmount = '',
       toCurrency = '',
       toAmount = '',
       orderType = '';

  final String uuid;
  DexAction action = DexAction.none;
  final DexTradingEntityKind entityKind;

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
