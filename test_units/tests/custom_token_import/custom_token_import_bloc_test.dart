import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    as kdf_rpc;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/custom_token_import/bloc/custom_token_import_bloc.dart';
import 'package:web_dex/bloc/custom_token_import/bloc/custom_token_import_event.dart';
import 'package:web_dex/bloc/custom_token_import/bloc/custom_token_import_state.dart';
import 'package:web_dex/bloc/custom_token_import/data/custom_token_import_repository.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/services/storage/base_storage.dart';

Map<String, dynamic> _trxConfig() => {
  'coin': 'TRX',
  'type': 'TRX',
  'name': 'TRON',
  'fname': 'TRON',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'required_confirmations': 1,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRX',
    'protocol_data': {'network': 'Mainnet'},
  },
  'nodes': <Map<String, dynamic>>[],
};

Map<String, dynamic> _trc20Config({
  required String coin,
  required String contractAddress,
}) => {
  'coin': coin,
  'type': 'TRC-20',
  'name': 'Tether',
  'fname': 'Tether',
  'wallet_only': true,
  'mm2': 1,
  'decimals': 6,
  'derivation_path': "m/44'/195'",
  'protocol': {
    'type': 'TRC20',
    'protocol_data': {'platform': 'TRX', 'contract_address': contractAddress},
  },
  'contract_address': contractAddress,
  'parent_coin': 'TRX',
  'nodes': <Map<String, dynamic>>[],
};

class _MemoryStorage implements BaseStorage {
  final Map<String, dynamic> _store = {};

  @override
  Future<bool> delete(String key) async {
    _store.remove(key);
    return true;
  }

  @override
  Future<dynamic> read(String key) async => _store[key];

  @override
  Future<bool> write(String key, dynamic data) async {
    _store[key] = data;
    return true;
  }
}

class _FakeAnalyticsRepo implements AnalyticsRepo {
  final List<AnalyticsEventData> queuedEvents = [];

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  Future<void> dispose() async {}

  @override
  bool get isEnabled => true;

  @override
  bool get isInitialized => true;

  @override
  Future<void> loadPersistedQueue() async {}

  @override
  Future<void> persistQueue() async {}

  @override
  Future<void> queueEvent(AnalyticsEventData data) async {
    queuedEvents.add(data);
  }

  @override
  Future<void> retryInitialization(dynamic settings) async {}

  @override
  Future<void> sendData(AnalyticsEventData data) async {
    queuedEvents.add(data);
  }
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(this._available);

  final Map<AssetId, Asset> _available;

  @override
  Map<AssetId, Asset> get available => _available;

  void addAsset(Asset asset) {
    _available[asset.id] = asset;
  }

  void removeAsset(AssetId assetId) {
    _available.remove(assetId);
  }

