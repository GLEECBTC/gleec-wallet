import 'package:flutter/material.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/first_uri_segment.dart';
import 'package:web_dex/router/parsers/base_route_parser.dart';
import 'package:web_dex/router/parsers/bridge_route_parser.dart';
import 'package:web_dex/router/parsers/card_route_parser.dart';
import 'package:web_dex/router/parsers/dex_route_parser.dart';
import 'package:web_dex/router/parsers/fiat_route_parser.dart';
import 'package:web_dex/router/parsers/nft_route_parser.dart';
import 'package:web_dex/router/parsers/settings_route_parser.dart';
import 'package:web_dex/router/parsers/wallet_route_parser.dart';
import 'package:web_dex/router/routes.dart';

class RootRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  RootRouteInformationParser(this.coinsBloc);

  final CoinsBloc coinsBloc;

  Map<String, BaseRouteParser> get _parsers => {
    firstUriSegment.wallet: WalletRouteParser(coinsBloc),
    firstUriSegment.fiat: fiatRouteParser,
    firstUriSegment.dex: dexRouteParser,
    firstUriSegment.bridge: bridgeRouteParser,
    firstUriSegment.card: cardRouteParser,
    firstUriSegment.nfts: nftRouteParser,
    firstUriSegment.settings: settingsRouteParser,
  };

  @override
  Future<AppRoutePath> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final BaseRouteParser parser = _getRoutParser(
      Uri.parse(routeInformation.uri.path),
    );

    return parser.getRoutePath(routeInformation.uri);
  }

  @override
  RouteInformation restoreRouteInformation(AppRoutePath configuration) {
    return RouteInformation(uri: Uri.parse(configuration.location));
  }

  BaseRouteParser _getRoutParser(Uri uri) {
    final defaultRouteParser =
        dexRouteParser.handlesDeepLinkParameters(uri.queryParameters.keys)
        ? dexRouteParser
        : WalletRouteParser(coinsBloc);

    if (uri.pathSegments.isEmpty) return defaultRouteParser;
    return _parsers[uri.pathSegments.first] ?? defaultRouteParser;
  }
}
