import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/coin.dart';

/// An asset's name and, apart from it, the token standard it runs on.
///
/// The SDK's display name carries the standard only for a top-level coin,
/// "Gleec (GRC20)", while a token's omits it, so USDT on Ethereum and on TRON
/// both read "Tether". Here every asset gives its plain name, and the
/// standard goes in a chip beside it, written the same way for both: `ERC-20`.
({String name, String? network}) assetDisplayParts(Coin coin) {
  final standard = coin.id.subClass.tokenStandardSuffix;
  var network = standard?.replaceFirstMapped(
    _standard,
    (match) => '${match[1]}-${match[2]}',
  );
  if (coin.isTestCoin) network = network == null ? 'TEST' : '$network TEST';
  return (name: coin.id.name, network: network);
}

final _standard = RegExp(r'^([A-Z]{2,4})(\d{2})$');
