import 'package:komodo_defi_types/komodo_defi_types.dart';

/// The suffix `abbr2TickerWithSuffix` labels "(OLD)" elsewhere in the app.
final _legacySuffix = RegExp(r'[-_]OLD$', caseSensitive: false);

/// Whether [asset] is kept only for holders of a replaced token or chain,
/// such as USDC-PLG20_OLD, the bridged USDC.e on Polygon.
bool isLegacySwapAsset(AssetId asset) => _legacySuffix.hasMatch(asset.id);

/// The ticker a user knows [asset] by: "USDT", not "USDT-ERC20". A legacy
/// asset reads "USDC (OLD)": its config symbol is its successor's.
String swapTicker(AssetId asset) {
  final symbol = asset.symbol.configSymbol;
  if (!isLegacySwapAsset(asset)) return symbol;
  return '${symbol.replaceFirst(_legacySuffix, '')} (OLD)';
}
