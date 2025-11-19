import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart' show Rational;
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/shared/utils/extensions/collection_extensions.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';

extension AssetCoinExtension on Asset {
  Coin toCoin() {
    // temporary measure to get metadata, like `wallet_only`, that isn't exposed
    // by the SDK (and might be phased out completely later on)
    // TODO: Remove this once the SDK exposes all the necessary metadata
    final config = protocol.config;
    final logoImageUrl = config.valueOrNull<String>('logo_image_url');
    final isCustomToken =
        (config.valueOrNull<bool>('is_custom_token') ?? false) ||
        logoImageUrl != null;

    final ProtocolData protocolData = ProtocolData(
      platform: id.parentId?.id ?? platform ?? '',
      contractAddress: contractAddress ?? '',
    );

    return Coin(
      type: protocol.subClass.toCoinType(),
      abbr: id.id,
      id: id,
      name: id.name,
      logoImageUrl: logoImageUrl ?? '',
      isCustomCoin: isCustomToken,
      explorerUrl: config.valueOrNull<String>('explorer_url') ?? '',
      explorerTxUrl: config.valueOrNull<String>('explorer_tx_url') ?? '',
      explorerAddressUrl:
          config.valueOrNull<String>('explorer_address_url') ?? '',
      protocolType: protocol.subClass.ticker,
      protocolData: protocolData,
      isTestCoin: protocol.isTestnet,
      coingeckoId: id.symbol.coinGeckoId,
      swapContractAddress: config.valueOrNull<String>('swap_contract_address'),
      fallbackSwapContract: config.valueOrNull<String>(
        'fallback_swap_contract',
      ),
      priority: priorityCoinsAbbrMap[id.id] ?? 0,
      state: CoinState.inactive,
      walletOnly: config.valueOrNull<bool>('wallet_only') ?? false,
      mode: id.isSegwit ? CoinMode.segwit : CoinMode.standard,
      derivationPath: id.derivationPath,
      decimals: id.chainId.decimals ?? 8,
    );
  }

  String? get contractAddress => protocol.config.valueOrNull(
    'protocol',
    'protocol_data',
    'contract_address',
  );
  String? get platform =>
      protocol.config.valueOrNull('protocol', 'protocol_data', 'platform');
}

extension CoinTypeExtension on CoinSubClass {
  CoinType toCoinType() {
    switch (this) {
      case CoinSubClass.base:
        return CoinType.base20;
      case CoinSubClass.ftm20:
        return CoinType.ftm20;
      case CoinSubClass.arbitrum:
        return CoinType.arb20;
      case CoinSubClass.slp:
        return CoinType.slp;
      case CoinSubClass.qrc20:
        return CoinType.qrc20;
      case CoinSubClass.avx20:
        return CoinType.avx20;
      case CoinSubClass.smartChain:
        return CoinType.smartChain;
      case CoinSubClass.sia:
        return CoinType.sia;
      case CoinSubClass.moonriver:
        return CoinType.mvr20;
      case CoinSubClass.ethereumClassic:
        return CoinType.etc;
      case CoinSubClass.hecoChain:
        return CoinType.hco20;
      case CoinSubClass.hrc20:
        return CoinType.hrc20;
      case CoinSubClass.tendermint:
        return CoinType.tendermint;
      case CoinSubClass.tendermintToken:
        return CoinType.tendermintToken;
      case CoinSubClass.ubiq:
        return CoinType.ubiq;
      case CoinSubClass.bep20:
        return CoinType.bep20;
      case CoinSubClass.matic:
        return CoinType.plg20;
      case CoinSubClass.utxo:
        return CoinType.utxo;
      case CoinSubClass.smartBch:
        return CoinType.sbch;
      case CoinSubClass.erc20:
        return CoinType.erc20;
      case CoinSubClass.krc20:
        return CoinType.krc20;
      case CoinSubClass.zhtlc:
        return CoinType.zhtlc;
      default:
        return CoinType.utxo;
    }
  }

  bool isEvmProtocol() {
    switch (this) {
      case CoinSubClass.base:
        return true;
      case CoinSubClass.avx20:
      case CoinSubClass.bep20:
      case CoinSubClass.ftm20:
      case CoinSubClass.matic:
      case CoinSubClass.hrc20:
      case CoinSubClass.arbitrum:
      case CoinSubClass.moonriver:
      case CoinSubClass.moonbeam:
      case CoinSubClass.ethereumClassic:
      case CoinSubClass.ubiq:
      case CoinSubClass.krc20:
      case CoinSubClass.ewt:
      case CoinSubClass.hecoChain:
      case CoinSubClass.rskSmartBitcoin:
      case CoinSubClass.erc20:
        return true;
      default:
        return false;
    }
  }
}

extension CoinSubClassExtension on CoinType {
  CoinSubClass toCoinSubClass() {
    switch (this) {
      case CoinType.base20:
        return CoinSubClass.base;
      case CoinType.ftm20:
        return CoinSubClass.ftm20;
      case CoinType.arb20:
        return CoinSubClass.arbitrum;
      case CoinType.slp:
        return CoinSubClass.slp;
      case CoinType.qrc20:
        return CoinSubClass.qrc20;
      case CoinType.avx20:
        return CoinSubClass.avx20;
      case CoinType.smartChain:
        return CoinSubClass.smartChain;
      case CoinType.sia:
        return CoinSubClass.sia;
      case CoinType.mvr20:
        return CoinSubClass.moonriver;
      case CoinType.etc:
        return CoinSubClass.ethereumClassic;
      case CoinType.hco20:
        return CoinSubClass.hecoChain;
      case CoinType.hrc20:
        return CoinSubClass.hrc20;
      case CoinType.tendermint:
        return CoinSubClass.tendermint;
      case CoinType.tendermintToken:
        return CoinSubClass.tendermintToken;
      case CoinType.ubiq:
        return CoinSubClass.ubiq;
      case CoinType.bep20:
        return CoinSubClass.bep20;
      case CoinType.plg20:
        return CoinSubClass.matic;
      case CoinType.utxo:
        return CoinSubClass.utxo;
      case CoinType.sbch:
        return CoinSubClass.smartBch;
      case CoinType.erc20:
        return CoinSubClass.erc20;
      case CoinType.krc20:
        return CoinSubClass.krc20;
      case CoinType.zhtlc:
        return CoinSubClass.zhtlc;
    }
  }
}

