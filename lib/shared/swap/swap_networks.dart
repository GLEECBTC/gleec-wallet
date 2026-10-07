import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Names the networks a swap touches, in the words a user knows them by.
///
/// The prototype's rule is that an asset is always shown with its network —
/// "USDC · Arbitrum" — because the same ticker on two networks is two
/// different assets.
class SwapNetworks {
  /// Creates the namer over the assets the wallet knows, which is how a route
  /// leg's EVM chain id is turned back into a name.
  SwapNetworks(Iterable<AssetId> knownAssets) {
    for (final asset in knownAssets) {
      if (asset.isChildAsset) continue;
      final chainId = asset.chainId;
      if (chainId is AssetChainId && _isEvm(asset.subClass)) {
        _byEvmChainId.putIfAbsent(chainId.chainId, () => asset);
      }
    }
  }

  final Map<int, AssetId> _byEvmChainId = {};

  /// The network [asset] lives on.
  String networkOf(AssetId asset) {
    // A token lives on its platform's network, which the token's own subclass
    // already names (ERC20 → Ethereum, PLG20 → Polygon, GRC20 → Gleec).
    if (asset.isChildAsset) {
      final parent = asset.parentId!;
      return _usesOwnName(asset.subClass) ? networkOf(parent) : _name(asset);
    }
    return _usesOwnName(asset.subClass) ? asset.name : _name(asset);
  }

  /// The network behind an EVM [chainId], when the wallet knows one.
  String? networkOfEvmChain(int? chainId) {
    if (chainId == null) return null;
    final asset = _byEvmChainId[chainId];
    return asset == null ? null : networkOf(asset);
  }

  /// The EVM chain id [asset] lives on, when it has one.
  static int? evmChainIdOf(AssetId asset) {
    final chainId = (asset.parentId ?? asset).chainId;
    return chainId is AssetChainId && _isEvm(asset.subClass)
        ? chainId.chainId
        : null;
  }

  String _name(AssetId asset) => asset.subClass.formatted;

  /// Subclasses whose formatted name is a protocol, not a network, so the
  /// coin's own name reads better ("Bitcoin", not "Native").
  static bool _usesOwnName(CoinSubClass subClass) => switch (subClass) {
    CoinSubClass.utxo ||
    CoinSubClass.smartChain ||
    CoinSubClass.tendermint ||
    CoinSubClass.tendermintToken ||
    CoinSubClass.sia ||
    CoinSubClass.zhtlc ||
    CoinSubClass.unknown => true,
    _ => false,
  };

  static bool _isEvm(CoinSubClass subClass) => switch (subClass) {
    CoinSubClass.erc20 ||
    CoinSubClass.bep20 ||
    CoinSubClass.polygon ||
    CoinSubClass.arbitrum ||
    CoinSubClass.base ||
    CoinSubClass.avx20 ||
    CoinSubClass.ftm20 ||
    CoinSubClass.moonbeam ||
    CoinSubClass.moonriver ||
    CoinSubClass.ethereumClassic ||
    CoinSubClass.ubiq ||
    CoinSubClass.krc20 ||
    CoinSubClass.ewt ||
    CoinSubClass.hrc20 ||
    CoinSubClass.hecoChain ||
    CoinSubClass.rskSmartBitcoin ||
    CoinSubClass.smartBch ||
    CoinSubClass.grc20 => true,
    _ => false,
  };
}
