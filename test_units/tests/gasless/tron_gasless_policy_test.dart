import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show GaslessReceiveEvidence, KomodoDefiSdk;
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_consolidation_gate.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/trading/trading_asset_policy.dart';

Map<String, dynamic> _trxConfig({bool testnet = false}) => {
  'coin': testnet ? 'TRXT' : 'TRX',
  'type': 'TRX',
  'name': testnet ? 'TRON Testnet' : 'TRON',
  'fname': testnet ? 'TRON Testnet' : 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'is_testnet': testnet,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': testnet ? 'Nile' : 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _usdtConfig({
  bool testnet = false,
  bool custom = false,
  String? contract,
}) {
  final parent = testnet ? 'TRXT' : 'TRX';
  final address =
      contract ??
      (testnet
          ? 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf'
          : 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
  return {
    'coin': testnet ? 'TESTUSDT-TRC20' : 'USDT-TRC20',
    'type': 'TRC-20',
    'name': testnet ? 'Tether Testnet' : 'Tether',
    'fname': testnet ? 'Tether Testnet' : 'Tether',
    'wallet_only': true,
    'is_custom_token': custom,
    'is_testnet': testnet,
    'mm2': 1,
    'decimals': 6,
    'derivation_path': "m/44'/195'",
    'contract_address': address,
    'parent_coin': parent,
    'protocol': {
      'type': 'TRC20',
      'protocol_data': {'platform': parent, 'contract_address': address},
    },
    'nodes': <Map<String, dynamic>>[],
  };
}

Asset _asset({bool testnet = false, bool custom = false, String? contract}) {
  final parent = Asset.fromJson(
    _trxConfig(testnet: testnet),
    knownIds: const {},
  );
  return Asset.fromJson(
    _usdtConfig(testnet: testnet, custom: custom, contract: contract),
    knownIds: {parent.id},
  );
}

class _ReceiveCapabilitySdk implements KomodoDefiSdk {
  const _ReceiveCapabilitySdk(
    this.canReceive, {
    this.statusAttested = false,
    this.evidence = GaslessReceiveEvidence.none,
  });

  final bool canReceive;
  final bool statusAttested;
  final GaslessReceiveEvidence evidence;

  @override
  bool canReceiveGasless(Asset asset) => canReceive;

  @override
  bool canReceiveGaslessFromStatus(Asset asset) => statusAttested;

  @override
  GaslessReceiveEvidence gaslessReceiveEvidence(Asset asset) => evidence;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnavailableReceiveCapabilitySdk implements KomodoDefiSdk {
  const _UnavailableReceiveCapabilitySdk();

  @override
  bool canReceiveGasless(Asset asset) => throw StateError('SDK unavailable');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CachedPubkeyManager implements PubkeyManager {
  const _CachedPubkeyManager(this.cached);

  final AssetPubkeys? cached;

  @override
  AssetPubkeys? lastKnown(AssetId assetId) =>
      cached?.assetId == assetId ? cached : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CachedReceiveCapabilitySdk implements KomodoDefiSdk {
  const _CachedReceiveCapabilitySdk({
    required this.pubkeys,
    required this.canReceive,
  });

  @override
  final PubkeyManager pubkeys;

  final bool canReceive;

  @override
  bool canReceiveGasless(Asset asset) => canReceive;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PubkeyInfo _gaslessPubkey({
  required String address,
  required String gasfreeAddress,
  required String? derivationPath,
  String? chain = 'external',
}) {
  return PubkeyInfo(
    address: address,
    derivationPath: derivationPath,
    chain: chain,
    balance: BalanceInfo.zero(),
    coinTicker: 'USDT-TRC20',
    gasfreeAddress: gasfreeAddress,
  );
}

AssetPubkeys _cachedPubkeys(Asset asset, List<PubkeyInfo> keys) {
  return AssetPubkeys(
    assetId: asset.id,
    keys: keys,
    availableAddressesCount: keys.length,
    syncStatus: SyncStatusEnum.success,
  );
}

void testTronGaslessPolicy() {
  group('TRON GasFree policy', () {
    test('build feature is fail-closed by default', () {
      expect(tronGaslessEnabled, isFalse);
      expect(tronGaslessReceiveEnabled, isFalse);
      expect(tronGaslessStatusAttestedReceiveEnabled, isFalse);
      expect(isTronGaslessConfigured, isFalse);
    });

    test('recovery route follows the custody network', () {
      expect(
        tronGaslessRecoveryUrl(isTestnet: false),
        'https://gasfree.io/withdraw',
      );
      expect(
        tronGaslessRecoveryUrl(isTestnet: true),
        'https://test.gasfree.io/withdraw',
      );
    });

    test('configuration rejects unsafe URLs and malformed provider pins', () {
      expect(
        tronGaslessNetworkPath('https://quicknode.gleec.com/gasfree/tron'),
        'tron',
      );
      expect(
        tronGaslessNetworkPath('https://quicknode.gleec.com/gasfree/nile'),
        'nile',
      );
      expect(tronGaslessNetworkPath('http://example.com/gasfree/tron'), isNull);
      expect(
        tronGaslessNetworkPath('https://user:secret@example.com/gasfree/tron'),
        isNull,
      );
      expect(
        isValidTronServiceProvider('TLntW9Z59LYY5KEi9cmwk3PKjQga828ird'),
        isTrue,
      );
      expect(isValidTronServiceProvider('not-a-tron-address'), isFalse);
    });

    test('SDK allowlist is exact and configuration-dependent', () {
      const provider = 'TLntW9Z59LYY5KEi9cmwk3PKjQga828ird';
      expect(
        tronGaslessAssetIdsFor(
          enabled: true,
          baseUrl: 'https://quicknode.gleec.com/gasfree/tron',
          serviceProvider: provider,
        ),
        {'USDT-TRC20'},
      );
      expect(
        tronGaslessAssetIdsFor(
          enabled: true,
          baseUrl: 'https://quicknode.gleec.com/gasfree/nile',
          serviceProvider: provider,
        ),
        {'TESTUSDT-TRC20'},
      );
      expect(
        tronGaslessAssetIdsFor(
          enabled: false,
          baseUrl: 'https://quicknode.gleec.com/gasfree/tron',
          serviceProvider: provider,
        ),
        isEmpty,
      );
      expect(
        tronGaslessRecoveryAssetIdsFor(
          baseUrl: 'https://quicknode.gleec.com/gasfree/tron',
          serviceProvider: provider,
        ),
        {'USDT-TRC20'},
      );
      expect(
        tronGaslessAssetIdsFor(
          enabled: true,
          baseUrl: 'https://quicknode.gleec.com/gasfree/tron',
          serviceProvider: 'invalid',
        ),
        isEmpty,
      );
    });

    test('accepts only the exact mainnet asset identity', () {
      expect(
        isTronGaslessAssetEligible(_asset(), providerNetworkPath: 'tron'),
        isTrue,
      );
      expect(
        isTronGaslessAssetEligible(_asset(), providerNetworkPath: 'nile'),
        isFalse,
      );
      expect(
        isTronGaslessAssetEligible(
          _asset(contract: 'TWrongContractAddress11111111111111'),
          providerNetworkPath: 'tron',
        ),
        isFalse,
      );
      expect(
        isTronGaslessAssetEligible(
          _asset(custom: true),
          providerNetworkPath: 'tron',
        ),
        isFalse,
      );
    });

    test('Nile asset cannot cross into the mainnet provider rail', () {
      expect(
        isTronGaslessAssetEligible(
          _asset(testnet: true),
          providerNetworkPath: 'nile',
        ),
        isTrue,
      );
      expect(
        isTronGaslessAssetEligible(
          _asset(testnet: true),
          providerNetworkPath: 'tron',
        ),
        isFalse,
      );
    });

    test('recovery eligibility survives disabled feature flags', () {
      expect(_asset().isTronGaslessRecoveryEligibleAsset, isTrue);
      expect(_asset(testnet: true).isTronGaslessRecoveryEligibleAsset, isTrue);
      expect(_asset(custom: true).isTronGaslessRecoveryEligibleAsset, isFalse);
      expect(
        _asset(
          contract: 'TWrongContractAddress11111111111111',
        ).isTronGaslessRecoveryEligibleAsset,
        isFalse,
      );
    });

    test('new receives require the SDK bound-relay capability', () {
      final asset = _asset();

      expect(
        hasBoundTronGaslessReceiveCapability(
          const _ReceiveCapabilitySdk(true),
          asset,
        ),
        isTrue,
      );
      expect(
        hasBoundTronGaslessReceiveCapability(
          const _ReceiveCapabilitySdk(false),
          asset,
        ),
        isFalse,
      );
      expect(
        hasBoundTronGaslessReceiveCapability(
          const _UnavailableReceiveCapabilitySdk(),
          asset,
        ),
        isFalse,
      );
    });

    test('wallet-only V1 evidence never satisfies the bound receive gate', () {
      final asset = _asset();
      const sdk = _ReceiveCapabilitySdk(
        false,
        statusAttested: true,
        evidence: GaslessReceiveEvidence.statusAttestedV1,
      );
      final now = DateTime.utc(2026, 7, 12, 12);

      expect(hasBoundTronGaslessReceiveCapability(sdk, asset), isFalse);
      expect(
        hasWalletTronGaslessReceiveCapability(
          sdk,
          asset,
          allowStatusAttestedV1: false,
        ),
        isFalse,
      );
      expect(
        hasWalletTronGaslessReceiveCapability(
          sdk,
          asset,
          allowStatusAttestedV1: true,
        ),
        isTrue,
      );
      expect(
        isVerifiedWalletTronGaslessReceive(
          sdk,
          asset,
          capabilityReady: true,
          verifiedAddress: 'TCanonicalGasFreeAddress00000000001',
          custodyAddress: 'TCanonicalGasFreeAddress00000000001',
          expiresAt: now.add(const Duration(minutes: 1)),
          now: now,
          allowStatusAttestedV1: true,
        ),
        isTrue,
      );
    });

    test('consolidation accepts only one cached canonical software key', () {
      final asset = _asset();
      const custody = 'TCanonicalGasFreeAddress00000000001';
      final canonical = _gaslessPubkey(
        address: 'TCanonicalStandardAddress0000000001',
        gasfreeAddress: custody,
        derivationPath: "m/44'/195'/0'/0/0",
      );
      final secondary = _gaslessPubkey(
        address: 'TSecondaryStandardAddress0000000001',
        gasfreeAddress: 'TSecondaryGasFreeAddress00000000001',
        derivationPath: "m/44'/195'/0'/0/1",
      );

      KomodoDefiSdk sdkFor(List<PubkeyInfo> keys) =>
          _CachedReceiveCapabilitySdk(
            pubkeys: _CachedPubkeyManager(_cachedPubkeys(asset, keys)),
            canReceive: true,
          );

      expect(
        cachedCanonicalTronGaslessCustodyAddress(
          sdkFor([canonical, secondary]),
          asset,
          walletType: WalletType.hdwallet,
        ),
        custody,
      );
      expect(
        cachedCanonicalTronGaslessCustodyAddress(
          sdkFor([secondary]),
          asset,
          walletType: WalletType.hdwallet,
        ),
        isNull,
      );
      expect(
        cachedCanonicalTronGaslessCustodyAddress(
          sdkFor([canonical]),
          asset,
          walletType: WalletType.trezor,
        ),
        isNull,
      );
      expect(
        cachedCanonicalTronGaslessCustodyAddress(
          sdkFor([canonical, canonical]),
          asset,
          walletType: WalletType.hdwallet,
        ),
        isNull,
      );
    });

    test('receive verifier requires bound, exact, and fresh context', () {
      final asset = _asset();
      const custody = 'TCanonicalGasFreeAddress00000000001';
      final now = DateTime.utc(2026, 7, 12, 12);
      final boundSdk = _CachedReceiveCapabilitySdk(
        pubkeys: const _CachedPubkeyManager(null),
        canReceive: true,
      );
      final unboundSdk = _CachedReceiveCapabilitySdk(
        pubkeys: const _CachedPubkeyManager(null),
        canReceive: false,
      );

      bool verify({
        KomodoDefiSdk? sdk,
        bool ready = true,
        String? verified = custody,
        String? candidate = custody,
        DateTime? expiresAt,
      }) => isVerifiedBoundTronGaslessReceive(
        sdk ?? boundSdk,
        asset,
        capabilityReady: ready,
        verifiedAddress: verified,
        custodyAddress: candidate,
        expiresAt: expiresAt ?? now.add(const Duration(minutes: 1)),
        now: now,
      );

      expect(verify(), isTrue);
      expect(verify(sdk: unboundSdk), isFalse);
      expect(verify(ready: false), isFalse);
      expect(verify(candidate: 'TDifferentCustodyAddress'), isFalse);
      expect(verify(expiresAt: now), isFalse);
      expect(
        isVerifiedBoundTronGaslessReceive(
          boundSdk,
          asset,
          capabilityReady: true,
          verifiedAddress: custody,
          custodyAddress: custody,
          expiresAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('canonical GasFree assets are denied at the shared DEX boundary', () {
      final state = TradingStatusLoadSuccess();
      expect(state.canTradeAssets([_asset().id]), isFalse);
      expect(state.canTradeAssets([_asset(testnet: true).id]), isFalse);
      expect(canTradeAssetPair('BTC', 'USDT-TRC20'), isFalse);
      expect(canTradeAssetPair('TESTUSDT-TRC20', 'KMD'), isFalse);
      expect(canTradeAssetPair('BTC', 'KMD'), isTrue);
    });
  });
}
