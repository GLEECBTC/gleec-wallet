import 'dart:async' show TimeoutException;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';

/// Abstraction for fetching and importing custom tokens.
///
/// Implementations should resolve token metadata and activate tokens so they
/// become available to the user within the wallet.
abstract class ICustomTokenImportRepository {
  /// Fetch an [Asset] for a custom token on [network] using [address] and the
  /// resolved parent [platformAsset].
  ///
  /// May return an existing known asset or construct a new one when absent.
  Future<Asset> fetchCustomToken({
    required CoinSubClass network,
    required Asset platformAsset,
    required String address,
  });

  /// Import the provided custom token [asset] into the wallet (e.g. activate it).
  Future<void> importCustomToken(Asset asset);

  /// Get the API name for the given coin subclass.
  String? getNetworkApiName(CoinSubClass coinType);

  /// Release any held resources.
  void dispose();
}

class KdfCustomTokenImportRepository implements ICustomTokenImportRepository {
  KdfCustomTokenImportRepository(
    this._kdfSdk,
    this._coinsRepo, {
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final CoinsRepo _coinsRepo;
  final KomodoDefiSdk _kdfSdk;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final _log = Logger('KdfCustomTokenImportRepository');

  @override
  Future<Asset> fetchCustomToken({
    required CoinSubClass network,
    required Asset platformAsset,
    required String address,
  }) async {
    _assertSupportedNetwork(network);
    _assertPlatformAsset(network, platformAsset);

    final convertAddressResponse = await _kdfSdk.client.rpc.address
        .convertAddress(
          from: address,
          coin: platformAsset.id.id,
          toFormat: AddressFormat.fromCoinSubClass(network),
        );
    final contractAddress = convertAddressResponse.address;
    final knownCoin = _findKnownAssetByContract(
      network: network,
      platformAsset: platformAsset,
      contractAddress: contractAddress,
    );
    if (knownCoin != null) {
      return knownCoin;
    }

    return _createNewCoin(
      contractAddress: contractAddress,
      network: network,
      platformAsset: platformAsset,
    );
  }

  Future<Asset> _createNewCoin({
    required String contractAddress,
    required CoinSubClass network,
    required Asset platformAsset,
  }) async {
    _log.info('Creating new coin for $contractAddress on $network');
    final response = await _kdfSdk.client.rpc.utility.getTokenInfo(
      contractAddress: contractAddress,
      platform: platformAsset.id.id,
      protocolType: _protocolTypeFor(network),
    );

    final platformConfig = platformAsset.protocol.config;
    final String ticker = response.info.symbol;
    final platformChainId = int.parse(
      platformAsset.id.chainId.formattedChainId,
    );
    final coinId = '$ticker-${network.tokenStandardSuffix}';
    final conflictingAsset = _findExistingAssetByGeneratedId(
      network: network,
      platformAsset: platformAsset,
      assetId: coinId,
    );
    if (conflictingAsset != null) {
      if (_hasMatchingContract(
        network: network,
        existingContractAddress: conflictingAsset.contractAddress,
        requestedContractAddress: contractAddress,
      )) {
        return conflictingAsset;
      }

      throw CustomTokenConflictException(
        assetId: coinId,
        network: network,
        existingContractAddress: conflictingAsset.contractAddress ?? '',
        requestedContractAddress: contractAddress,
      );
    }

    final tokenApi = await fetchTokenInfoFromApi(network, contractAddress);

    final String? logoImageUrl =
        tokenApi?['image']?['large'] ??
        tokenApi?['image']?['small'] ??
        tokenApi?['image']?['thumb'];

    _log.info('Creating new coin for $coinId on $network');
    final protocol = switch (network) {
      CoinSubClass.trc20 =>
        _buildTrc20Protocol(platformConfig).copyWithProtocolData(
          coin: coinId,
          type: network.tokenStandardSuffix,
          chainId: platformChainId,
          contractAddress: contractAddress,
          platform: network.ticker,
          logoImageUrl: logoImageUrl,
          isCustomToken: true,
        ),
      _ => Erc20Protocol.fromJson(platformConfig).copyWithProtocolData(
        coin: coinId,
        type: network.tokenStandardSuffix,
        chainId: platformChainId,
        contractAddress: contractAddress,
        platform: network.ticker,
        logoImageUrl: logoImageUrl,
        isCustomToken: true,
      ),
    };

    final newCoin = Asset(
      signMessagePrefix: null,
      id: AssetId(
        id: coinId,
        name: tokenApi?['name'] ?? ticker,
        symbol: AssetSymbol(
          assetConfigId: coinId,
          coinGeckoId: tokenApi?['id'],
          coinPaprikaId: tokenApi?['id'],
        ),
        chainId: platformAsset.id.chainId,
        subClass: network,
        derivationPath: platformAsset.id.derivationPath,
        parentId: platformAsset.id,
      ),
      isWalletOnly: false,
      protocol: protocol,
    );

    if (logoImageUrl != null && logoImageUrl.isNotEmpty) {
      AssetIcon.registerCustomIcon(newCoin.id, NetworkImage(logoImageUrl));
    }

    return newCoin;
  }

  void _assertSupportedNetwork(CoinSubClass network) {
    if (network.tokenStandardSuffix == null ||
        getNetworkApiName(network) == null) {
      throw UnsupportedCustomTokenNetworkException(network);
    }
  }

  void _assertPlatformAsset(CoinSubClass network, Asset platformAsset) {
    if (!platformAsset.id.subClass.canBeParentOf(network)) {
      throw ArgumentError.value(
        platformAsset.id,
        'platformAsset',
        'is not a valid parent for ${network.formatted} tokens',
      );
    }
  }

  String _protocolTypeFor(CoinSubClass network) {
    final protocolType = network.tokenStandardSuffix;
    if (protocolType == null) {
      throw UnsupportedCustomTokenNetworkException(network);
    }
    return protocolType;
  }

  Asset? _findKnownAssetByContract({
    required CoinSubClass network,
    required Asset platformAsset,
    required String contractAddress,
  }) {
    return _kdfSdk.assets.available.values.firstWhereOrNull(
      (asset) =>
          asset.id.subClass == network &&
          asset.id.parentId == platformAsset.id &&
          _hasMatchingContract(
            network: network,
            existingContractAddress: asset.contractAddress,
            requestedContractAddress: contractAddress,
          ),
    );
  }

  Asset? _findExistingAssetByGeneratedId({
    required CoinSubClass network,
    required Asset platformAsset,
    required String assetId,
  }) {
    return _kdfSdk.assets.available.values.firstWhereOrNull(
      (asset) =>
          asset.id.id == assetId &&
          asset.id.subClass == network &&
          asset.id.parentId == platformAsset.id &&
          asset.id.chainId.formattedChainId ==
              platformAsset.id.chainId.formattedChainId,
    );
  }

  bool _hasMatchingContract({
    required CoinSubClass network,
    required String? existingContractAddress,
    required String requestedContractAddress,
  }) {
    if (existingContractAddress == null) {
      return false;
    }

    return _normalizeContractAddress(
          network: network,
          contractAddress: existingContractAddress,
        ) ==
        _normalizeContractAddress(
          network: network,
          contractAddress: requestedContractAddress,
        );
  }

  String _normalizeContractAddress({
    required CoinSubClass network,
    required String contractAddress,
  }) {
    return network == CoinSubClass.trc20
        ? contractAddress
        : contractAddress.toLowerCase();
  }

  @override
  Future<void> importCustomToken(Asset asset) async {
    await _coinsRepo.activateAssetsSync([asset], maxRetryAttempts: 10);
  }

  Future<Map<String, dynamic>?> fetchTokenInfoFromApi(
    CoinSubClass coinType,
    String contractAddress, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final platform = getNetworkApiName(coinType);
    if (platform == null) {
      _log.warning('Unsupported Image URL Network: $coinType');
      return null;
    }

    final url = Uri.parse(
      'https://api.coingecko.com/api/v3/coins/$platform/'
      'contract/$contractAddress',
    );

    try {
      final response = await _httpClient
          .get(url)
          .timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException('Timeout fetching token data from $url');
            },
          );
      final data = jsonDecode(response.body);
      return data;
    } catch (e, s) {
      _log.severe('Error fetching token data from $url', e, s);
      return null;
    }
  }

