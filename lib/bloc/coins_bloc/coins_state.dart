part of 'coins_bloc.dart';

class CoinsState extends Equatable {
  /// The list of available and activated assets to be displayed in the app.
  /// This list is filtered to exclude assets not intended to be shown to the
  /// user. E.g. NFT assets.
  CoinsState({
    required Map<String, Coin> coins,
    required Map<String, Coin> walletCoins,
    required this.pubkeys,
    required this.prices,
  }) : coins = _filterExcludedAssets(coins),
       walletCoins = _filterExcludedAssets(walletCoins);

  factory CoinsState.initial() => CoinsState(
    coins: const {},
    walletCoins: const {},
    pubkeys: const {},
    prices: const {},
  );

  final Map<String, Coin> coins;
  final Map<String, Coin> walletCoins;
  final Map<String, AssetPubkeys> pubkeys;
  final Map<String, CexPrice> prices;

  @override
  List<Object> get props => [coins, walletCoins, pubkeys, prices];

  /// Creates a copy of the current state with the option to update
  /// specific fields.
  /// NOTE: This method filters the coins and walletCoins maps to exclude
  /// assets that should not be shown to the user.
  CoinsState copyWith({
    Map<String, Coin>? coins,
    Map<String, Coin>? walletCoins,
    Map<String, AssetPubkeys>? pubkeys,
    Map<String, CexPrice>? prices,
  }) {
    // Filtering is required to avoid including "NFT_*" assets in the coins
    // or walletCoins maps. The user should not see these assets, as they are
    // only needed to support the NFT feature.
    final walletCoinsWithoutExcludedCoins = _filterExcludedAssets(
      walletCoins ?? this.walletCoins,
    );
    final coinsWithoutExcludedCoins = _filterExcludedAssets(
      coins ?? this.coins,
    );

    return CoinsState(
      coins: coinsWithoutExcludedCoins,
      walletCoins: walletCoinsWithoutExcludedCoins,
      pubkeys: pubkeys ?? this.pubkeys,
      prices: prices ?? this.prices,
    );
  }

  static Map<String, Coin> _filterExcludedAssets(Map<String, Coin> coins) {
    return Map.fromEntries(
      coins.entries.where((entry) {
        final coinId = entry.key;
        return !excludedAssetList.contains(coinId);
      }),
    );
  }

  /// CEX quote for [assetId] from [prices] (keys: uppercased [AssetSymbol.configSymbol]).
  ///
  /// Distinct from [KomodoDefiSdk.marketData] spot pricing: wallet chrome totals use this
  /// feed with SDK balances (`computeWalletTotalUsd`); sorting and portfolio growth may
  /// still use SDK prices until a single pricing path exists.
  CexPrice? getPriceForAsset(AssetId assetId) {
    return prices[assetId.symbol.configSymbol.toUpperCase()];
  }

  /// Gets the 24h price change percentage for a given asset ID
  double? get24hChangeForAsset(AssetId assetId) {
    return getPriceForAsset(assetId)?.change24h?.toDouble();
  }

  /// Calculates the USD price for a given amount of a coin
  ///
  /// [amount] The amount of the coin as a string
  /// [coinAbbr] The abbreviation/symbol of the coin
  ///
  /// Returns null if:
  /// - The coin is not found in the state
  /// - The amount cannot be parsed to a double
  /// - The coin does not have a USD price
  ///
  /// Note: This will be migrated to use the SDK's price functionality in the future.
  /// See the MarketDataManager in the SDK for the new implementation.
  @Deprecated('Use sdk.prices.fiatPrice(assetId) * amount instead')
  double? getUsdPriceByAmount(String amount, String coinAbbr) {
    final Coin? coin = coins[coinAbbr];
    final double? parsedAmount = double.tryParse(amount);
    final CexPrice? cexPrice = prices[coinAbbr.toUpperCase()];
    final double? usdPrice = cexPrice?.price?.toDouble();

    if (coin == null || usdPrice == null || parsedAmount == null) {
      return null;
    }
    return parsedAmount * usdPrice;
  }
}
