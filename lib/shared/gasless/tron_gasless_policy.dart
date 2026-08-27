import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/constants.dart';

/// Official recovery page for the selected TRON network.
///
/// Testnet custody must never be handed to the mainnet withdrawal flow (or the
/// reverse), even when ordinary GasFree receive entry points are disabled.
String tronGaslessRecoveryUrl({required bool isTestnet}) => isTestnet
    ? 'https://test.gasfree.io/withdraw'
    : 'https://gasfree.io/withdraw';

/// Applies Gleec's canonical token opt-in to the normalized SDK asset config.
///
/// Provider configuration, rather than the UI send/receive switches, controls
/// activation-time enrollment. This keeps KDF account status and recovery
/// available while either user-facing rail is paused.
JsonMap applyGleecTronGaslessActivationConfig(JsonMap config) =>
    configureGleecTronGaslessActivation(
      config,
      baseUrl: tronGaslessBaseUrl,
      serviceProvider: tronGaslessServiceProvider,
    );

/// Returns a fresh asset config with the documented KDF token opt-in when the
/// exact Gleec network/token identity is eligible.
///
/// An existing `gasless` key is authoritative and is never rewritten. That
/// preserves an explicit disable, an optional `transfer_max_fee`, and
/// fail-closed handling of malformed upstream configuration.
JsonMap configureGleecTronGaslessActivation(
  JsonMap config, {
  required String baseUrl,
  required String serviceProvider,
}) {
  final result = JsonMap.of(config);
  final networkPath = tronGaslessNetworkPath(baseUrl);
  final configuredAssetIds = tronGaslessRecoveryAssetIdsFor(
    baseUrl: baseUrl,
    serviceProvider: serviceProvider,
  );
  if (networkPath == null ||
      !configuredAssetIds.contains(config['coin']) ||
      config.containsKey('gasless') ||
      !isTronGaslessRawAssetConfigEligible(
        config,
        providerNetworkPath: networkPath,
      )) {
    return result;
  }

  result['gasless'] = <String, dynamic>{'enabled': true};
  return result;
}

/// Raw-config counterpart of [isTronGaslessAssetEligible].
///
/// This runs before [Asset] parsing, so it validates every identity field that
/// must not be inferred from a ticker: protocol, parent platform, testnet
/// marker, contract, custom-token marker, and canonical TRON derivation root.
bool isTronGaslessRawAssetConfigEligible(
  JsonMap config, {
  required String providerNetworkPath,
}) {
  final policy = _tronGaslessPolicyFor(providerNetworkPath);
  if (policy == null) return false;
  final protocol = config.valueOrNull<JsonMap>('protocol');
  final protocolData = protocol?.valueOrNull<JsonMap>('protocol_data');

  return config['coin'] == policy.ticker &&
      config['type'] == 'TRC-20' &&
      config['parent_coin'] == policy.platform &&
      config['is_custom_token'] != true &&
      config['is_testnet'] == policy.isTestnet &&
      config['derivation_path'] == "m/44'/195'" &&
      config['contract_address'] == policy.contractAddress &&
      protocol?['type'] == 'TRC20' &&
      protocolData?['platform'] == policy.platform &&
      protocolData?['contract_address'] == policy.contractAddress;
}

/// Whether the SDK currently considers the canonical GasFree receive rail
/// usable for [asset].
bool hasTronGaslessReceiveCapability(KomodoDefiSdk sdk, Asset asset) {
  try {
    return sdk.canReceiveGasless(asset);
  } catch (_) {
    return false;
  }
}

/// Validates the product's pinned provider and custody address against the
/// typed KDF account-status response.
///
/// KDF deliberately omits `service_provider` for `provider_unreachable`; every
/// response that does carry a provider must match the production pin exactly.
bool isPinnedTronGaslessAccountStatus(
  GaslessAccountStatusResponse status, {
  required String custodyAddress,
  required String expectedServiceProvider,
}) {
  final provider = status.serviceProvider;
  final expectedProvider = expectedServiceProvider.trim();
  if (expectedProvider.isEmpty ||
      (provider != null &&
          (provider.isEmpty || provider != expectedProvider))) {
    return false;
  }

  return custodyAddress.isNotEmpty &&
      custodyAddress == custodyAddress.trim() &&
      status.gasfreeAddress == custodyAddress;
}