  // TODO: when migrating to the API, change this to fetch the coingecko
  // asset_platforms: https://api.coingecko.com/api/v3/asset_platforms
  @override
  String? getNetworkApiName(CoinSubClass coinType) {
    switch (coinType) {
      case CoinSubClass.trc20:
        return 'tron'; // https://api.coingecko.com/api/v3/coins/tron/contract/TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t
      case CoinSubClass.erc20:
        return 'ethereum'; // https://api.coingecko.com/api/v3/coins/ethereum/contract/0x56072C95FAA701256059aa122697B133aDEd9279
      case CoinSubClass.bep20:
        return 'bsc'; // https://api.coingecko.com/api/v3/coins/bsc/contract/0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
      case CoinSubClass.arbitrum:
        // TODO: re-enable once the ticker->Asset issue is figured out
        // temporarily disabled to avoid confusion with failed activations
        return null;
      // return 'arbitrum-one'; // https://api.coingecko.com/api/v3/coins/arbitrum-one/contract/0xCBeb19549054CC0a6257A77736FC78C367216cE7
      case CoinSubClass.avx20:
        return 'avalanche'; // https://api.coingecko.com/api/v3/coins/avalanche/contract/0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E
      case CoinSubClass.moonriver:
        return 'moonriver'; // https://api.coingecko.com/api/v3/coins/moonriver/contract/0x0caE51e1032e8461f4806e26332c030E34De3aDb
      case CoinSubClass.matic:
        return 'polygon-pos'; // https://api.coingecko.com/api/v3/coins/polygon-pos/contract/0xdF7837DE1F2Fa4631D716CF2502f8b230F1dcc32
      case CoinSubClass.krc20:
        return 'kcc'; // https://api.coingecko.com/api/v3/coins/kcc/contract/0x0039f574ee5cc39bdd162e9a88e3eb1f111baf48
      case CoinSubClass.qrc20:
        return null; // Unable to find working url
      case CoinSubClass.ftm20:
        return null; // Unable to find working url
      case CoinSubClass.hecoChain:
        return null; // Unable to find working url
      case CoinSubClass.hrc20:
        return null; // Unable to find working url
      default:
        return null;
    }
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }
}

