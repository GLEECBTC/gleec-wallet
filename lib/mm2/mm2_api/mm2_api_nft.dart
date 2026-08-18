import 'dart:convert';

import 'package:http/http.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/mm2/mm2_api/rpc/errors.dart';
import 'package:web_dex/mm2/mm2_api/rpc/nft/get_nft_list/get_nft_list_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/nft/refresh_nft_metadata/refresh_nft_metadata_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/nft/update_nft/update_nft_req.dart';
import 'package:web_dex/mm2/mm2_api/rpc/nft/withdraw/withdraw_nft_request.dart';
import 'package:web_dex/mm2/rpc/nft_transaction/nft_transactions_request.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/shared/constants.dart';

class Mm2ApiNft {
  Mm2ApiNft(this.call);

  final Future<JsonMap> Function(dynamic) call;
  final _log = Logger('Mm2ApiNft');

  /// Dispose method for cleanup. Currently no-op as there are no resources to dispose.
  void dispose() {
    // No resources to dispose currently
  }

  Future<Map<String, dynamic>> updateNftList(
    List<NftBlockchains> chains,
  ) async {
    try {
      if (chains.isEmpty) {
        return {
          'error':
              'Please ensure an NFT chain is activated and patiently await '
              'while your NFTs are loaded.',
        };
      }
      final nftChains = chains.map((c) => c.toApiRequest()).toList();
      final request = UpdateNftRequest(chains: nftChains);

      return await call(request);
    } catch (e, s) {
      _log.shout('Error updating nfts', e, s);
      throw TransportError(message: e.toString());
    }
  }

  Future<Map<String, dynamic>> refreshNftMetadata({
    required String chain,
    required String tokenAddress,
    required String tokenId,
  }) async {
    try {
      final RefreshNftMetadataRequest request = RefreshNftMetadataRequest(
        chain: chain,
        tokenAddress: tokenAddress,
        tokenId: tokenId,
      );
      return await call(request);
    } catch (e, s) {
      _log.shout(e.toString(), e, s);
      throw TransportError(message: e.toString());
    }
  }

  Future<Map<String, dynamic>> getNftList(List<NftBlockchains> chains) async {
    try {
      if (chains.isEmpty) {
        return {
          'error':
              'Please ensure the NFT chain is activated and patiently await '
              'while your NFTs are loaded.',
        };
      }

      final nftChains = chains.map((c) => c.toApiRequest()).toList();
      final request = GetNftListRequest(chains: nftChains);
      final JsonMap json = await call(request);
      return json;
    } catch (e, s) {
      _log.shout('Error getting nft list', e, s);
      throw TransportError(message: e.toString());
    }
  }

  Future<Map<String, dynamic>> withdraw(WithdrawNftRequest request) async {
    try {
      return await call(request);
    } catch (e, s) {
      _log.shout('Error withdrawing nft', e, s);
      throw TransportError(message: e.toString());
    }
  }

  Future<Map<String, dynamic>> getNftTxs(
    NftTransactionsRequest request,
    bool withAdditionalInfo,
  ) async {
    try {
      final JsonMap json = await call(request);
      if (withAdditionalInfo) {
        final jsonUpdated = await const ProxyApiNft().addDetailsToTx(json);
        return jsonUpdated;
      }
      return json;
    } catch (e, s) {
      _log.shout('Error getting nft transactions', e, s);
      throw TransportError(message: e.toString());
    }
  }

  Future<Map<String, dynamic>> getNftTxDetails(
    NftTxDetailsRequest request,
  ) async {
    try {
      final additionalTxInfo = await const ProxyApiNft().getTxDetailsByHash(
        request.chain,
        request.txHash,
      );
      return additionalTxInfo;
    } catch (e, s) {
      _log.shout('Error getting nft tx details', e, s);
      throw TransportError(message: e.toString());
    }
  }

}

class ProxyApiNft {
  const ProxyApiNft();
  static const _errorBaseMessage = 'ProxyApiNft API: ';
  Future<Map<String, dynamic>> addDetailsToTx(Map<String, dynamic> json) async {
    final transactions = List<dynamic>.from(
      json['result']['transfer_history'] as List? ?? [],
    );
    final listOfAdditionalData = transactions
        .map(
          (tx) => {
            'blockchain': convertChainForProxy(tx['chain'] as String),
            'tx_hash': tx['transaction_hash'],
          },
        )
        .toList();

    final response = await Client().post(
      Uri.parse(txByHashUrl),
      body: jsonEncode(listOfAdditionalData),
    );
    final jsonBody = jsonDecode(response.body) as JsonMap;
    json['result']['transfer_history'] = transactions.map((element) {
      final txHash = element['transaction_hash'] as String?;
      final tx = jsonBody[txHash] as JsonMap?;
      if (tx != null) {
        element['confirmations'] = tx['confirmations'];
        element['fee_details'] = tx['fee_details'];
      }
      return element;
    }).toList();

    return json;
  }

  Future<Map<String, dynamic>> getTxDetailsByHash(
    String blockchain,
    String txHash,
  ) async {
    final listOfAdditionalData = [
      {'blockchain': convertChainForProxy(blockchain), 'tx_hash': txHash},
    ];
    final body = jsonEncode(listOfAdditionalData);
    try {
      final response = await Client().post(Uri.parse(txByHashUrl), body: body);
      final jsonBody = jsonDecode(response.body) as JsonMap;
      return jsonBody[txHash] as JsonMap;
    } catch (e) {
      throw Exception(_errorBaseMessage + e.toString());
    }
  }

  String convertChainForProxy(String chain) {
    switch (chain) {
      case 'AVALANCHE':
        return 'avx';
      case 'BSC':
        return 'bnb';
      case 'ETH':
        return 'eth';
      case 'FANTOM':
        return 'ftm';
      case 'POLYGON':
        return 'plg';
    }

    throw UnimplementedError();
  }
}
