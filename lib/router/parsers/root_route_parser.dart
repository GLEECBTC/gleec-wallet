import 'package:flutter/material.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/first_uri_segment.dart';
import 'package:web_dex/router/parsers/base_route_parser.dart';
import 'package:web_dex/router/parsers/dex_route_parser.dart';
import 'package:web_dex/router/parsers/fiat_route_parser.dart';
import 'package:web_dex/router/parsers/nft_route_parser.dart';
import 'package:web_dex/router/parsers/settings_route_parser.dart';
import 'package:web_dex/router/parsers/wallet_route_parser.dart';
import 'package:web_dex/router/routes.dart';

class RootRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  RootRouteInformationParser(this.coinsBloc);

  final CoinsBloc coinsBloc;

  /// The `/swap` address the browser last opened, and the `/dex` address it
  /// stands for. While the app stays there, it reports the address back as
  /// the browser has it: a different one would add a history entry, so Back
  /// to `/swap` would add `/dex` again and never get further.
  ({Uri alias, String location})? _alias;

  Map<String, BaseRouteParser> get _parsers => {
    firstUriSegment.wallet: WalletRouteParser(coinsBloc),
    firstUriSegment.fiat: fiatRouteParser,
    firstUriSegment.dex: dexRouteParser,
    firstUriSegment.swap: dexRouteParser,
    firstUriSegment.nfts: nftRouteParser,
    firstUriSegment.settings: settingsRouteParser,
  };

  @override
  Future<AppRoutePath> parseRouteInformation(
    RouteInformation routeInformation,
  ) async {
    final uri = routeInformation.uri;
    final BaseRouteParser parser = _getRoutParser(Uri.parse(uri.path));

    final path = parser.getRoutePath(uri);
    final segments = uri.pathSegments;
    _alias = segments.isNotEmpty && segments.first == firstUriSegment.swap
        ? (alias: uri, location: path.location)
        : null;
    return path;
  }

  @override
  RouteInformation restoreRouteInformation(AppRoutePath configuration) {
    final location = configuration.location;
    // Kept until the browser opens another address: the app asks for its
    // address as each part of a route is applied, not only once it settles.
    final alias = _alias;
    if (alias != null && alias.location == location) {
      return RouteInformation(uri: alias.alias);
    }
    return RouteInformation(uri: Uri.parse(location));
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