/// Whether [status] authorizes a new GasFree deposit at [custodyAddress].
bool isVerifiedTronGaslessReceiveStatus(
  GaslessAccountStatusResponse status, {
  required String custodyAddress,
  required String expectedServiceProvider,
}) {
  if (status.availability != GaslessAccountAvailability.available) {
    return false;
  }
  final provider = status.serviceProvider;
  return provider != null &&
      provider.isNotEmpty &&
      isPinnedTronGaslessAccountStatus(
        status,
        custodyAddress: custodyAddress,
        expectedServiceProvider: expectedServiceProvider,
      );
}

/// Final app boundary for exposing or using a GasFree receive address.
///
/// A previous `ready` result is insufficient once the typed status is stale,
/// has changed, or the canonical custody address no longer matches. Every
/// receive surface calls this immediately before revealing, copying, or
/// passing the address to an integration.
bool isVerifiedTronGaslessReceive(
  KomodoDefiSdk sdk,
  Asset asset, {
  required bool capabilityReady,
  required GaslessAccountStatusResponse? accountStatus,
  required DateTime? accountStatusObservedAt,
  required String? verifiedAddress,
  required String? custodyAddress,
  required String expectedServiceProvider,
  DateTime? now,
}) {
  final verified = verifiedAddress;
  final custody = custodyAddress;
  final currentTime = (now ?? DateTime.now()).toUtc();
  final statusObservedAt = accountStatusObservedAt?.toUtc();
  if (!capabilityReady ||
      verified == null ||
      verified.isEmpty ||
      custody == null ||
      custody.isEmpty ||
      verified != verified.trim() ||
      custody != custody.trim() ||
      verified != custody ||
      statusObservedAt == null ||
      statusObservedAt.isAfter(currentTime) ||
      currentTime.difference(statusObservedAt) > const Duration(minutes: 1) ||
      accountStatus == null ||
      !isVerifiedTronGaslessReceiveStatus(
        accountStatus,
        custodyAddress: custody,
        expectedServiceProvider: expectedServiceProvider,
      )) {
    return false;
  }

  return hasTronGaslessReceiveCapability(sdk, asset);
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
  String? derivationPath,
  String? providerNetworkPath,
}) {
  if (id.subClass != CoinSubClass.trc20 || isCustomToken) return false;

  final policy = _tronGaslessPolicyFor(
    providerNetworkPath ?? tronGaslessNetworkPath(tronGaslessBaseUrl),
  );
  if (policy == null) return false;
  final configuredDerivationPath = derivationPath?.trim();
  return isTestnet == policy.isTestnet &&
      id.id == policy.ticker &&
      platform == policy.platform &&
      contractAddress == policy.contractAddress &&
      (configuredDerivationPath == null ||
          configuredDerivationPath == "m/44'/195'");
}

/// Identity-only check for SDK assets. This does not imply either rail is
/// enabled; use the send- or receive-specific configured-asset getter below
/// for the actual capability gate.
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
    derivationPath: asset.id.derivationPath,
    providerNetworkPath: providerNetworkPath,
  );
}

({String ticker, String platform, String contractAddress, bool isTestnet})?
_tronGaslessPolicyFor(String? providerNetworkPath) =>
    switch (providerNetworkPath) {
      'tron' => (
        ticker: 'USDT-TRC20',
        platform: 'TRX',
        contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        isTestnet: false,
      ),
      'nile' => (
        ticker: 'TESTUSDT-TRC20',
        platform: 'TRXT',
        contractAddress: 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
        isTestnet: true,
      ),
      _ => null,
    };

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
