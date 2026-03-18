import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/custom_token_import/data/custom_token_import_repository.dart';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config({
  required String coin,
  required String contractAddress,
}) => {
  'coin': coin,
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {'platform': 'TRX', 'contract_address': contractAddress},
  },
  'contract_address': contractAddress,
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

class _StubCoinsRepo implements CoinsRepo {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(this._available);

  final Map<AssetId, Asset> _available;

  @override
  Map<AssetId, Asset> get available => _available;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({required this.client, required this.assets});

  @override
  final ApiClient client;

  @override
  final AssetManager assets;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeApiClient implements ApiClient {
  _FakeApiClient({
    required this.convertedContractAddress,
    required this.tokenSymbol,
    required this.decimals,
  });

  final String convertedContractAddress;
  final String tokenSymbol;
  final int decimals;
  int convertAddressCalls = 0;
  int getTokenInfoCalls = 0;
  Map<String, dynamic>? lastConvertAddressRequest;
  Map<String, dynamic>? lastGetTokenInfoRequest;

  @override
  FutureOr<Map<String, dynamic>> executeRpc(Map<String, dynamic> request) {
    final method = request['method'] as String?;
    switch (method) {
      case 'convertaddress':
        convertAddressCalls += 1;
        lastConvertAddressRequest = request;
        return {
          'mmrpc': '2.0',
          'result': {'address': convertedContractAddress},
        };
      case 'get_token_info':
        getTokenInfoCalls += 1;
        lastGetTokenInfoRequest = request;
        return {
          'mmrpc': '2.0',
          'result': {
            'type': request['params']['protocol']['type'],
            'info': {'symbol': tokenSymbol, 'decimals': decimals},
          },
        };
      default:
        throw UnsupportedError('Unexpected RPC method: $method');
    }
  }
}

class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._body);

  final String _body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = utf8.encode(_body);
    return http.StreamedResponse(
      Stream.value(bytes),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('KdfCustomTokenImportRepository', () {
    late Asset platformAsset;

    setUp(() {
      platformAsset = Asset.fromJson(_trxConfig(), knownIds: const {});
    });

    test('TRC20 fetch preserves selected protocol context end-to-end', () async {
      final apiClient = _FakeApiClient(
        convertedContractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        tokenSymbol: 'USDT',
        decimals: 6,
      );
      final repository = KdfCustomTokenImportRepository(
        _FakeSdk(
          client: apiClient,
          assets: _FakeAssetManager({platformAsset.id: platformAsset}),
        ),
        _StubCoinsRepo(),
        httpClient: _FakeHttpClient(
          jsonEncode({
            'id': 'tether',
            'name': 'Tether USD',
            'image': {'large': 'https://example.com/usdt.png'},
          }),
        ),
      );

      final asset = await repository.fetchCustomToken(
        network: CoinSubClass.trc20,
        platformAsset: platformAsset,
        address: '0x1234',
      );

      expect(asset.id.subClass, CoinSubClass.trc20);
      expect(asset.protocol, isA<Trc20Protocol>());
      expect(asset.id.parentId, platformAsset.id);
      expect(asset.id.id, 'USDT-TRC20');
      expect(
        asset.protocol.contractAddress,
        'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      );
      expect(
        apiClient.lastConvertAddressRequest?['coin'],
        equals(platformAsset.id.id),
      );
      expect(
        apiClient.lastGetTokenInfoRequest?['params']['protocol']['type'],
        equals('TRC20'),
      );
      expect(
        apiClient
            .lastGetTokenInfoRequest?['params']['protocol']['protocol_data']['platform'],
        equals('TRX'),
      );
    });

    test('same-contract re-import returns the existing known asset', () async {
      final existingAsset = Asset.fromJson(
        _trc20Config(
          coin: 'USDT-TRC20',
          contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        ),
        knownIds: {platformAsset.id},
      );
      final apiClient = _FakeApiClient(
        convertedContractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        tokenSymbol: 'USDT',
        decimals: 6,
      );
      final repository = KdfCustomTokenImportRepository(
        _FakeSdk(
          client: apiClient,
          assets: _FakeAssetManager({
            platformAsset.id: platformAsset,
            existingAsset.id: existingAsset,
          }),
        ),
        _StubCoinsRepo(),
        httpClient: _FakeHttpClient('{}'),
      );

      final asset = await repository.fetchCustomToken(
        network: CoinSubClass.trc20,
        platformAsset: platformAsset,
        address: '0x1234',
      );

      expect(asset, same(existingAsset));
      expect(apiClient.convertAddressCalls, 1);
      expect(apiClient.getTokenInfoCalls, 0);
    });

    test(
      'same generated asset id with different contract throws conflict',
      () async {
        final existingAsset = Asset.fromJson(
          _trc20Config(
            coin: 'USDT-TRC20',
            contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          ),
          knownIds: {platformAsset.id},
        );
        final repository = KdfCustomTokenImportRepository(
          _FakeSdk(
            client: _FakeApiClient(
              convertedContractAddress: 'TXLAQ63Xg1NAzckPwKHvzw7CSEmLMEqcdj',
              tokenSymbol: 'USDT',
              decimals: 6,
            ),
            assets: _FakeAssetManager({
              platformAsset.id: platformAsset,
              existingAsset.id: existingAsset,
            }),
          ),
          _StubCoinsRepo(),
          httpClient: _FakeHttpClient('{}'),
        );

        expect(
          repository.fetchCustomToken(
            network: CoinSubClass.trc20,
            platformAsset: platformAsset,
            address: '0x1234',
          ),
          throwsA(isA<CustomTokenConflictException>()),
        );
      },
    );
  });
}
