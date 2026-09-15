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
    final session = await _sdk.auth.captureSessionContext();
    // Filter to only chains whose parent coins are already activated
    final activatedChains = await getActivatedChains(chains);
    if (activatedChains.isEmpty) {
      _log.info('No NFT chains with activated parent coins');
      return;
    }
    _sdk.auth.ensureSessionContextCurrent(session);
    await _enableNftAssets(activatedChains);
    _sdk.auth.ensureSessionContextCurrent(session);
    final json = await _api.updateNftList(activatedChains);
    _sdk.auth.ensureSessionContextCurrent(session);
    if (json['error'] != null) {
      _log.severe(json['error'] as String);
      throw ApiError(message: json['error'] as String);
    }
  }

  Future<List<NftToken>> getNfts(List<NftBlockchains> chains) async {
    final session = await _sdk.auth.captureSessionContext();
    // Filter to only chains whose parent coins are already activated
    final activatedChains = await getActivatedChains(chains);
    if (activatedChains.isEmpty) {
      _log.info('No NFT chains with activated parent coins');
      return [];
    }
    _sdk.auth.ensureSessionContextCurrent(session);
    await _enableNftAssets(activatedChains);
    _sdk.auth.ensureSessionContextCurrent(session);
    final json = await _api.getNftList(activatedChains);
    _sdk.auth.ensureSessionContextCurrent(session);
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
  /// Policy and session failures remain typed; protocol failures are mapped
  /// into the app's localized error presentation.
  Future<void> _enableNftAssets(List<NftBlockchains> chains) async {
    try {
      await _sdk.nftActivation.enableNftChains(
        chains.map((chain) => chain.nftAssetTicker()),
      );
    } on WalletChangedDisconnectException {
      rethrow;
    } on ActivationPolicyException {
      rethrow;
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
    final session = await _sdk.auth.captureSessionContext();
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
      intended = (await _sdk.walletAssets.load()).toList();
      _sdk.auth.ensureSessionContextCurrent(session);
    } on WalletChangedDisconnectException {
      rethrow;
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
  /// wallet already holds remains selected and keeps receiving SDK updates.
  Future<void> activateChain(NftBlockchains chain) async {
    final asset = _allowedParentAsset(chain);
    if (asset == null) {
      // A guard, not a user-facing path: no tab should have been offered.
      _log.warning('Refusing to activate unsupported NFT chain $chain');
      throw ApiError(message: LocaleKeys.somethingWrong.tr());
    }
    try {
      // Runtime availability is independent of the user's saved wallet list.
      // This does not mutate selection or suppress another consumer's stream.
      final result = await _sdk.activateAsset(asset);
      result.throwIfFailed();
    } on WalletChangedDisconnectException {
      rethrow;
    } on ActivationPolicyException {
      rethrow;
    } on BaseError {
      rethrow;
    } catch (e, s) {
      // A bare Exception no `on BaseError` arm can match, as in
      // [_enableNftAssets].
      _log.severe('Failed to activate ${asset.id.id} for $chain', e, s);
      throw ApiError(message: LocaleKeys.somethingWrong.tr());
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
