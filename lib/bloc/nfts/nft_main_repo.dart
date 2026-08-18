import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api_nft.dart';
import 'package:web_dex/mm2/mm2_api/rpc/errors.dart';
import 'package:web_dex/mm2/mm2_api/rpc/nft/get_nft_list/get_nft_list_res.dart';
import 'package:web_dex/model/coin.dart' show Coin;
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/model/text_error.dart';

class NftsRepo {
  NftsRepo({required Mm2ApiNft api, required CoinsRepo coinsRepo})
    : _coinsRepo = coinsRepo,
      _api = api;

  final Logger _log = Logger('NftsRepo');
  final CoinsRepo _coinsRepo;
  final Mm2ApiNft _api;

  Future<void> updateNft(List<NftBlockchains> chains) async {
    // Filter to only chains whose parent coins are already activated
    final activatedChains = await getActivatedChains(chains);
    if (activatedChains.isEmpty) {
      _log.info('No NFT chains with activated parent coins');
      return;
    }
    await _api.enableNftChains(activatedChains);
    final json = await _api.updateNftList(activatedChains);
    if (json['error'] != null) {
      _log.severe(json['error'] as String);
      throw ApiError(message: json['error'] as String);
    }
  }

  Future<List<NftToken>> getNfts(List<NftBlockchains> chains) async {
    // Filter to only chains whose parent coins are already activated
    final activatedChains = await getActivatedChains(chains);
    if (activatedChains.isEmpty) {
      _log.info('No NFT chains with activated parent coins');
      return [];
    }
    await _api.enableNftChains(activatedChains);
    final json = await _api.getNftList(activatedChains);
    final jsonError = json['error'] as String?;
    if (jsonError != null) {
      _log.severe(jsonError);
      if (jsonError.toLowerCase().startsWith('transport')) {
        throw TransportError(message: jsonError);
      } else {
        throw ApiError(message: jsonError);
      }
    }

    if (json['result'] == null) {
      throw ApiError(message: LocaleKeys.somethingWrong.tr());
    }
    try {
      final response = GetNftListResponse.fromJson(json);
      final nfts = response.result.nfts;
      final coins = _coinsRepo.getKnownCoins();
      for (final NftToken nft in nfts) {
        final coin = coins.firstWhere((c) => c.type == nft.coinType);
        final parentCoin = coin.parentCoin ?? coin;
        nft.parentCoin = parentCoin;
      }
      return response.result.nfts;
    } on StateError catch (e) {
      throw TextError(error: e.toString());
    } catch (e) {
      throw ParsingApiJsonError(message: 'nft_main_repo -> getNfts: $e');
    }
  }

  /// Checks if the parent coins for the provided NFT chains are activated.
  /// Returns only the chains whose parent coins are already activated.
  ///
  /// Note: We no longer automatically activate parent coins to avoid unnecessary
  /// overhead. Users must manually enable the parent chain assets before using
  /// NFT functionality for that chain.
  Future<List<NftBlockchains>> getActivatedChains(
    List<NftBlockchains> chains,
  ) async {
    final List<Coin> knownCoins = _coinsRepo.getKnownCoins();
    final List<Coin> activeCoins = await _coinsRepo.getWalletCoins();
    
    return chains.where((NftBlockchains chain) {
      final parentCoin = knownCoins.firstWhereOrNull(
        (Coin coin) => coin.id.id == chain.coinAbbr(),
      );
      
      if (parentCoin == null) return false;
      
      // Check if the parent coin is already activated
      return activeCoins.any((coin) => coin.id.id == parentCoin.id.id);
    }).toList();
  }
}
