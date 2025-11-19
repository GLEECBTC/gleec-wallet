import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/model/coin_utils.dart';

/// Base class for all currencies
abstract class ICurrency {
  const ICurrency({
    required this.symbol,
    required this.name,
    required this.minPurchaseAmount,
  });

  /// The symbol/code of the currency (e.g. BTC, USD). Note that this usually
  /// excludes any chain identifiers like "-segwit" or "-erc20".
  final String symbol;

  /// The full name of the currency (e.g. Bitcoin, US Dollar).
  final String name;

  /// The minimum purchase amount for this currency. This is used to
  /// determine the minimum amount that can be purchased in a fiat
  /// transaction.
  final Decimal minPurchaseAmount;

  /// Returns true if the currency is a fiat currency (e.g. USD)
  bool get isFiat;

  /// Returns true if the currency is a crypto currency (e.g. BTC)
  bool get isCrypto;

  /// Returns the abbreviation of the currency (e.g. BTC, USD).
  String getAbbr() => symbol;

  // Returns the abbreviation of the currency without postfixes like "-segwit"
  String get configSymbol;

  /// Returns the full name of the currency (e.g. Bitcoin).
  String formatNameShort() => name;

  ICurrency copyWith({
    String? symbol,
    String? name,
    Decimal? minPurchaseAmount,
  });
}

class FiatCurrency extends ICurrency {
  const FiatCurrency({
    required super.symbol,
    required super.name,
    required super.minPurchaseAmount,
  });

  factory FiatCurrency.usd() => FiatCurrency(
    symbol: 'USD',
    name: 'United States Dollar',
    minPurchaseAmount: Decimal.zero,
  );

  @override
  bool get isFiat => true;

  @override
  bool get isCrypto => false;

  @override
  String get configSymbol => symbol;

  @override
  FiatCurrency copyWith({
    String? symbol,
    String? name,
    Decimal? minPurchaseAmount,
  }) {
    return FiatCurrency(
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      minPurchaseAmount: minPurchaseAmount ?? this.minPurchaseAmount,
    );
  }
}

class CryptoCurrency extends ICurrency {
  const CryptoCurrency({
    required super.symbol,
    required super.name,
    required this.chainType,
    required super.minPurchaseAmount,
  });

  factory CryptoCurrency.bitcoin() => CryptoCurrency(
    symbol: 'BTC-segwit',
    name: 'Bitcoin',
    chainType: CoinType.utxo,
    minPurchaseAmount: Decimal.zero,
  );

  factory CryptoCurrency.fromAsset(
    Asset asset, {
    required Decimal minPurchaseAmount,
  }) {
    final coin = asset.toCoin();
    return CryptoCurrency(
      symbol: coin.id.id,
      name: coin.displayName,
      chainType: coin.type,
      minPurchaseAmount: minPurchaseAmount,
    );
  }

  final CoinType chainType;

  @override
  bool get isFiat => false;

  @override
  bool get isCrypto => true;

  @override
  String get configSymbol => symbol.split('-')[0];

  @override
  String getAbbr() {
    // TODO: look into a better way to do this when migrating to the SDK
    // Providers return "ETH" with chain type "ERC20", resultning in abbr of
    // "ETH-ERC20", which is not how it is stored in our coins configuration
    // files. "ETH" is the expected abbreviation, which would just be `symbol`.
    if (chainType == CoinType.utxo ||
        chainType == CoinType.sia ||
        (chainType == CoinType.tendermint && symbol == 'ATOM') ||
        (chainType == CoinType.erc20 && symbol == 'ETH') ||
        (chainType == CoinType.bep20 && symbol == 'BNB') ||
        (chainType == CoinType.avx20 && symbol == 'AVAX') ||
        (chainType == CoinType.etc && symbol == 'ETC') ||
        (chainType == CoinType.ftm20 && symbol == 'FTM') ||
        (chainType == CoinType.arb20 && symbol == 'ARB') ||
        (chainType == CoinType.hrc20 && symbol == 'ONE') ||
        (chainType == CoinType.plg20 && symbol == 'MATIC') ||
        (chainType == CoinType.mvr20 && symbol == 'MOVR') ||
        (chainType == CoinType.krc20 && symbol == 'KCS')) {
      return symbol;
    }

    return '$symbol-${getCoinTypeName(chainType, symbol).replaceAll('-', '')}';
  }

  @override
  String formatNameShort() {
    final coinType = ' (${getCoinTypeName(chainType, symbol)})';
    return '$name$coinType';
  }

  Asset toAsset(KomodoDefiSdk sdk) {
    return sdk.getSdkAsset(getAbbr());
  }

  @override
  CryptoCurrency copyWith({
    String? symbol,
    String? name,
    CoinType? chainType,
    Decimal? minPurchaseAmount,
  }) {
    return CryptoCurrency(
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      chainType: chainType ?? this.chainType,
      minPurchaseAmount: minPurchaseAmount ?? this.minPurchaseAmount,
    );
  }
}
