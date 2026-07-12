import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/constants.dart';

/// Whether KDF proved the bound-relay contract required for exposing a new
/// GasFree custody receive address.
///
/// Legacy PR #9 remains available for existing-custody send and recovery, but
/// its relay responses cannot bind a new deposit address strongly enough for
/// the receive surface. SDK lifecycle failures also fail closed here.
bool hasBoundTronGaslessReceiveCapability(KomodoDefiSdk sdk, Asset asset) {
  try {
    return sdk.canReceiveGasless(asset);
  } catch (_) {
    return false;
  }
}

/// Validates a TRC-20 identity against the provider network selected by the
/// build. Callers with only an [AssetId] must also supply protocol metadata so
/// ticker lookalikes and custom-token aliases cannot enter the GasFree rail.
bool isTronGaslessAssetIdEligible(
  AssetId id, {
  required bool isCustomToken,
  required bool isTestnet,
  required String? platform,
  required String? contractAddress,
  String? providerNetworkPath,
}) {
  if (id.subClass != CoinSubClass.trc20 || isCustomToken) return false;

  return switch (providerNetworkPath ??
      tronGaslessNetworkPath(tronGaslessBaseUrl)) {
    'tron' =>
      !isTestnet &&
          id.id == 'USDT-TRC20' &&
          platform == 'TRX' &&
          contractAddress == 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    'nile' =>
      isTestnet &&
          id.id == 'TESTUSDT-TRC20' &&
          platform == 'TRXT' &&
          contractAddress == 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
    _ => false,
  };
}

/// Identity-only check for SDK assets. This does not imply the build enabled
/// GasFree; use [TronGaslessAssetPolicy.isTronGaslessConfiguredAsset] for the
/// actual capability gate.
bool isTronGaslessAssetEligible(Asset asset, {String? providerNetworkPath}) {
  final config = asset.protocol.config;
  return isTronGaslessAssetIdEligible(
    asset.id,
    isCustomToken: asset.protocol.isCustomToken,
    isTestnet: asset.protocol.isTestnet,
    platform: config.valueOrNull<String>(
      'protocol',
      'protocol_data',
      'platform',
    ),
    contractAddress: asset.protocol.contractAddress,
    providerNetworkPath: providerNetworkPath,
  );
}

extension TronGaslessAssetPolicy on Asset {
  /// Authoritative app-side preflight before any GasFree status/preview RPC.
  bool get isTronGaslessConfiguredAsset =>
      isTronGaslessConfigured && isTronGaslessAssetEligible(this);

  /// Whether a new custody receive address may be presented for this asset.
  bool get isTronGaslessReceiveConfiguredAsset =>
      isTronGaslessReceiveConfigured && isTronGaslessAssetEligible(this);

  /// Whether this asset can have legacy/existing GasFree custody state that
  /// must remain visible for reconciliation and recovery.
  ///
  /// Unlike new send/receive capability, recovery deliberately ignores build
  /// kill switches and derives the provider network from the asset's own
  /// immutable testnet identity. Exact ticker/platform/contract/custom-token
  /// checks still apply.
  bool get isTronGaslessRecoveryEligibleAsset => isTronGaslessAssetEligible(
    this,
    providerNetworkPath: protocol.isTestnet ? 'nile' : 'tron',
  );
}
