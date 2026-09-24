import 'dart:async';

import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/app_config/app_config.dart' show excludedAssetList;
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/atomic_swap_execution.dart';
import 'package:web_dex/shared/swap/atomic_swap_source.dart';
import 'package:web_dex/shared/swap/routed_swap_execution.dart';
import 'package:web_dex/shared/swap/routed_swap_source.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_history_repository.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

/// A request to open the swap form on a pair, as tickers.
typedef SwapIntent = ({String? pay, String? receive, String? amount});

/// Everything the swap surface needs from the rest of the app, built once.
///
/// App-wide rather than per screen because the [registry] must outlive every
/// swap screen: a swap started on the form keeps being followed while the user
/// is on their wallet, and is picked back up after a restart.
class SwapServices {
  SwapServices({
    required KomodoDefiSdk sdk,
    required CoinsRepo coinsRepo,
    required DexRepository dexRepository,
    required MyOrdersService orders,
    required Mm2Api mm2Api,
  }) : _sdk = sdk,
       _coinsRepo = coinsRepo,
       _mm2Api = mm2Api {
    pricing = SwapPricingService(SdkSwapPriceSource(sdk.marketData));
    registry = SwapExecutionRegistry(
      executors: [
        RoutedSwapExecutor(sdk.routedSwaps, networks: networks),
        AtomicSwapExecutor(
          dexRepository: dexRepository,
          orders: orders,
          networks: networks,
          resolveAsset: resolveAsset,
        ),
      ],
      inFlight: _inFlight,
    );
    history = SwapHistoryRepository(
      routedSwaps: sdk.routedSwaps,
      atomicHistory: _atomicHistory,
      networks: networks,
      resolveAsset: resolveAsset,
    );
    terms = SwapTermsRepository(walletKey: _walletKey);
    preferences = SwapPreferences(walletKey: _walletKey);
    _userSubscription = sdk.auth.watchCurrentUser().listen(
      _onUserChanged,
      onError: (Object _) {},
    );
  }

  final KomodoDefiSdk _sdk;
  final CoinsRepo _coinsRepo;
  final Mm2Api _mm2Api;

  late final SwapPricingService pricing;
  late final SwapExecutionRegistry registry;
  late final SwapHistoryRepository history;
  late final SwapTermsRepository terms;
  late final SwapPreferences preferences;

  StreamSubscription<KdfUser?>? _userSubscription;
  KdfUser? _user;
  final StreamController<SwapExecutionRef> _openRequests =
      StreamController<SwapExecutionRef>.broadcast();
  SwapExecutionRef? _pendingOpen;

  /// Swaps currently on screen. Notices about them are redundant.
  final Set<String> viewing = {};

  final StreamController<SwapIntent> _intents =
      StreamController<SwapIntent>.broadcast();
  SwapIntent? _pendingIntent;

  /// The last deep-link intent the Swap surface applied, so rebuilding the
  /// surface does not re-apply a link the user has since moved on from.
  String? lastRouteIntent;

  /// Asks the Swap form to open on a pair — from a coin page's Swap action.
  void requestIntent(SwapIntent intent) {
    _pendingIntent = intent;
    if (!_intents.isClosed) _intents.add(intent);
  }

  /// Intents as they are requested.
  Stream<SwapIntent> get intents => _intents.stream;

  /// The intent requested before the Swap surface mounted, once.
  SwapIntent? takePendingIntent() {
    final pending = _pendingIntent;
    _pendingIntent = null;
    return pending;
  }

  /// Asks the Swap surface to show a swap — from a notice, say, while the
  /// surface may not be mounted yet.
  void requestOpen(SwapExecutionRef ref) {
    _pendingOpen = ref;
    if (!_openRequests.isClosed) _openRequests.add(ref);
  }

  /// Open requests as they happen.
  Stream<SwapExecutionRef> get openRequests => _openRequests.stream;

  /// The request made before the Swap surface mounted, once.
  SwapExecutionRef? takePendingOpen() {
    final pending = _pendingOpen;
    _pendingOpen = null;
    return pending;
  }

  SwapNetworks? _networks;
  int _networksBuiltFrom = -1;

  static const _atomicResumeWindow = Duration(days: 7);

