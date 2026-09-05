import 'package:flutter_test/flutter_test.dart';
// `KomodoDefiSdk.auth` and `.assets` are typed as concrete classes the SDK
// barrel does not re-export, so faking them means importing directly.
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/nfts/nft_main_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api_nft.dart';
import 'package:web_dex/mm2/mm2_api/rpc/errors.dart';
import 'package:web_dex/model/nft.dart';

/// Pins the single-source-of-truth property of [NftsRepo.resolveChains].
///
/// The NFT page once decided "is this chain enabled?" from two disagreeing
/// places: persisted wallet intent (`activated_coins`) and KDF's live enabled
/// set. Only the live set may produce a tab; intent may only hold the loading
/// state. The bloc tests stub this method out, so these are the only tests that
/// execute the resolution itself.
void testNftMainRepo() {
  group('NftsRepo.resolveChains', () {
    late _FakeAssetManager assets;
    late _FakeNftActivation nftActivation;
    late _FakeTradingStatusService tradingStatus;
    late _FakeAuth auth;

    NftsRepo build({
      Set<String> enabled = const {},
      Map<AssetId, AssetActivationState> states = const {},
      List<String> intended = const [],
    }) {
      assets = _FakeAssetManager({for (final a in _catalogue) a.id: a})
        ..enabled = enabled;
      nftActivation = _FakeNftActivation();
      tradingStatus = _FakeTradingStatusService();
      auth = _FakeAuth(intended);
      return NftsRepo(
        api: _FakeMm2ApiNft(),
        coinsRepo: _FakeCoinsRepo(),
        sdk: _FakeSdk(
          auth: auth,
          assets: assets,
          nftActivation: nftActivation,
          activationStates: states,
        ),
        tradingStatusService: tradingStatus,
      );
    }

    test('a live-enabled parent produces an activated chain', () async {
      final repo = build(enabled: {'ETH'});

      final result = await repo.resolveChains(NftBlockchains.values);

      expect(result.activated, [NftBlockchains.eth]);
      expect(result.unresolved, isEmpty);
    });

    test('wallet intent alone never produces a tab', () async {
      // `activated_coins` names ETH, but KDF has not enabled it. This is the
      // exact disagreement that used to make the repo pass a chain the API
      // layer then rejected.
      final repo = build(intended: ['ETH']);

      final result = await repo.resolveChains(NftBlockchains.values);

      expect(result.activated, isEmpty);
      expect(result.unresolved, [NftBlockchains.eth]);
    });

    test('a failed activation is neither activated nor unresolved', () async {
      final repo = build(
        intended: ['ETH'],
        states: {
          _ethId: AssetActivationState.failed(_ethId, errorMessage: 'boom'),
        },
      );

      final result = await repo.resolveChains(NftBlockchains.values);

      // Otherwise the loading hold would spin forever.
      expect(result.activated, isEmpty);
      expect(result.unresolved, isEmpty);
    });

    test(
      'the coordinator map counts as active before the cache catches up',
      () async {
        // ActivationManager publishes `active` before invalidating the
        // activated-assets cache, so `getEnabledCoins` can still be stale here.
        final repo = build(
          enabled: const {},
          states: {_ethId: AssetActivationState.active(_ethId)},
        );

        final result = await repo.resolveChains(NftBlockchains.values);

        expect(result.activated, [NftBlockchains.eth]);
      },
    );

    test('a geo-blocked chain is excluded', () async {
      final repo = build(enabled: {'ETH'});
      tradingStatus.blocked = {_ethId};

      final result = await repo.resolveChains(NftBlockchains.values);

      expect(result.activated, isEmpty);
      expect(result.unresolved, isEmpty);
    });

    test('a ticker absent from the catalogue is excluded', () async {
      // FTM is not in the bundled coins config; the old code reached this via
      // `firstWhereOrNull(...) == null -> false`.
      final repo = build(enabled: {'FTM'});

      final result = await repo.resolveChains(NftBlockchains.values);

      expect(result.activated, isEmpty);
    });

    test('caller order is preserved', () async {
      final repo = build(enabled: {'ETH', 'BNB', 'MATIC'});

      final result = await repo.resolveChains([
        NftBlockchains.bsc,
        NftBlockchains.eth,
        NftBlockchains.polygon,
      ]);

      expect(result.activated, [
        NftBlockchains.bsc,
        NftBlockchains.eth,
        NftBlockchains.polygon,
      ]);
    });

    test('a failed activation-state read surfaces as a typed error', () async {
      final repo = build();
      assets.enabledError = StateError('cache disposed');

      // A bare StateError would reach the bloc's catch-all and render its raw
      // Dart text at the user.
      await expectLater(
        repo.resolveChains(NftBlockchains.values),
        throwsA(isA<TransportError>()),
      );
    });

    test('getActivatedChains exposes only the activated half', () async {
      final repo = build(enabled: {'ETH'}, intended: ['BNB']);

      expect(await repo.getActivatedChains(NftBlockchains.values), [
        NftBlockchains.eth,
      ]);
    });

    test('every catalogue chain is supported, activated or not', () async {
      // The tab strip is built from this. A chain the user has never enabled
      // must still appear, or tapping it can never be the way to enable it.
      final repo = build(enabled: {'ETH'});

      final result = await repo.resolveChains(NftBlockchains.values);

      expect(result.supported, [
        NftBlockchains.eth,
        NftBlockchains.polygon,
        NftBlockchains.bsc,
        NftBlockchains.avalanche,
      ]);
      // FTM is absent from the bundled coins config, so Fantom can never be a
      // tab no matter what the enum says.
      expect(result.supported, isNot(contains(NftBlockchains.fantom)));
      expect(result.activated, [NftBlockchains.eth]);
    });

    test('a geo-blocked chain is not supported', () async {
      final repo = build(enabled: {'ETH'});
      tradingStatus.blocked = {_ethId};

      final result = await repo.resolveChains(NftBlockchains.values);

      expect(result.supported, isNot(contains(NftBlockchains.eth)));
    });
  });

  group('NftsRepo.activateChain', () {
    late _FakeCoinsRepo coinsRepo;
    late _FakeTradingStatusService tradingStatus;

    NftsRepo build({List<String> walletCoins = const []}) {
      coinsRepo = _FakeCoinsRepo();
      tradingStatus = _FakeTradingStatusService();
      return NftsRepo(
        api: _FakeMm2ApiNft(),
        coinsRepo: coinsRepo,
        sdk: _FakeSdk(
          auth: _FakeAuth(walletCoins),
          assets: _FakeAssetManager({for (final a in _catalogue) a.id: a}),
          nftActivation: _FakeNftActivation(),
          activationStates: const {},
        ),
        tradingStatusService: tradingStatus,
      );
    }

    test('the parent coin is activated, session-scoped', () async {
      final repo = build();

      await repo.activateChain(NftBlockchains.polygon);

      // The PARENT gates the tab; NFT_MATIC is activated later, in the fetch.
      expect(coinsRepo.activateCalls.single.single.id.id, 'MATIC');
      // Pins the product decision so it cannot be silently flipped: browsing an
      // NFT tab must not add MATIC to the wallet or to the next login's set.
      expect(coinsRepo.lastAddToWalletMetadata, isFalse);
      expect(coinsRepo.lastNotifyListeners, isFalse);
      // A user is watching, so this must not inherit the 15-attempt background
      // fan-out budget.
      expect(coinsRepo.lastMaxRetryAttempts, 3);
    });

    test('a parent the wallet already holds keeps its coin-list row', () async {
      // `notifyListeners: false` suppresses the asset's activation broadcasts
      // for the whole session. On a coin the wallet owns that freezes a real
      // row - reachable whenever a wallet coin's activation failed, because
      // resolveChains reports that as inactive and the tab offers to enable it.
      final repo = build(walletCoins: ['MATIC']);

      await repo.activateChain(NftBlockchains.polygon);

      expect(coinsRepo.lastNotifyListeners, isTrue);
      // Still never re-added to metadata: it is already there.
      expect(coinsRepo.lastAddToWalletMetadata, isFalse);
    });

    test('a chain absent from the catalogue never reaches CoinsRepo', () async {
      final repo = build();

      await expectLater(
        repo.activateChain(NftBlockchains.fantom),
        throwsA(isA<ApiError>()),
      );
      expect(coinsRepo.activateCalls, isEmpty);
    });

    test('a geo-blocked chain never reaches CoinsRepo', () async {
      final repo = build();
      tradingStatus.blocked = {_ethId};

      await expectLater(
        repo.activateChain(NftBlockchains.eth),
        throwsA(isA<ApiError>()),
      );
      expect(coinsRepo.activateCalls, isEmpty);
    });

    test('a bare activation failure becomes a typed ApiError', () async {
      final repo = build();
      coinsRepo.errorToThrow = Exception('activation exhausted');

      // CoinsRepo throws a bare Exception, which no `on BaseError` arm in the
      // bloc could match.
      await expectLater(
        repo.activateChain(NftBlockchains.eth),
        throwsA(isA<ApiError>()),
      );
    });
  });

  group('NftsRepo NFT asset activation', () {
    test('activation is delegated to the SDK with NFT_* tickers', () async {
      final nftActivation = _FakeNftActivation();
      final repo = NftsRepo(
        api: _FakeMm2ApiNft(),
        coinsRepo: _FakeCoinsRepo(),
        sdk: _FakeSdk(
          auth: _FakeAuth(const []),
          assets: _FakeAssetManager({for (final a in _catalogue) a.id: a})
            ..enabled = {'ETH'},
          nftActivation: nftActivation,
          activationStates: const {},
        ),
        tradingStatusService: _FakeTradingStatusService(),
      );

      await repo.updateNft([NftBlockchains.eth]);

      // The parent gates the tab; the NFT_* asset is what gets activated.
      expect(nftActivation.enabledTickers, ['NFT_ETH']);
    });

    test('a bare SDK activation failure becomes a typed ApiError', () async {
      final nftActivation = _FakeNftActivation()
        ..errorToThrow = Exception('aggregate activation failure');
      final repo = NftsRepo(
        api: _FakeMm2ApiNft(),
        coinsRepo: _FakeCoinsRepo(),
        sdk: _FakeSdk(
          auth: _FakeAuth(const []),
          assets: _FakeAssetManager({for (final a in _catalogue) a.id: a})
            ..enabled = {'ETH'},
          nftActivation: nftActivation,
          activationStates: const {},
        ),
        tradingStatusService: _FakeTradingStatusService(),
      );

      // NftActivationService throws a bare Exception, which no `on BaseError`
      // arm can match.
      await expectLater(
        repo.updateNft([NftBlockchains.eth]),
        throwsA(isA<ApiError>()),
      );
    });
  });
}

