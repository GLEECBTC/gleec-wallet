import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/app_config/app_config.dart';

/// Assets whose wallet balance may include funds held by the GasFree custody
/// contract. KDF's DEX settlement still spends from the Standard EOA, so these
/// assets must remain wallet-only until custody-aware settlement is supported.
const Set<String> gaslessCustodyBackedAssetIds = {
  'USDT-TRC20',
  'TESTUSDT-TRC20',
};

/// Shared execution policy for every DEX entry point.
///
/// This accepts the raw KDF asset id as well as [AssetId] so repositories can
/// enforce the same rule immediately before an RPC, even when no UI model is
/// available (deep links, restored bot settings, and order edits).
bool isWalletOnlyTradingAssetId(String assetId) {
  final normalized = assetId.trim().toUpperCase();
  return appWalletOnlyAssetList.any((id) => id.toUpperCase() == normalized) ||
      gaslessCustodyBackedAssetIds.contains(normalized);
}

bool canTradeAssetId(AssetId? assetId) =>
    assetId != null &&
    !isSolanaTradingAsset(assetId) &&
    !isWalletOnlyTradingAssetId(assetId.id);

bool canTradeAssetPair(String base, String rel) =>
    !isWalletOnlyTradingAssetId(base) &&
    !isWalletOnlyTradingAssetId(rel) &&
    !_isUnconfiguredSolana(base) &&
    !_isUnconfiguredSolana(rel);

bool isSolanaTradingAsset(AssetId asset) =>
    asset.subClass == CoinSubClass.solana ||
    asset.subClass == CoinSubClass.solanaToken;

// These retired preview names are never authorized for new trades, including
// when restored metadata still describes an otherwise valid devnet asset.
const _retiredSolanaTradingAssetIds = {'SOL-DEV', 'USDC-SOL-DEV'};

// Legacy callers without a catalog cannot authorize the preview assets. The
// injected policy below uses actual protocol metadata, never ticker inference.
// Retired preview names remain denial aliases for restored order requests.
bool _isUnconfiguredSolana(String id) => const {
  'SOL',
  'TESTSOL',
  'USDC-SOL',
  'TESTUSDC-TESTSOL',
  ..._retiredSolanaTradingAssetIds,
}.contains(id);

/// Live catalog and engine policy for starting trades. Cancellation, status
/// tracking and recovery deliberately do not use this policy.
class TradingAssetPolicy {
  TradingAssetPolicy({
    required Asset? Function(String id) assetOf,
    SolanaCapabilities Function()? solanaCapabilities,
    Set<String> curatedSolanaDevnetNodes = const {
      'https://api.devnet.solana.com',
    },
  }) : _assetOf = assetOf,
       _solanaCapabilities = solanaCapabilities ?? _disabledSolana,
       _curatedSolanaDevnetNodes = Set.unmodifiable(curatedSolanaDevnetNodes);

  final Asset? Function(String id) _assetOf;
  final SolanaCapabilities Function() _solanaCapabilities;
  final Set<String> _curatedSolanaDevnetNodes;

  static SolanaCapabilities _disabledSolana() => const SolanaCapabilities();

  bool allowsAsset(AssetId id) => allowsAssetId(id.id);

  bool allowsAssetId(String id) {
    if (_retiredSolanaTradingAssetIds.contains(id)) return false;
    if (isWalletOnlyTradingAssetId(id)) return false;
    final asset = _assetOf(id);
    if (asset == null || asset.isWalletOnly) return false;
    if (!isSolanaTradingAsset(asset.id)) return true;
    final capabilities = _solanaCapabilities();
    if (!capabilities.enabled || !capabilities.devnetTradingEnabled) {
      return false;
    }
    if (!asset.protocol.isTestnet) return false;
    final protocol = asset.protocol;
    if (protocol is SolanaTokenProtocol &&
        (protocol.programId != SolanaTokenProtocol.classicTokenProgramId ||
            asset.id.parentId?.id != protocol.platform)) {
      // Token-2022 trading needs its own acceptance coverage as well as
      // wallet transfer support; it is not enabled by listing a fixture.
      return false;
    }
    final platform = asset.id.parentId == null
        ? asset
        : _assetOf(asset.id.parentId!.id);
    if (platform == null ||
        platform.isWalletOnly ||
        !platform.protocol.isTestnet) {
      return false;
    }
    final platformProtocol = platform.protocol;
    return platformProtocol is SolanaProtocol &&
        platformProtocol.nodes.isNotEmpty &&
        platformProtocol.nodes.every(
          (node) => _curatedSolanaDevnetNodes.contains(node.url),
        );
  }

  bool isSolanaPair(String base, String rel) => [base, rel].any((id) {
    final asset = _assetOf(id);
    return asset != null && isSolanaTradingAsset(asset.id);
  });

  bool allowsPair(String base, String rel) {
    if (!allowsAssetId(base) || !allowsAssetId(rel)) return false;
    final from = _assetOf(base)!;
    final to = _assetOf(rel)!;
    if (isSolanaTradingAsset(from.id) || isSolanaTradingAsset(to.id)) {
      return from.protocol.isTestnet && to.protocol.isTestnet;
    }
    return true;
  }

  /// The engine creates/reprices bot orders after startup, outside the
  /// wallet's per-order funding checks. Solana automation needs independent
  /// engine acceptance for receiving-side funding and live policy changes.
  bool allowsMarketMakerPair(String base, String rel) =>
      allowsPair(base, rel) && !isSolanaPair(base, rel);

  void requirePair(String base, String rel) {
    if (!allowsPair(base, rel)) {
      throw StateError('Trading is unavailable for this asset pair.');
    }
  }
}

/// Atomic EVM tokens may need an allowance at payment time. This is disclosure
/// metadata, never a trading restriction or proof that approval is required.
bool isAtomicEvmToken(AssetId asset) =>
    asset.isChildAsset && evmCoinSubClasses.contains(asset.subClass);

/// A policy or funding check failed before any order reached the engine.
/// Transport failures deliberately do not use this exception.
class TradePreflightRejected implements Exception {
  const TradePreflightRejected(this.cause);
  final Object cause;
  @override
  String toString() => 'Trade preflight rejected: $cause';
}

/// Automated Solana orders need per-order engine funding acceptance first.
class SolanaMarketMakerUnavailable implements Exception {
  const SolanaMarketMakerUnavailable();

  @override
  String toString() => 'Solana market maker automation is unavailable';
}
