import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api_nft.dart';
import 'package:web_dex/mm2/mm2_api/rpc/errors.dart';
import 'package:web_dex/mm2/mm2_api/rpc/nft/get_nft_list/get_nft_list_res.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/model/text_error.dart';

/// How a set of NFT chains stands against KDF's live activation state.
class NftChainActivation {
  const NftChainActivation({required this.activated, required this.unresolved});

  /// Chains KDF currently reports as enabled, and that are not geo-blocked.
  /// The ONLY thing that may become a tab.
  final List<NftBlockchains> activated;

  /// Chains the wallet asked for whose activation has neither succeeded nor
  /// failed yet. Never becomes a tab; it only separates "still coming up" from
  /// "you really have not enabled anything".
  final List<NftBlockchains> unresolved;
}

class NftsRepo {
  NftsRepo({
    required Mm2ApiNft api,
    required CoinsRepo coinsRepo,
    required KomodoDefiSdk sdk,
    required TradingStatusService tradingStatusService,
  }) : _coinsRepo = coinsRepo,
       _api = api,
       _sdk = sdk,
       _tradingStatusService = tradingStatusService;

  final Logger _log = Logger('NftsRepo');
  final CoinsRepo _coinsRepo;
  final Mm2ApiNft _api;
  final KomodoDefiSdk _sdk;
  final TradingStatusService _tradingStatusService;

  static final Set<String> _parentTickers = NftBlockchains.values
      .map((chain) => chain.coinAbbr())
      .toSet();

  Future<void> updateNft(List<NftBlockchains> chains) async {
    // Filter to only chains whose parent coins are already activated
    final activatedChains = await getActivatedChains(chains);
    if (activatedChains.isEmpty) {
      _log.info('No NFT chains with activated parent coins');
      return;
    }
    await _enableNftAssets(activatedChains);
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
    await _enableNftAssets(activatedChains);
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

  /// Activates the NFT protocol assets for [chains] through the SDK.
  ///
  /// `NftActivationService` throws a bare aggregate `Exception`, which no
  /// `on BaseError` arm can match, so it is converted here.
  Future<void> _enableNftAssets(List<NftBlockchains> chains) async {
    try {
      await _sdk.nftActivation.enableNftChains(
        chains.map((chain) => chain.nftAssetTicker()),
      );
    } catch (e, s) {
      _log.severe('Failed to activate NFT assets for $chains', e, s);
      throw ApiError(message: LocaleKeys.somethingWrong.tr());
    }
  }

  /// Resolves [chains] against KDF's live activation state.
  ///
  /// The gate keys on the PARENT coin (`coinAbbr()`), never on the `NFT_*`
  /// asset: the NFT assets are activated lazily inside the fetch below, so a
  /// gate keyed on them would be empty on every first pass and would tell the
  /// user to enable a chain they already enabled.
  Future<NftChainActivation> resolveChains(List<NftBlockchains> chains) async {
    final Set<String> enabled;
    final Map<AssetId, AssetActivationState> states;
    final List<String> intended;
    try {
      // Two SDK-maintained projections of ONE fact - KDF's enabled set.
      // `getEnabledCoins` is the authoritative read; `activationStates` is the
      // coordinator's map, written the instant KDF reports success, so it
      // covers the window before the activated-assets cache is invalidated.
      enabled = await _sdk.assets.getEnabledCoins();
      states = _sdk.activationStates;
      // Intent only. Decides "spinner or placeholder"; never a tab.
      intended = await _sdk.getWalletCoinIds();
    } catch (e, s) {
      _log.severe('Failed to read NFT chain activation state', e, s);
      throw TransportError(message: LocaleKeys.somethingWrong.tr());
    }

    final active = <String>{
      ...enabled,
      ...states.values.where((s) => s.isActive).map((s) => s.assetId.id),
    };
    final failed = states.values
        .where((s) => s.isFailed)
        .map((s) => s.assetId.id)
        .toSet();
    final intendedParents = intended.where(_parentTickers.contains).toSet();

    final activated = <NftBlockchains>[];
    final unresolved = <NftBlockchains>[];
    for (final chain in chains) {
      if (!_isChainAllowed(chain)) continue;
      final ticker = chain.coinAbbr();
      if (active.contains(ticker)) {
        activated.add(chain);
      } else if (intendedParents.contains(ticker) && !failed.contains(ticker)) {
        unresolved.add(chain);
      }
    }
    return NftChainActivation(activated: activated, unresolved: unresolved);
  }

  /// Chains whose parent coin KDF currently reports as enabled.
  Future<List<NftBlockchains>> getActivatedChains(
    List<NftBlockchains> chains,
  ) async => (await resolveChains(chains)).activated;

  /// Reproduces the geo filter that `CoinsRepo.getKnownCoins()` applied here,
  /// and the unknown-ticker case with it: a ticker absent from the catalogue
  /// yields an empty set, which filters to empty - matching the previous
  /// `firstWhereOrNull(...) == null -> false`.
  bool _isChainAllowed(NftBlockchains chain) => _tradingStatusService
      .filterAllowedAssets(
        _sdk.assets.findAssetsByConfigId(chain.coinAbbr()).toList(),
      )
      .isNotEmpty;
}