Asset _asset(String ticker, String name, int chainId) => Asset.fromJson({
  'coin': ticker,
  'type': 'UTXO',
  'name': name,
  'fname': name,
  'wallet_only': false,
  'mm2': 1,
  'chain_id': chainId,
  'decimals': 18,
  'is_testnet': false,
  'required_confirmations': 1,
  'derivation_path': "m/44'/60'/0'",
  'protocol': {'type': 'UTXO'},
}, knownIds: const {});

final _catalogue = <Asset>[
  _asset('ETH', 'Ethereum', 1),
  _asset('BNB', 'Binance Coin', 56),
  _asset('MATIC', 'Polygon', 137),
  _asset('AVAX', 'Avalanche', 43114),
  // FTM deliberately absent, mirroring the bundled coins config.
];

final _ethId = _catalogue.first.id;

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({
    required this.auth,
    required this.assets,
    required this.nftActivation,
    required this.activationStates,
  });

  @override
  final KomodoDefiLocalAuth auth;

  @override
  final AssetManager assets;

  @override
  final NftActivationService nftActivation;

  @override
  final Map<AssetId, AssetActivationState> activationStates;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(this._available);

  final Map<AssetId, Asset> _available;
  Set<String> enabled = {};
  Object? enabledError;

  @override
  Future<Set<String>> getEnabledCoins() async {
    if (enabledError != null) throw enabledError!;
    return enabled;
  }

  @override
  Set<Asset> findAssetsByConfigId(String ticker) =>
      _available.values.where((asset) => asset.id.id == ticker).toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeNftActivation implements NftActivationService {
  final List<String> enabledTickers = [];
  Object? errorToThrow;

  @override
  Future<void> enableNftChains(
    Iterable<String> nftTickers, {
    NftActivationParams? activationParams,
  }) async {
    enabledTickers.addAll(nftTickers);
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTradingStatusService implements TradingStatusService {
  Set<AssetId> blocked = {};

  @override
  List<Asset> filterAllowedAssets(List<Asset> assets) =>
      assets.where((a) => !blocked.contains(a.id)).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements KomodoDefiLocalAuth {
  _FakeAuth(this._intended);

  final List<String> _intended;

  @override
  Future<KdfUser?> get currentUser async => KdfUser(
    walletId: WalletId.fromName(
      'Wallet 1',
      const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    ),
    isBip39Seed: true,
    metadata: {'activated_coins': _intended},
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoinsRepo implements CoinsRepo {
  final List<List<Asset>> activateCalls = [];
  bool? lastNotifyListeners;
  bool? lastAddToWalletMetadata;
  int? lastMaxRetryAttempts;
  Object? errorToThrow;

  @override
  Future<void> activateAssetsSync(
    List<Asset> assets, {
    bool notifyListeners = true,
    bool addToWalletMetadata = true,
    bool useSharedActivationCache = false,
    int maxRetryAttempts = 15,
    Duration initialRetryDelay = const Duration(milliseconds: 500),
    Duration maxRetryDelay = const Duration(seconds: 10),
  }) async {
    activateCalls.add(assets);
    lastNotifyListeners = notifyListeners;
    lastAddToWalletMetadata = addToWalletMetadata;
    lastMaxRetryAttempts = maxRetryAttempts;
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMm2ApiNft implements Mm2ApiNft {
  @override
  Future<Map<String, dynamic>> updateNftList(
    List<NftBlockchains> chains,
  ) async => <String, dynamic>{'result': <String, dynamic>{}};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
