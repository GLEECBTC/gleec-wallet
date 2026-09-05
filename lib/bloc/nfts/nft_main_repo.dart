import 'package:easy_localization/easy_localization.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api_nft.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/errors.dart';
import 'package:web_dex/mm2/mm2_api/rpc/nft/get_nft_list/get_nft_list_res.dart';
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/model/text_error.dart';

/// How a set of NFT chains stands against KDF's live activation state.
class NftChainActivation {
  const NftChainActivation({
    required this.supported,
    required this.activated,
    required this.unresolved,
  });

  /// Every chain this build can offer: present in the coins catalogue and not
  /// geo-blocked. A superset of [activated] and [unresolved] - a chain nobody
  /// has enabled still earns a tab, because tapping it is how it gets enabled.
  ///
  /// Shipped in the same snapshot as [activated] so the two cannot be read
  /// across a geo-status flip.
  final List<NftBlockchains> supported;

  /// Chains KDF currently reports as enabled, and that are not geo-blocked.
  /// The only thing that may carry an NFT count.
  final List<NftBlockchains> activated;

  /// Chains the wallet asked for whose activation has neither succeeded nor
  /// failed yet. Renders as an in-progress tab, never as a count: it separates
  /// "still coming up" from "you have not enabled this".
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

    final supported = <NftBlockchains>[];
    final activated = <NftBlockchains>[];
    final unresolved = <NftBlockchains>[];
    for (final chain in chains) {
      if (!_isChainAllowed(chain)) continue;
      supported.add(chain);
      final ticker = chain.coinAbbr();
      if (active.contains(ticker)) {
        activated.add(chain);
      } else if (intendedParents.contains(ticker) && !failed.contains(ticker)) {
        unresolved.add(chain);
      }
    }
    return NftChainActivation(
      supported: supported,
      activated: activated,
      unresolved: unresolved,
    );
  }

  /// Chains whose parent coin KDF currently reports as enabled.
  Future<List<NftBlockchains>> getActivatedChains(
    List<NftBlockchains> chains,
  ) async => (await resolveChains(chains)).activated;

  /// Enables the PARENT coin behind [chain] so its NFTs become fetchable.
  ///
  /// Deliberately NOT reachable from [getNfts]/[updateNft]. Those run on a 60s
  /// timer across `NftBlockchains.values`, so activating from inside them would
  /// restore the eager all-chain activation removed in 7953dffe. Only an
  /// explicit user gesture reaches this; the `NFT_*` asset is still activated
  /// lazily by [_enableNftAssets] once the parent is up.
  ///
  /// A parent the NFT page brings up on its own is session-scoped: it stays out
  /// of the next login's set and out of the wallet coin list. A parent the
  /// wallet already holds is activated normally - see [_isWalletCoin].
  Future<void> activateChain(NftBlockchains chain) async {
    final asset = _allowedParentAsset(chain);
    if (asset == null) {
      // A guard, not a user-facing path: no tab should have been offered.
      _log.warning('Refusing to activate unsupported NFT chain $chain');
      throw ApiError(message: LocaleKeys.somethingWrong.tr());
    }
    final isWalletCoin = await _isWalletCoin(asset);
    try {
      await _coinsRepo.activateAssetsSync(
        [asset],
        // `false` suppresses the asset's activation broadcasts for the rest of
        // the session, which keeps a browsed-only chain out of the wallet list.
        // On a coin the wallet holds it would freeze a real row instead -
        // reachable whenever a wallet coin's activation failed, which
        // `resolveChains` reports as inactive and the tab offers to enable.
        notifyListeners: isWalletCoin,
        addToWalletMetadata: false,
        // CoinsRepo's default of 15 is a background budget, ~105s of pure
        // sleep. Someone is watching this one.
        maxRetryAttempts: 3,
        maxRetryDelay: const Duration(seconds: 2),
      );
    } on BaseError {
      rethrow;
    } catch (e, s) {
      // A bare Exception no `on BaseError` arm can match, as in
      // [_enableNftAssets].
      _log.severe('Failed to activate ${asset.id.id} for $chain', e, s);
      throw ApiError(message: LocaleKeys.somethingWrong.tr());
    }
  }

  /// Whether [asset] is already one of the wallet's own coins. Falls back to
  /// `false` if the read fails, rather than failing an activation the user
  /// asked for over a bookkeeping question.
  Future<bool> _isWalletCoin(Asset asset) async {
    try {
      return (await _sdk.getWalletCoinIds()).contains(asset.id.id);
    } catch (e, s) {
      _log.warning('Could not read wallet coins for ${asset.id.id}', e, s);
      return false;
    }
  }

  /// Reproduces the geo filter that `CoinsRepo.getKnownCoins()` applied here,
  /// and the unknown-ticker case with it: a ticker absent from the catalogue
  /// yields an empty set, which filters to empty - matching the previous
  /// `firstWhereOrNull(...) == null -> false`.
  ///
  /// `findAssetsByConfigId` is indexed on `asset.id.id`, so every survivor is
  /// the parent coin itself and the first is the one to enable.
  Asset? _allowedParentAsset(NftBlockchains chain) {
    final allowed = _tradingStatusService.filterAllowedAssets(
      _sdk.assets.findAssetsByConfigId(chain.coinAbbr()).toList(),
    );
    return allowed.isEmpty ? null : allowed.first;
  }

  bool _isChainAllowed(NftBlockchains chain) =>
      _allowedParentAsset(chain) != null;
}