  /// The asset catalogue.
  Map<AssetId, Asset> get _available {
    try {
      return _sdk.assets.available;
    } on Object {
      return const {};
    }
  }

  /// Names the networks swaps touch. Rebuilt when the catalogue changes.
  SwapNetworks networks() {
    final available = _available;
    if (_networks == null || _networksBuiltFrom != available.length) {
      _networks = SwapNetworks(available.keys);
      _networksBuiltFrom = available.length;
    }
    return _networks!;
  }

  /// The asset a ticker names, if the wallet knows it.
  AssetId? resolveAsset(String ticker) {
    try {
      return _sdk.assets.findAssetsByConfigId(ticker).firstOrNull?.id;
    } on Object {
      return null;
    }
  }

  /// The full asset for [id].
  Asset? assetOf(AssetId id) => _available[id];

  /// Every asset the wallet knows.
  Iterable<AssetId> get knownAssets => _available.keys;

  /// The assets a swap may offer: every known asset the app does not
  /// exclude outright.
  Set<AssetId> swappableAssets() => {
    for (final id in _available.keys)
      if (!excludedAssetList.contains(id.id)) id,
  };

  /// Whether the coin config marks [id] wallet-only, which KDF refuses to
  /// trade on the orderbook.
  bool isWalletOnly(AssetId id) => assetOf(id)?.isWalletOnly ?? false;

  /// Whether [id] is a test-network asset.
  bool isTestnet(AssetId id) {
    try {
      return assetOf(id)?.protocol.isTestnet ?? false;
    } on Object {
      return false;
    }
  }

  /// The token contract behind [id], for a token; null for a native coin.
  String? contractOf(AssetId id) {
    try {
      return assetOf(id)?.protocol.contractAddress;
    } on Object {
      return null;
    }
  }

  /// A key identifying the signed-in wallet, for per-wallet preferences.
  Future<String?> _walletKey() async {
    final user = _user ?? await _sdk.auth.currentUser;
    return user?.walletId.compoundId;
  }

  void _onUserChanged(KdfUser? user) {
    final previous = _user?.walletId;
    _user = user;
    if (user == null) {
      unawaited(registry.reset());
      return;
    }
    if (previous != null && previous != user.walletId) {
      unawaited(registry.reset().then((_) => registry.resumeInFlight()));
      return;
    }
    if (previous == null) unawaited(registry.resumeInFlight());
  }

  Future<List<SwapExecutionRef>> _inFlight() async {
    final refs = <SwapExecutionRef>[];
    try {
      final routed = await _sdk.routedSwaps.inFlight();
      refs.addAll([
        for (final swap in routed)
          (id: swap.uuid, source: SwapLiquiditySource.routed),
      ]);
    } on Object {
      // Routed history unavailable: atomic swaps still resume.
    }
    try {
      final page = await _atomicHistory(limit: 50, page: 1);
      // Swaps that never logged Finished can sit in the list for years;
      // following every one of them would poll forever.
      final since = DateTime.now().subtract(_atomicResumeWindow);
      refs.addAll([
        for (final swap in page.swaps)
          if (!swap.isCompleted &&
              swap.events.isNotEmpty &&
              DateTime.fromMillisecondsSinceEpoch(
                swap.events.last.timestamp,
              ).isAfter(since))
            (id: swap.uuid, source: SwapLiquiditySource.atomic),
      ]);
    } on Object {
      // As above, the other way round.
    }
    return refs;
  }

  Future<AtomicSwapHistoryPage> _atomicHistory({
    required int limit,
    required int page,
  }) async {
    final response = await _mm2Api.getMyRecentSwaps(
      MyRecentSwapsRequest(limit: limit, pageNumber: page),
    );
    if (response == null) {
      throw StateError('my_recent_swaps returned no result');
    }
    final result = response.result;
    return AtomicSwapHistoryPage(
      swaps: result.swaps,
      hasMore: result.pageNumber < result.totalPages,
    );
  }

  /// Builds the quote repository, gated by the live trading checks.
  UnifiedSwapRepository createRepository({
    required bool Function(AssetId from, AssetId to) tradingAllowed,
    required bool Function() clockValid,
  }) {
    return UnifiedSwapRepository(
      sources: [
        RoutedSwapQuoteSource(
          _sdk.routedSwaps,
          networks: networks,
          tradingAllowed: tradingAllowed,
        ),
        AtomicSwapQuoteSource(
          trading: _sdk.trading,
          networks: networks,
          addressOf: addressOf,
          tradingAllowed: tradingAllowed,
          clockValid: clockValid,
          isWalletOnly: isWalletOnly,
        ),
      ],
      pricing: pricing,
      knownAssets: swappableAssets,
      activatedAssets: activatedAssets,
    );
  }