/// Extension methods to help bridging the gap between legacy [Coin] and SDK [Asset] objects
extension SdkAssetExtension on KomodoDefiSdk {
  /// Get the SDK Asset corresponding to a coin's ticker symbol
  Asset getSdkAsset(String abbr) {
    final assets = this.assets;

    // Find the asset with the matching ticker symbol
    // This could be refined based on your specific use case
    try {
      return assets.findAssetsByConfigId(abbr).single;
    } catch (e) {
      throw ArgumentError('Could not find SDK asset for $abbr');
    }
  }
}

/// Helper function to get an SDK Asset from a ticker abbr
Asset getSdkAsset(KomodoDefiSdk sdk, String abbr) => sdk.getSdkAsset(abbr);

/// Extension methods to help access Asset data from a Coin
extension AssetBalanceExtension on Coin {
  /// Get the current balance for this coin from the SDK
  Future<BalanceInfo> getBalance(KomodoDefiSdk sdk) async {
    return await sdk.balances.getBalance(id);
  }

  /// Get a stream of balance updates for this coin
  Stream<BalanceInfo> watchBalance(
    KomodoDefiSdk sdk, {
    bool activateIfNeeded = true,
  }) {
    return sdk.balances.watchBalance(id, activateIfNeeded: activateIfNeeded);
  }

  /// Get the last-known balance for this coin.
  ///
  /// Note: Prefer using [getBalance] or [watchBalance] for real-time updates.
  BalanceInfo? lastKnownBalance(KomodoDefiSdk sdk) =>
      sdk.balances.lastKnown(id);

  /// Get the price for this coin
  Future<Decimal?> getPrice(KomodoDefiSdk sdk) {
    return sdk.marketData.maybeFiatPrice(id);
  }

  double? usdBalance(KomodoDefiSdk sdk) {
    final balance = sdk.balances.lastKnown(id);
    if (balance == null) return null;
    if (balance.spendable == Decimal.zero) return 0.0;
    final price = sdk.marketData.priceIfKnown(id);
    if (price == null) return null;
    return (balance * price).spendable.toDouble();
  }
}

extension CoinSupportOps on Iterable<Coin> {
  /// Returns a list excluding test coins. Useful when filtering coins before
  /// running portfolio calculations that assume production assets only.
  List<Coin> withoutTestCoins() =>
      where((coin) => !coin.isTestCoin).unmodifiable().toList();

  /// Filters out unsupported coins by first removing test coins and then
  /// evaluating the optional [isSupported] predicate. When the predicate is not
  /// provided, only test coins are removed.
  Future<List<Coin>> filterSupportedCoins([
    Future<bool> Function(Coin coin)? isSupported,
  ]) async {
    final predicate = isSupported ?? _alwaysSupported;
    final supportedCoins = <Coin>[];
    for (final coin in this) {
      if (coin.isTestCoin) continue;
      if (await predicate(coin)) {
        supportedCoins.add(coin);
      }
    }
    return supportedCoins.unmodifiable().toList();
  }

  static Future<bool> _alwaysSupported(Coin _) async => true;

  Future<List<Coin>> removeInactiveCoins(KomodoDefiSdk sdk) async {
    final activeIds = await sdk.activatedAssetsCache.getActivatedAssetIds();

    return where((coin) => activeIds.contains(coin.id)).unmodifiable().toList();
  }

  Future<List<Coin>> removeActiveCoins(KomodoDefiSdk sdk) async {
    final activeIds = await sdk.activatedAssetsCache.getActivatedAssetIds();

    return where(
      (coin) => !activeIds.contains(coin.id),
    ).unmodifiable().toList();
  }

  double totalLastKnownUsdBalance(KomodoDefiSdk sdk) {
    double total = fold<double>(
      0.00,
      (prev, coin) => prev + (coin.lastKnownUsdBalance(sdk) ?? 0),
    );

    // Return at least 0.01 if total is positive but very small
    if (total > 0 && total < 0.01) {
      return 0.01;
    }

    return total;
  }

  Future<Rational> totalChange24h(KomodoDefiSdk sdk) async {
    Rational totalChange = Rational.zero;
    for (final coin in this) {
      final double usdBalance = coin.lastKnownUsdBalance(sdk) ?? 0.0;
      final usdBalanceDecimal = Decimal.parse(usdBalance.toString());
      final change24h =
          await sdk.marketData.priceChange24h(coin.id) ?? Decimal.zero;
      totalChange += change24h * usdBalanceDecimal / Decimal.fromInt(100);
    }
    return totalChange;
  }

  Future<Rational> percentageChange24h(KomodoDefiSdk sdk) async {
    final double totalBalance = totalLastKnownUsdBalance(sdk);
    final Rational totalBalanceRational = Rational.parse(
      totalBalance.toString(),
    );
    final Rational totalChange = await totalChange24h(sdk);

    // Avoid division by zero or very small balances
    if (totalBalanceRational <= Rational.fromInt(1, 100)) {
      return Rational.zero;
    }

    // Return the percentage change
    return (totalChange / totalBalanceRational) * Rational.fromInt(100);
  }
}