  @override
  Set<Asset> findAssetsByConfigId(String ticker) {
    return _available.values.where((asset) => asset.id.id == ticker).toSet();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements KomodoDefiLocalAuth {
  _FakeAuth({required this.user});

  KdfUser? user;

  @override
  Future<KdfUser?> get currentUser async => user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({required this.assets, required this.auth});

  @override
  final _FakeAssetManager assets;

  @override
  final KomodoDefiLocalAuth auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RollbackCall {
  const _RollbackCall({
    required this.assets,
    required this.deleteCustomTokens,
    required this.removeWalletMetadataAssets,
  });

  final List<Asset> assets;
  final Set<AssetId> deleteCustomTokens;
  final Set<AssetId> removeWalletMetadataAssets;
}

class _FakeCoinsRepo implements CoinsRepo {
  _FakeCoinsRepo({required this.assetManager, this.balanceInfo});

  final _FakeAssetManager assetManager;
  final List<List<Asset>> activateCalls = [];
  final List<_RollbackCall> rollbackCalls = [];
  final Set<AssetId> activeAssetIds = <AssetId>{};
  final kdf_rpc.BalanceInfo? balanceInfo;

  @override
  Future<void> activateAssetsSync(
    List<Asset> assets, {
    bool notifyListeners = true,
    bool addToWalletMetadata = true,
    int maxRetryAttempts = 15,
    Duration initialRetryDelay = const Duration(milliseconds: 500),
    Duration maxRetryDelay = const Duration(seconds: 10),
  }) async {
    activateCalls.add(List<Asset>.from(assets));
    for (final asset in assets) {
      activeAssetIds.add(asset.id);
      assetManager.addAsset(asset);
    }
  }

  @override
  double? getUsdPriceByAmount(String amount, String coinAbbr) => 12.5;

  @override
  Future<bool> isAssetActivated(
    AssetId assetId, {
    bool forceRefresh = false,
  }) async {
    return activeAssetIds.contains(assetId);
  }

  @override
  Future<void> rollbackPreviewAssets(
    Iterable<Asset> assets, {
    Set<AssetId> deleteCustomTokens = const {},
    Set<AssetId> removeWalletMetadataAssets = const {},
    bool notifyListeners = false,
  }) async {
    final assetList = assets.toList();
    rollbackCalls.add(
      _RollbackCall(
        assets: assetList,
        deleteCustomTokens: deleteCustomTokens,
        removeWalletMetadataAssets: removeWalletMetadataAssets,
      ),
    );

    for (final asset in assetList) {
      activeAssetIds.remove(asset.id);
    }
    for (final assetId in deleteCustomTokens) {
      assetManager.removeAsset(assetId);
    }
  }

  @override
  Future<kdf_rpc.BalanceInfo> tryGetBalanceInfo(AssetId coinId) async {
    return balanceInfo ?? kdf_rpc.BalanceInfo.zero();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomTokenImportRepository implements ICustomTokenImportRepository {
  Asset? fetchResult;
  Object? fetchError;
  int importCalls = 0;

  @override
  void dispose() {}

  @override
  Future<Asset> fetchCustomToken({
    required CoinSubClass network,
    required Asset platformAsset,
    required String address,
  }) async {
    if (fetchError != null) {
      throw fetchError!;
    }
    return fetchResult ?? (throw StateError('fetchResult not configured'));
  }

  @override
  String? getNetworkApiName(CoinSubClass coinType) {
    return switch (coinType) {
      CoinSubClass.trc20 => 'tron',
      CoinSubClass.erc20 => 'ethereum',
      _ => null,
    };
  }

  @override
  Future<void> importCustomToken(Asset asset) async {
    importCalls += 1;
  }
}

Future<void> _setTrc20Input(CustomTokenImportBloc bloc) async {
  bloc.add(const UpdateNetworkEvent(CoinSubClass.trc20));
  bloc.add(const UpdateAddressEvent('0x1234'));
  await Future<void>.delayed(Duration.zero);
}

Future<CustomTokenImportState> _fetchPreview(CustomTokenImportBloc bloc) async {
  final successState = bloc.stream.firstWhere(
    (state) => state.formStatus == FormStatus.success,
  );
  bloc.add(const SubmitFetchCustomTokenEvent());
  return successState;
}

AnalyticsBloc _createAnalyticsBloc(_FakeAnalyticsRepo analyticsRepo) {
  return AnalyticsBloc(
    analytics: analyticsRepo,
    storedData: StoredSettings.initial(),
    repository: SettingsRepository(storage: _MemoryStorage()),
  );
}

void main() {
  group('CustomTokenImportBloc preview lifecycle', () {
    late Asset platformAsset;
    late Asset tokenAsset;
    late _FakeAssetManager assetManager;
    late _FakeCoinsRepo coinsRepo;
    late _FakeCustomTokenImportRepository repository;
    late _FakeAnalyticsRepo analyticsRepo;
    late AnalyticsBloc analyticsBloc;
    late _FakeAuth auth;
    late CustomTokenImportBloc bloc;

    setUp(() {
      platformAsset = Asset.fromJson(_trxConfig(), knownIds: const {});
      tokenAsset = Asset.fromJson(
        _trc20Config(
          coin: 'USDT-TRC20',
          contractAddress: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
        ),
        knownIds: {platformAsset.id},
      );

      assetManager = _FakeAssetManager({platformAsset.id: platformAsset});
      coinsRepo = _FakeCoinsRepo(
        assetManager: assetManager,
        balanceInfo: kdf_rpc.BalanceInfo.zero(),
      );
      repository = _FakeCustomTokenImportRepository()..fetchResult = tokenAsset;
      analyticsRepo = _FakeAnalyticsRepo();
      analyticsBloc = _createAnalyticsBloc(analyticsRepo);
      auth = _FakeAuth(
        user: KdfUser(
          walletId: WalletId.fromName(
            'test-wallet',
            const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
          ),
          isBip39Seed: true,
          metadata: const {'activated_coins': <String>[]},
        ),
      );
      bloc = CustomTokenImportBloc(
        repository,
        coinsRepo,
        _FakeSdk(assets: assetManager, auth: auth),
        analyticsBloc,
      );
    });

    tearDown(() async {
      if (!bloc.isClosed) {
        await bloc.close();
      }
      await analyticsBloc.close();
    });

    test('successful preview does not roll back immediately', () async {
      await _setTrc20Input(bloc);

      final successState = await _fetchPreview(bloc);

      expect(successState.coin, tokenAsset);
      expect(coinsRepo.rollbackCalls, isEmpty);
      expect(
        coinsRepo.activeAssetIds,
        containsAll({platformAsset.id, tokenAsset.id}),
      );
    });

    test('fetch failure rolls back preview-only platform activation', () async {
      repository.fetchError = StateError('token lookup failed');
      await _setTrc20Input(bloc);

      final failureState = bloc.stream.firstWhere(
        (state) => state.formStatus == FormStatus.failure,
      );
      bloc.add(const SubmitFetchCustomTokenEvent());
      await failureState;

      expect(coinsRepo.rollbackCalls, hasLength(1));
      expect(
        coinsRepo.rollbackCalls.single.assets.map((asset) => asset.id).toSet(),
        {platformAsset.id},
      );
      expect(coinsRepo.rollbackCalls.single.deleteCustomTokens, isEmpty);
    });

    test(
      'reset rolls back preview token and parent, deleting new token',
      () async {
        await _setTrc20Input(bloc);
        await _fetchPreview(bloc);

        final resetState = bloc.stream.firstWhere(
          (state) => state.formStatus == FormStatus.initial,
        );
        bloc.add(const ResetFormStatusEvent());
        await resetState;

        expect(coinsRepo.rollbackCalls, hasLength(1));
        expect(
          coinsRepo.rollbackCalls.single.assets
              .map((asset) => asset.id)
              .toSet(),
          {platformAsset.id, tokenAsset.id},
        );
        expect(coinsRepo.rollbackCalls.single.deleteCustomTokens, {
          tokenAsset.id,
        });
        expect(coinsRepo.rollbackCalls.single.removeWalletMetadataAssets, {
          platformAsset.id,
          tokenAsset.id,
        });
        expect(assetManager.available.containsKey(tokenAsset.id), isFalse);
      },
    );

    test('close rolls back preview token and parent', () async {
      await _setTrc20Input(bloc);
      await _fetchPreview(bloc);

      await bloc.close();

      expect(coinsRepo.rollbackCalls, hasLength(1));
      expect(
        coinsRepo.rollbackCalls.single.assets.map((asset) => asset.id).toSet(),
        {platformAsset.id, tokenAsset.id},
      );
    });

    test('pre-existing preview asset is not deleted on reset', () async {
      assetManager.addAsset(tokenAsset);
      auth.user = auth.user!.copyWith(
        metadata: {
          'activated_coins': <String>[platformAsset.id.id, tokenAsset.id.id],
        },
      );
      await _setTrc20Input(bloc);
      await _fetchPreview(bloc);

      final resetState = bloc.stream.firstWhere(
        (state) => state.formStatus == FormStatus.initial,
      );
      bloc.add(const ResetFormStatusEvent());
      await resetState;

      expect(coinsRepo.rollbackCalls, hasLength(1));
      expect(coinsRepo.rollbackCalls.single.deleteCustomTokens, isEmpty);
      expect(
        coinsRepo.rollbackCalls.single.removeWalletMetadataAssets,
        isEmpty,
      );
      expect(assetManager.available.containsKey(tokenAsset.id), isTrue);
    });

    test('preview rollback preserves saved parent metadata', () async {
      auth.user = auth.user!.copyWith(
        metadata: {
          'activated_coins': <String>[platformAsset.id.id],
        },
      );
      await _setTrc20Input(bloc);
      await _fetchPreview(bloc);

      final resetState = bloc.stream.firstWhere(
        (state) => state.formStatus == FormStatus.initial,
      );
      bloc.add(const ResetFormStatusEvent());
      await resetState;

      expect(coinsRepo.rollbackCalls, hasLength(1));
      expect(coinsRepo.rollbackCalls.single.deleteCustomTokens, {
        tokenAsset.id,
      });
      expect(coinsRepo.rollbackCalls.single.removeWalletMetadataAssets, {
        tokenAsset.id,
      });
    });

    test(
      'import success keeps preview activation and skips rollback on close',
      () async {
        await _setTrc20Input(bloc);
        await _fetchPreview(bloc);

        final importState = bloc.stream.firstWhere(
          (state) => state.importStatus == FormStatus.success,
        );
        bloc.add(const SubmitImportCustomTokenEvent());
        await importState;

        expect(repository.importCalls, 1);
        expect(analyticsRepo.queuedEvents, hasLength(1));

        await bloc.close();

        expect(coinsRepo.rollbackCalls, isEmpty);
      },
    );
  });
}