  /// Assets currently activated.
  Future<Set<AssetId>> activatedAssets() async =>
      (await _coinsRepo.getActivatedAssetIds()).toSet();

  /// Activates [id] in the wallet.
  Future<void> activate(AssetId id) async {
    final asset = assetOf(id);
    if (asset == null) throw StateError('Unknown asset ${id.id}');
    await _coinsRepo.activateAssetsSync([asset]);
  }

  PubkeyInfo? _swapKey(AssetPubkeys? pubkeys) {
    if (pubkeys == null) return null;
    return pubkeys.keys.firstWhereOrNull((key) => key.isActiveForSwap) ??
        pubkeys.keys.firstOrNull;
  }

  Future<AssetPubkeys?> _pubkeys(AssetId id) async {
    final known = _sdk.pubkeys.lastKnown(id);
    if (known != null && known.keys.isNotEmpty) return known;
    final asset = assetOf(id);
    if (asset == null || !await _isActivated(id)) return null;
    return _sdk.pubkeys.getPubkeys(asset);
  }

  /// Whether [id] is active. Every read of an address or balance goes
  /// through this first: the SDK activates an asset to read either, and on
  /// the swap form activation is the user's decision, never a side effect.
  Future<bool> _isActivated(AssetId id) async {
    try {
      return (await activatedAssets()).contains(id);
    } on Object {
      return false;
    }
  }

  /// The address swaps of [id] spend from and deliver to.
  ///
  /// The engine swaps from one enabled address per asset, which for an HD
  /// wallet is the first address of the account.
  Future<String?> addressOf(AssetId id) async {
    try {
      return _swapKey(await _pubkeys(id))?.address;
    } on Object {
      return null;
    }
  }

  /// What can be put into a swap of [id]: the swap address's spendable
  /// balance. Null — never zero — when it cannot be read, so the form does
  /// not tell someone with funds that they have none.
  Future<Decimal?> spendableBalance(AssetId id) async {
    try {
      final key = _swapKey(await _pubkeys(id));
      if (key != null) {
        return Decimal.tryParse(key.balance.spendable.toString());
      }
    } on Object {
      // Fall back to the asset-wide balance.
    }
    try {
      if (!await _isActivated(id)) return null;
      final balance = await _coinsRepo.balance(id);
      if (balance == null) return null;
      return Decimal.tryParse(balance.spendable.toString());
    } on Object {
      return null;
    }
  }

  /// The last balance read for [id], without waiting.
  Decimal? lastKnownBalance(AssetId id) {
    try {
      final balance = _sdk.balances.lastKnown(id);
      return balance == null
          ? null
          : Decimal.tryParse(balance.spendable.toString());
    } on Object {
      return null;
    }
  }

  /// The USD price of [id], if known.
  Decimal? usdPrice(AssetId id) => pricing.prices.usdPrice(id);

  /// Holdings with their USD value, for choosing a default pair.
  Future<List<SwapHolding>> holdings() async {
    final activated = await activatedAssets();
    await pricing.prices.warm(activated);
    return [
      for (final id in activated)
        if (_holding(id) case final SwapHolding holding) holding,
    ];
  }

  SwapHolding? _holding(AssetId id) {
    final balance = lastKnownBalance(id);
    final price = usdPrice(id);
    if (balance == null || price == null || balance <= Decimal.zero) {
      return null;
    }
    return (asset: id, usdValue: balance * price);
  }

  /// An explorer link for [hash] on [asset]'s network.
  Uri? explorerTxUrl(AssetId? asset, String hash) {
    if (asset == null) return null;
    try {
      return assetOf(asset)?.protocol.explorerTxUrl(hash);
    } on Object {
      return null;
    }
  }

  /// Stops following swaps and releases resources.
  Future<void> dispose() async {
    await _userSubscription?.cancel();
    await _openRequests.close();
    await _intents.close();
    await registry.dispose();
  }
}