extension on Erc20Protocol {
  Erc20Protocol copyWithProtocolData({
    String? coin,
    String? type,
    String? contractAddress,
    String? platform,
    String? logoImageUrl,
    bool? isCustomToken,
    int? chainId,
  }) {
    final currentConfig = JsonMap.from(config);
    currentConfig.addAll({
      if (coin != null) 'coin': coin,
      if (type != null) 'type': type,
      if (chainId != null) 'chain_id': chainId,
      if (platform != null) 'parent_coin': platform,
      if (logoImageUrl != null) 'logo_image_url': logoImageUrl,
      if (isCustomToken != null) 'is_custom_token': isCustomToken,
      if (contractAddress != null) 'contract_address': contractAddress,
      if (contractAddress != null || platform != null)
        'protocol': {
          'protocol_data': {
            'contract_address': contractAddress ?? this.contractAddress,
            'platform': platform ?? subClass.ticker,
          },
        },
    });
    return Erc20Protocol.fromJson(currentConfig);
  }
}

Trc20Protocol _buildTrc20Protocol(JsonMap platformConfig) {
  final config = JsonMap.from(platformConfig);
  config['protocol'] = {
    'type': 'TRC20',
    'protocol_data': {
      'platform': config.valueOrNull<String>('coin') ?? CoinSubClass.trx.ticker,
      'contract_address': config.valueOrNull<String>('contract_address') ?? '',
    },
  };
  config['contract_address'] =
      config.valueOrNull<String>('contract_address') ?? '';
  return Trc20Protocol.fromJson(config);
}

extension on Trc20Protocol {
  Trc20Protocol copyWithProtocolData({
    String? coin,
    String? type,
    String? contractAddress,
    String? platform,
    String? logoImageUrl,
    bool? isCustomToken,
    int? chainId,
  }) {
    final currentConfig = JsonMap.from(config);
    currentConfig.addAll({
      if (coin != null) 'coin': coin,
      if (type != null) 'type': type,
      if (chainId != null) 'chain_id': chainId,
      if (platform != null) 'parent_coin': platform,
      if (logoImageUrl != null) 'logo_image_url': logoImageUrl,
      if (isCustomToken != null) 'is_custom_token': isCustomToken,
      if (contractAddress != null) 'contract_address': contractAddress,
      if (contractAddress != null || platform != null)
        'protocol': {
          'type': 'TRC20',
          'protocol_data': {
            'contract_address': contractAddress ?? this.contractAddress,
            'platform': platform ?? this.platform,
          },
        },
    });
    return Trc20Protocol.fromJson(currentConfig);
  }
}
