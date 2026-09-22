import 'dart:convert';

import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/model/withdraw_details/fee_details.dart';

class NftToken {
  NftToken({
    required this.chain,
    required this.tokenAddress,
    required this.tokenId,
    required this.amount,
    required this.ownerOf,
    required this.tokenHash,
    required this.blockNumber,
    required this.blockNumberMinted,
    required this.contractType,
    required this.collectionName,
    required this.symbol,
    required this.metaData,
    required this.lastTokenUriSync,
    required this.lastMetadataSync,
    required this.minterAddress,
    required this.possibleSpam,
    required this.uriMeta,
    required this.tokenUri,
  });

  final NftBlockchains chain;
  final String tokenAddress;
  final String tokenId;
  final String amount;
  final String ownerOf;
  final int blockNumber;
  final bool possibleSpam;
  final NftUriMeta uriMeta;
  final NftMetaData? metaData;
  final NftContractType contractType;
  final String? tokenHash;
  final int? blockNumberMinted;
  final String? collectionName;
  final String? symbol;
  final String? lastTokenUriSync;
  final String? lastMetadataSync;
  final String? minterAddress;
  final String? tokenUri;
  late final Coin parentCoin;

  static NftToken fromJson(dynamic json) {
    return NftToken(
      chain: NftBlockchains.fromApiResponse(json['chain']),
      tokenAddress: json['token_address'],
      tokenId: json['token_id'],
      amount: json['amount'],
      ownerOf: json['owner_of'],
      tokenHash: json['token_hash'],
      blockNumber: json['block_number'],
      blockNumberMinted: json['block_number_minted'],
      contractType: NftContractType.fromApiResponse(json['contract_type']),
      collectionName: json['name'],
      symbol: json['symbol'],
      metaData: json['metadata'] != null
          ? NftMetaData.fromJson(jsonDecode(json['metadata']))
          : null,
      lastTokenUriSync: json['last_token_uri_sync'],
      lastMetadataSync: json['last_metadata_sync'],
      minterAddress: json['minter_address'],
      possibleSpam: json['possible_spam'] ?? false,
      uriMeta: NftUriMeta.fromJson(json['uri_meta']),
      tokenUri: json['token_uri'],
    );
  }

  String get name => metaData?.name ?? uriMeta.tokenName ?? tokenId;
  String? get description => metaData?.description ?? uriMeta.description;
  String? get imageUrl {
    final image = uriMeta.imageUrl ?? metaData?.image ?? uriMeta.animationUrl;
    return image; // Return raw URL - bloc will handle normalization and fallbacks
  }

  String get uuid => '$chain:$tokenAddress:$tokenId'.hashCode.toString();

  CoinType get coinType {
    switch (chain) {
      case NftBlockchains.eth:
        return CoinType.erc20;
      case NftBlockchains.bsc:
        return CoinType.bep20;
      case NftBlockchains.avalanche:
        return CoinType.avx20;
      case NftBlockchains.polygon:
        return CoinType.plg20;
      case NftBlockchains.fantom:
        return CoinType.ftm20;
    }
  }
}

class NftUriMeta {
  const NftUriMeta({
    required this.tokenName,
    required this.description,
    required this.image,
    required this.attributes,
    required this.animationUrl,
    required this.imageUrl,
    required this.imageDetails,
    required this.externalUrl,
  });

  static NftUriMeta fromJson(Map<String, dynamic> json) {
    return NftUriMeta(
      animationUrl: json['animation_url'],
      attributes: json['attributes'],
      description: json['description'],
      image: json['image'],
      imageUrl: json['image_url'],
      tokenName: json['name'],
      imageDetails: json['image_details'],
      externalUrl: json['external_url'],
    );
  }

  final String? tokenName;
  final String? description;
  final String? image;
  final String? imageUrl;
  final dynamic attributes;
  final String? animationUrl;
  final Map<String, dynamic>? imageDetails;
  final String? externalUrl;
}

class NftMetaData {
  const NftMetaData({
    required this.name,
    required this.image,
    required this.description,
  });
  final String? name;
  final String? image;
  final String? description;

  static NftMetaData fromJson(Map<String, dynamic> json) {
    return NftMetaData(
      name: json['name'],
      image: json['image'],
      description: json['description'],
    );
  }
}

// Order is important
enum NftBlockchains {
  eth,
  polygon,
  bsc,
  avalanche,
  fantom;

  /// Chains the app offers NFT support for, in display order.
  ///
  /// Polygon is withheld: KDF hardcodes `Chain::Polygon` to the `MATIC` and
  /// `NFT_MATIC` tickers in `mm2src/coins/nft/nft_structs.rs`, so after the
  /// MATIC -> POL coins config rename neither ticker resolves — `POL` is
  /// rejected as an unsupported chain type and `NFT_MATIC` no longer names a
  /// coin. Drop the exclusion once KDF accepts `POL` / `NFT_POL`.
  static const List<NftBlockchains> supportedValues = [
    NftBlockchains.eth,
    NftBlockchains.bsc,
    NftBlockchains.avalanche,
    NftBlockchains.fantom,
  ];

