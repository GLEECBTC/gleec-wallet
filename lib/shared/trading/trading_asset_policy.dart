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
    assetId != null && !isWalletOnlyTradingAssetId(assetId.id);

bool canTradeAssetPair(String base, String rel) =>
    !isWalletOnlyTradingAssetId(base) && !isWalletOnlyTradingAssetId(rel);
