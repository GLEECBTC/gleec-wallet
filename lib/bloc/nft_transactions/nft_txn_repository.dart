import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api_nft.dart';
import 'package:web_dex/mm2/mm2_api/rpc/errors.dart';
import 'package:web_dex/mm2/rpc/nft_transaction/nft_transactions_request.dart';
import 'package:web_dex/mm2/rpc/nft_transaction/nft_transactions_response.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/model/withdraw_details/fee_details.dart';
import 'package:web_dex/shared/utils/utils.dart';

class NftTxnRepository {
  NftTxnRepository({required Mm2ApiNft api, required CoinsRepo coinsRepo})
      : _api = api,
        _coinsRepo = coinsRepo;
  final Mm2ApiNft _api;
  final CoinsRepo _coinsRepo;
  final Map<String, double?> _abbrToUsdPrices = {};
  Map<String, double?> get abbrToUsdPrices => _abbrToUsdPrices;

  Future<NftTxsResponse> getNftTransactions([
    List<NftBlockchains>? chains,
  ]) async {
    final List<String> allChains =
        (chains ?? NftBlockchains.values).map((e) => e.toApiRequest()).toList();
    await getUsdPricesOfCoins(
      (chains ?? NftBlockchains.values).map((e) => e.coinAbbr()),
    );
    final request = NftTransactionsRequest(
      chains: allChains,
      max: true,
    );

    try {
      final json = await _api.getNftTxs(request, false);
      if (json['error'] != null) {
        log(
          json['error'] as String,
          path: 'nft_main_repo => getNfts',
          isError: true,
        ).ignore();
        throw ApiError(message: json['error'] as String);
      }

      if (json['result'] == null) {
        throw ApiError(message: LocaleKeys.somethingWrong.tr());
      }
      try {
        final NftTxsResponse nftTransactionsResponse =
            NftTxsResponse.fromJson(json);

        return nftTransactionsResponse;
      } catch (e) {
        throw ParsingApiJsonError(message: e.toString());
      }
    } on TransportError catch (_) {
      rethrow;
    } on ApiError catch (_) {
      rethrow;
    } on ParsingApiJsonError catch (_) {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<NftTransaction> getNftTxDetailsByHash({
    required NftTransaction tx,
  }) async {
    try {
      final request = NftTxDetailsRequest(
        chain: tx.chain.toApiRequest(),
        txHash: tx.transactionHash,
      );
      final json = await _api.getNftTxDetails(request);
      try {
        tx.confirmations = json['confirmations'] ?? 0;
        tx.feeDetails = json['fee_details'] != null
            ? FeeDetails.fromJson(json['fee_details'])
            : FeeDetails.empty();
        tx.feeDetails?.setCoinUsdPrice(_abbrToUsdPrices[tx.chain.coinAbbr()]);

        return tx;
      } catch (e) {
        throw ParsingApiJsonError(message: e.toString());
      }
    } on TransportError catch (_) {
      rethrow;
    } on ApiError catch (_) {
      rethrow;
    } on ParsingApiJsonError catch (_) {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> getUsdPricesOfCoins(Iterable<String> coinAbbr) async {
    final coins = _coinsRepo.getKnownCoins();
    for (final abbr in coinAbbr) {
      // Total lookup: a ticker absent from the catalogue (FTM is, in the
      // bundled config) used to throw StateError and take the whole
      // transactions page down with it.
      final coin = coins.firstWhereOrNull((c) => c.abbr == abbr);
      if (coin == null) continue;
      _abbrToUsdPrices[abbr] = coin.usdPrice?.price?.toDouble();
    }
  }
}