  @override
  String toString() {
    switch (this) {
      case NftBlockchains.eth:
        return 'ETH';
      case NftBlockchains.bsc:
        return 'BNB';
      case NftBlockchains.avalanche:
        return 'Avalanche';
      case NftBlockchains.polygon:
        return 'Polygon';
      case NftBlockchains.fantom:
        return 'Fantom';
    }
  }

  static NftBlockchains? fromString(String chain) {
    switch (chain) {
      case 'ETH':
        return NftBlockchains.eth;
      case 'BSC':
        return NftBlockchains.bsc;
      case 'AVALANCHE':
        return NftBlockchains.avalanche;
      case 'POLYGON':
        return NftBlockchains.polygon;
      case 'FANTOM':
        return NftBlockchains.fantom;
      default:
        return null;
    }
  }

  static NftBlockchains fromApiResponse(String type) {
    switch (type) {
      case 'AVALANCHE':
        return NftBlockchains.avalanche;
      case 'BSC':
        return NftBlockchains.bsc;
      case 'ETH':
        return NftBlockchains.eth;
      case 'FANTOM':
        return NftBlockchains.fantom;
      case 'POLYGON':
        return NftBlockchains.polygon;
    }

    throw UnimplementedError();
  }

  String toApiRequest() {
    switch (this) {
      case NftBlockchains.eth:
        return 'ETH';
      case NftBlockchains.bsc:
        return 'BSC';
      case NftBlockchains.avalanche:
        return 'AVALANCHE';
      case NftBlockchains.polygon:
        return 'POLYGON';
      case NftBlockchains.fantom:
        return 'FANTOM';
    }
  }

  String coinAbbr() {
    switch (this) {
      case NftBlockchains.eth:
        return 'ETH';
      case NftBlockchains.bsc:
        return 'BNB';
      case NftBlockchains.avalanche:
        return 'AVAX';
      case NftBlockchains.polygon:
        return 'POL';
      case NftBlockchains.fantom:
        return 'FTM';
    }
  }

  String nftAssetTicker() {
    switch (this) {
      case NftBlockchains.eth:
        return 'NFT_ETH';
      case NftBlockchains.bsc:
        return 'NFT_BNB';
      case NftBlockchains.avalanche:
        return 'NFT_AVAX';
      case NftBlockchains.polygon:
        return 'NFT_POL';
      case NftBlockchains.fantom:
        return 'NFT_FTM';
    }
  }
}

enum NftContractType {
  erc1155,
  erc721;

  static NftContractType fromApiResponse(String type) {
    switch (type) {
      case 'ERC721':
        return NftContractType.erc721;
      case 'ERC1155':
        return NftContractType.erc1155;
    }
    throw Exception('There is no contract type');
  }

  String toWithdrawRequest() {
    switch (this) {
      case NftContractType.erc1155:
        return 'withdraw_erc1155';
      case NftContractType.erc721:
        return 'withdraw_erc721';
    }
  }
}

class NftTransactionDetails {
  NftTransactionDetails({
    required this.txHex,
    required this.txHash,
    required this.from,
    required this.to,
    required this.contractType,
    required this.tokenAddress,
    required this.tokenId,
    required this.amount,
    required this.feeDetails,
    required this.coin,
    required this.blockHeight,
    required this.timestamp,
    required this.internalId,
    required this.transactionType,
  });

  static NftTransactionDetails fromJson(Map<String, dynamic> json) {
    return NftTransactionDetails(
      txHex: json['tx_hex'],
      txHash: json['tx_hash'],
      coin: json['coin'],
      internalId: json['internal_id'] ?? 0,
      blockHeight: json['block_height'] ?? 0,
      timestamp: json['timestamp'],
      from: List.from(json['from']),
      to: List.from(json['to']),
      feeDetails: FeeDetails.fromJson(json['fee_details']),
      contractType: NftContractType.fromApiResponse(json['contract_type']),
      transactionType: json['transaction_type'],
      tokenAddress: json['token_address'],
      tokenId: json['token_id'] is List
          ? json['token_id'][0].toString()
          : json['token_id'].toString(),
      amount: json['amount'] is List
          ? json['amount'][0].toString()
          : json['amount'].toString(),
    );
  }

  final String txHex;
  final String txHash;
  final List<String> from;
  final List<String> to;
  final NftContractType contractType;
  final String tokenAddress;
  final String tokenId;
  final String amount;
  final FeeDetails feeDetails;
  final String coin;
  final int blockHeight;
  final int timestamp;
  final int internalId;
  final String transactionType;
}
