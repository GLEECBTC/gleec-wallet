import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/dex_repository.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/my_recent_swaps/my_recent_swaps_response.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/services/orders_service/my_orders_service.dart';
import 'package:web_dex/shared/swap/swap_services.dart';

import 'swap_src_fakes.dart';

/// A protocol with the members swaps read; [broken] makes each one throw.
class SrcProtocol implements ProtocolClass {
  SrcProtocol({
    this.testnet = false,
    this.contract,
    this.explorer = 'https://explorer.test/tx/',
    this.broken = false,
  });

  final bool testnet;
  final String? contract;
  final String explorer;
  final bool broken;

  void _check() {
    if (broken) throw StateError('protocol config unreadable');
  }

  @override
  bool get isTestnet {
    _check();
    return testnet;
  }

  @override
  String? get contractAddress {
    _check();
    return contract;
  }

  @override
  Uri? explorerTxUrl(String txHash) {
    _check();
    return Uri.parse('$explorer$txHash');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A wallet asset for [id].
Asset assetFor(AssetId id, {bool walletOnly = false, SrcProtocol? protocol}) =>
    Asset(
      id: id,
      protocol: protocol ?? SrcProtocol(),
      isWalletOnly: walletOnly,
      signMessagePrefix: null,
    );

/// A signed-in wallet.
KdfUser userOf(String name) => KdfUser(
  walletId: WalletId(
    name: name,
    pubkeyHash: 'hash-$name',
    authOptions: const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  ),
  isBip39Seed: true,
);

/// One address of an asset, holding [spendable].
PubkeyInfo keyOf(String address, {String? path, String spendable = '0'}) =>
    PubkeyInfo(
      address: address,
      derivationPath: path,
      chain: 'external',
      balance: BalanceInfo(
        total: Decimal.parse(spendable),
        spendable: Decimal.parse(spendable),
        unspendable: Decimal.zero,
      ),
      coinTicker: 'X',
    );

AssetPubkeys pubkeysOf(AssetId id, List<PubkeyInfo> keys) => AssetPubkeys(
  assetId: id,
  keys: keys,
  availableAddressesCount: keys.length,
  syncStatus: SyncStatusEnum.success,
);

BalanceInfo balanceOf(String spendable) => BalanceInfo(
  total: Decimal.parse(spendable),
  spendable: Decimal.parse(spendable),
  unspendable: Decimal.zero,
);

class SrcAuth implements KomodoDefiLocalAuth {
  final StreamController<KdfUser?> users =
      StreamController<KdfUser?>.broadcast();
  KdfUser? current;
  int currentUserReads = 0;

  @override
  Stream<KdfUser?> watchCurrentUser() => users.stream;

  @override
  Future<KdfUser?> get currentUser async {
    currentUserReads++;
    return current;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SrcMarketData implements MarketDataManager {
  final Map<AssetId, Decimal> prices = {};
  final List<AssetId> fetched = [];
  Set<AssetId> failing = {};
  bool broken = false;

  @override
  Decimal? priceIfKnown(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) {
    if (broken) throw StateError('market data disposed');
    return prices[assetId];
  }

  @override
  Future<Decimal?> maybeFiatPrice(
    AssetId assetId, {
    DateTime? priceDate,
    QuoteCurrency quoteCurrency = Stablecoin.usdt,
  }) async {
    fetched.add(assetId);
    if (failing.contains(assetId)) throw StateError('price feed down');
    return prices[assetId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SrcAssets implements AssetManager {
  final Map<AssetId, Asset> assets = {};
  bool broken = false;

  void add(Asset asset) => assets[asset.id] = asset;

  @override
  Map<AssetId, Asset> get available {
    if (broken) throw StateError('catalogue not loaded');
    return assets;
  }

  @override
  Set<Asset> findAssetsByConfigId(String ticker) =>
      available.values.where((asset) => asset.id.id == ticker).toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SrcPubkeys implements PubkeyManager {
  final Map<AssetId, AssetPubkeys> known = {};
  final Map<AssetId, AssetPubkeys> fetchable = {};
  final List<AssetId> fetched = [];
  bool broken = false;

  @override
  AssetPubkeys? lastKnown(AssetId assetId) {
    if (broken) throw StateError('pubkey cache unavailable');
    return known[assetId];
  }

  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async {
    fetched.add(asset.id);
    final keys = fetchable[asset.id];
    if (keys == null) throw StateError('get_enabled_coins failed');
    return keys;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SrcBalances implements BalanceManager {
  final Map<AssetId, BalanceInfo> known = {};
  bool broken = false;

  @override
  BalanceInfo? lastKnown(AssetId assetId) {
    if (broken) throw StateError('balance cache unavailable');
    return known[assetId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SrcSdk implements KomodoDefiSdk {
  @override
  final SrcAuth auth = SrcAuth();
  @override
  final SrcMarketData marketData = SrcMarketData();
  @override
  final SrcRoutedSwaps routedSwaps = SrcRoutedSwaps();
  @override
  final SrcAssets assets = SrcAssets();
  @override
  final SrcTrading trading = SrcTrading();
  @override
  final SrcPubkeys pubkeys = SrcPubkeys();
  @override
  final SrcBalances balances = SrcBalances();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SrcCoinsRepo implements CoinsRepo {
  Set<AssetId> activated = {};
  Object? activatedError;
  final Map<AssetId, BalanceInfo?> balances = {};
  Object? balanceError;
  final List<AssetId> balanceReads = [];
  final List<List<Asset>> activations = [];

  @override
  Future<Set<AssetId>> getActivatedAssetIds({bool forceRefresh = false}) async {
    final error = activatedError;
    if (error != null) throw error;
    return activated;
  }

  @override
  Future<void> activateAssetsSync(
    List<Asset> assets, {
    bool notifyListeners = true,
    bool addToWalletMetadata = true,
    bool useSharedActivationCache = false,
    int maxRetryAttempts = 15,
    Duration initialRetryDelay = const Duration(milliseconds: 500),
    Duration maxRetryDelay = const Duration(seconds: 10),
  }) async => activations.add(assets);

  @override
  Future<BalanceInfo?> balance(AssetId id) async {
    balanceReads.add(id);
    final error = balanceError;
    if (error != null) throw error;
    return balances[id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Atomic swaps the DEX does not know: resuming one falls through to the
/// order status, which has none.
class SrcDex implements DexRepository {
  final List<String> statusReads = [];

  @override
  Future<Swap> getSwapStatus(String swapUuid) async {
    statusReads.add(swapUuid);
    throw StateError('no such swap');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SrcOrders implements MyOrdersService {
  @override
  Future<OrderStatus?> getStatus(String uuid) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The legacy recent-swaps list; null [page] is KDF answering with an error.
class SrcMm2Api implements Mm2Api {
  MyRecentSwapsResponse? page = recentSwapsOf(const []);
  final List<MyRecentSwapsRequest> requests = [];

  @override
  Future<MyRecentSwapsResponse?> getMyRecentSwaps(
    MyRecentSwapsRequest request,
  ) async {
    requests.add(request);
    return page;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A page of the recent-swaps list.
MyRecentSwapsResponse recentSwapsOf(
  List<Swap> swaps, {
  int page = 1,
  int pages = 1,
}) => MyRecentSwapsResponse(
  result: MyRecentSwapsResponseResult(
    fromUuid: null,
    limit: 50,
    skipped: 0,
    swaps: swaps,
    total: swaps.length,
    pageNumber: page,
    foundRecords: swaps.length,
    totalPages: pages,
  ),
);

/// An atomic taker swap of ETH for USDC whose log holds [events], the last
/// one [lastAt].
Swap atomicSwapOf(String uuid, List<String> events, {DateTime? lastAt}) {
  final last = (lastAt ?? DateTime.now()).millisecondsSinceEpoch;
  return Swap.fromJson({
    'type': 'Taker',
    'uuid': uuid,
    'events': [
      for (final (index, type) in events.indexed)
        {
          'timestamp': last - (events.length - 1 - index) * 1000,
          'event': {'type': type},
        },
    ],
    'maker_amount': '3000',
    'maker_coin': 'USDC-ERC20',
    'taker_amount': '1',
    'taker_coin': 'ETH',
    'success_events': const ['Started', 'Negotiated', 'Finished'],
    'error_events': const ['StartFailed', 'NegotiateFailed'],
  });
}

/// Builds [SwapServices] over [sdk] and its collaborators.
SwapServices servicesOf(
  SrcSdk sdk, {
  SrcCoinsRepo? coins,
  SrcDex? dex,
  SrcMm2Api? mm2,
}) => SwapServices(
  sdk: sdk,
  coinsRepo: coins ?? SrcCoinsRepo(),
  dexRepository: dex ?? SrcDex(),
  orders: SrcOrders(),
  mm2Api: mm2 ?? SrcMm2Api(),
);
