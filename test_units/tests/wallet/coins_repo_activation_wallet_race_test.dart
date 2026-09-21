import 'dart:async';

import '../../helpers/runtime_auth_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_sdk/src/pubkeys/pubkey_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/bloc/trading_status/app_geo_status.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';

void main() => testCoinsRepoActivationWalletRace();

void testCoinsRepoActivationWalletRace() {
  final asset = Asset.fromJson({
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
  });
  final walletA = _wallet('a');
  final walletB = _wallet('b');

  group('CoinsRepo activation wallet races', () {
    late _Auth auth;
    late _Sdk sdk;
    late _Repo repo;
    late _TradingStatus policy;
    late List<Coin> events;
    setUp(() {
      auth = _Auth(walletA);
      sdk = _Sdk(auth, asset);
      policy = _TradingStatus();
      repo = _Repo(sdk, policy);
      events = [];
      final subscription = repo.watchCoinActivationState().listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        repo.dispose();
        await sdk.walletAssets.dispose();
        await sdk.states.close();
        await auth.changes.close();
        await policy.changes.close();
      });
    });

    test(
      'session-only activation does not select or create a wallet row',
      () async {
        await sdk.walletAssets.load();
        sdk.publishActive(asset);
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        expect(sdk.walletAssets.current, isEmpty);
        expect(auth.metadataWrites, 0);

        // Selecting the already enabled asset immediately projects its state.
        await sdk.walletAssets.add([asset.id.id]);
        await Future<void>.delayed(Duration.zero);
        expect(events.last.isActive, isTrue);
        expect(sdk.activationCalls, 0);
        await sdk.walletAssets.remove([asset.id.id]);
        await Future<void>.delayed(Duration.zero);
        expect(events.last.isInactive, isTrue);
      },
    );

    test('a silent consumer cannot suppress a selected wallet asset', () async {
      auth.user = auth.user.copyWith(
        metadata: {
          'activated_coins': [asset.id.id],
        },
      );
      await sdk.walletAssets.load();
      sdk.activate = () async {
        sdk.publishActive(asset);
        return true;
      };
      await repo.activateAssetsSync(
        [asset],
        addToWalletMetadata: false,
        notifyListeners: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.any((coin) => coin.isActive), isTrue);
      expect(sdk.walletAssets.current, {asset.id.id});
      expect(auth.metadataWrites, 0);
    });

    test('direct manual addition resumes after policy rejection', () async {
      policy.ready = false;
      sdk.activate = () async {
        if (!policy.ready) {
          throw ActivationPolicyException(
            asset.id,
            ActivationPolicyStatus.loading,
          );
        }
        sdk.publishActive(asset);
        return true;
      };
      final bloc = CoinsBloc(sdk, repo, policy);
      addTearDown(bloc.close);

      // CoinsManager calls the repository directly, bypassing CoinsActivated.
      await expectLater(
        repo.activateAssetsSync([asset]),
        throwsA(isA<ActivationPolicyException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.last.isSuspended, isTrue);
      expect(bloc.state.walletCoins[asset.id.id]?.isActivating, isNot(true));
      expect(sdk.walletAssets.current, {asset.id.id});
      expect(auth.metadataWrites, 1);
      expect(sdk.activationStates, isEmpty);

      final recovered = bloc.stream.firstWhere(
        (state) => state.walletCoins[asset.id.id]?.isActive ?? false,
      );
      policy.ready = true;
      policy.changes.add(const AppGeoStatus());
      await recovered.timeout(const Duration(seconds: 2));
      expect(sdk.activationCalls, 2);
      expect(auth.metadataWrites, 1);
    });

    for (final succeeds in [true, false]) {
      test(
        'late ${succeeds ? 'success' : 'failure'} cannot affect wallet B',
        () async {
          final started = Completer<void>();
          final result = Completer<bool>();
          sdk.activate = () {
            if (!started.isCompleted) started.complete();
            return result.future;
          };
          final pending = expectLater(
            repo.activateAssetsSync(
              [asset],
              addToWalletMetadata: false,
              maxRetryAttempts: 3,
              initialRetryDelay: Duration.zero,
            ),
            throwsA(isA<WalletChangedDisconnectException>()),
          );
          await started.future;
          await Future<void>.delayed(Duration.zero);
          events.clear();
          // No stream event: the post-await read must catch this independently.
          auth.user = walletB;
          result.complete(succeeds);
          await pending;
          await Future<void>.delayed(Duration.zero);
          expect(sdk.activationCalls, 1);
          expect(events, isEmpty);
          expect(sdk.balances.watchCalls, 0);
          expect(repo.statusReads, 1);
        },
      );
    }

    test(
      'wallet change during initial status lookup cannot broadcast or activate',
      () async {
        final started = Completer<void>();
        final status = Completer<bool>();
        repo.readStatus = () {
          if (!started.isCompleted) started.complete();
          return status.future;
        };
        final pending = expectLater(
          repo.activateAssetsSync([asset], addToWalletMetadata: false),
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        await started.future;
        auth.user = walletB;
        status.complete(false);
        await pending;
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        expect(sdk.activationCalls, 0);
        expect(sdk.balances.watchCalls, 0);
      },
    );

    test(
      'wallet change during failure recheck cannot suspend wallet B',
      () async {
        final started = Completer<void>();
        final recheck = Completer<bool>();
        sdk.activate = () async => false;
        repo.readStatus = () {
          if (repo.statusReads == 1) return Future.value(false);
          if (!started.isCompleted) started.complete();
          return recheck.future;
        };
        final pending = expectLater(
          repo.activateAssetsSync(
            [asset],
            addToWalletMetadata: false,
            maxRetryAttempts: 1,
          ),
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        await started.future;
        await Future<void>.delayed(Duration.zero);
        events.clear();
        auth.user = walletB;
        recheck.complete(false);
        await pending;
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        expect(sdk.balances.watchCalls, 0);
      },
    );

    test(
      'sign out and back in invalidates the old attempt even with the same ID',
      () async {
        final started = Completer<void>();
        final result = Completer<bool>();
        sdk.activate = () {
          if (!started.isCompleted) started.complete();
          return result.future;
        };
        final pending = expectLater(
          repo.activateAssetsSync([asset], addToWalletMetadata: false),
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        await started.future;
        await Future<void>.delayed(Duration.zero);
        events.clear();
        auth.changes.add(null);
        auth.changes.add(walletA);
        result.complete(true);
        await pending;
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
        expect(sdk.balances.watchCalls, 0);
      },
    );

    for (final disposeRepo in [false, true]) {
      test(
        '${disposeRepo ? 'dispose' : 'flushCache'} invalidates a pending activation',
        () async {
          final started = Completer<void>();
          final result = Completer<bool>();
          sdk.activate = () {
            started.complete();
            return result.future;
          };
          final pending = expectLater(
            repo.activateAssetsSync([asset], addToWalletMetadata: false),
            throwsA(isA<WalletChangedDisconnectException>()),
          );
          await started.future;
          await Future<void>.delayed(Duration.zero);
          events.clear();
          if (disposeRepo) {
            repo.dispose();
          } else {
            repo.flushCache();
          }
          result.complete(true);
          await pending;
          await Future<void>.delayed(Duration.zero);
          expect(events, isEmpty);
          expect(sdk.balances.watchCalls, 0);
          expect(sdk.activationCalls, 1);
        },
      );
    }

    test(
      'same-session identity degradation permits activation without replacing its wallet',
      () async {
        sdk.activate = () async {
          auth.user = walletA.copyWith(
            walletId: WalletId.fromName(
              walletA.walletId.name,
              walletA.walletId.authOptions,
            ),
          );
          auth.changes.add(auth.user);
          return true;
        };
        await repo.activateAssetsSync([asset], addToWalletMetadata: false);
        await Future<void>.delayed(Duration.zero);
        expect(events.last.state, CoinState.active);
        expect(sdk.activationCalls, 1);
        expect(sdk.balances.watchCalls, 1);
      },
    );
  });
}

KdfUser _wallet(String suffix) => KdfUser(
  walletId: WalletId(
    name: 'wallet-$suffix',
    pubkeyHash: 'hash-$suffix',
    authOptions: const AuthOptions(derivationMethod: DerivationMethod.iguana),
  ),
  isBip39Seed: true,
);

class _Auth with RuntimeAuthFixture implements KomodoDefiLocalAuth {
  _Auth(this.user);
  KdfUser user;
  int metadataWrites = 0;
  final changes = StreamController<KdfUser?>.broadcast(sync: true);
  @override
  Future<KdfUser?> get currentUser async => user;
  @override
  Stream<KdfUser?> get authStateChanges => changes.stream;
  @override
  Future<KdfUser> updateMetadataForSession(
    AuthSessionContext session,
    Map<String, dynamic> updates,
  ) async {
    ensureSessionContextCurrent(session);
    metadataWrites++;
    return user = user.copyWith(metadata: {...user.metadata, ...updates});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk implements KomodoDefiSdk {
  _Sdk(this.auth, Asset asset) : assets = _Assets({asset.id: asset});
  @override
  final _Auth auth;
  @override
  final AssetManager assets;
  @override
  late final WalletAssetSelection walletAssets = WalletAssetSelection(auth);
  @override
  final _Balances balances = _Balances();
  @override
  final PubkeyManager pubkeys = _Pubkeys();
  @override
  final activatedAssetsCache = _Cache();
  Future<bool> Function() activate = () async => true;
  int activationCalls = 0;
  @override
  Future<ActivationResult> activateAsset(
    Asset asset, {
    Duration? timeout,
  }) async {
    activationCalls++;
    return await activate()
        ? ActivationResult.success(asset.id)
        : ActivationResult.failure(asset.id, 'Activation failed');
  }

  @override
  final Map<AssetId, AssetActivationState> activationStates = {};
  final states =
      StreamController<Map<AssetId, AssetActivationState>>.broadcast();
  void publishActive(Asset asset) {
    activationStates[asset.id] = AssetActivationState.active(asset.id);
    states.add(Map.of(activationStates));
  }

  @override
  Stream<Map<AssetId, AssetActivationState>> watchActivationStates() =>
      states.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Assets implements AssetManager {
  _Assets(this.available);
  @override
  final Map<AssetId, Asset> available;
  @override
  Set<Asset> findAssetsByConfigId(String id) =>
      available.values.where((asset) => asset.id.id == id).toSet();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo extends CoinsRepo {
  _Repo(_Sdk sdk, _TradingStatus policy)
    : super(
        kdfSdk: sdk,
        mm2: mm2,
        tradingStatusService: policy,
        arrrActivationService: _Arrr(),
      );
  int statusReads = 0;
  Future<bool> Function() readStatus = () async => false;
  @override
  Future<bool> isAssetActivated(AssetId id, {bool forceRefresh = false}) {
    statusReads++;
    return readStatus();
  }
}

class _Balances implements BalanceManager {
  int watchCalls = 0;
  @override
  Future<BalanceInfo> getBalance(
    AssetId id, {
    bool forceRefresh = false,
  }) async => BalanceInfo.zero();
  @override
  Stream<BalanceInfo> watchBalance(AssetId id, {bool activateIfNeeded = true}) {
    watchCalls++;
    return const Stream.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pubkeys implements PubkeyManager {
  @override
  Future<AssetPubkeys> getPubkeys(Asset asset) async => AssetPubkeys(
    assetId: asset.id,
    keys: const [],
    availableAddressesCount: 0,
    syncStatus: SyncStatusEnum.success,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cache implements ActivatedAssetsCache {
  @override
  void invalidate() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TradingStatus implements TradingStatusService {
  final changes = StreamController<AppGeoStatus>.broadcast();
  bool ready = true;
  @override
  Stream<AppGeoStatus> get statusStream => changes.stream;
  @override
  bool get isActivationReady => ready;
  @override
  List<Asset> filterAllowedAssets(List<Asset> assets) => assets;
  @override
  Map<String, T> filterAllowedAssetsMap<T>(
    Map<String, T> assets,
    AssetId Function(T) id,
  ) => assets;

  @override
  bool isAssetBlocked(AssetId assetId) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Arrr implements ArrrActivationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
