import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart' show KomodoDefiSdk;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/shared/constants.dart';
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
  const _ReceiveCapabilitySdk(this.canReceive);

  final bool canReceive;

  @override
  bool canReceiveGasless(Asset asset) => canReceive;

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

void testTronGaslessPolicy() {
  group('TRON GasFree policy', () {
    test('build feature is fail-closed by default', () {
      expect(tronGaslessEnabled, isFalse);
      expect(tronGaslessReceiveEnabled, isFalse);
      expect(isTronGaslessConfigured, isFalse);
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
