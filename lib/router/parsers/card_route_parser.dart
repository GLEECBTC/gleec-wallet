import 'package:web_dex/router/parsers/base_route_parser.dart';
import 'package:web_dex/router/routes.dart';

class _CardRouteParser implements BaseRouteParser {
  const _CardRouteParser();

  @override
  AppRoutePath getRoutePath(Uri uri) => CardRoutePath.card();
}

const cardRouteParser = _CardRouteParser();
