import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
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
    late List<Coin> events;
    setUp(() {
      auth = _Auth(walletA);
      sdk = _Sdk(auth);
      repo = _Repo(sdk);
      events = [];
      final subscription = repo.watchCoinActivationState().listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        repo.dispose();
        await auth.changes.close();
      });
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

class _Auth implements KomodoDefiLocalAuth {
  _Auth(this.user);
  KdfUser user;
  final changes = StreamController<KdfUser?>.broadcast(sync: true);
  @override
  Future<KdfUser?> get currentUser async => user;
  @override
  Stream<KdfUser?> get authStateChanges => changes.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk implements KomodoDefiSdk {
  _Sdk(this.auth);
  @override
  final _Auth auth;
  @override
  final _Balances balances = _Balances();
  @override
  final activatedAssetsCache = _Cache();
  Future<bool> Function() activate = () async => true;
  int activationCalls = 0;
  @override
  Future<bool> ensureAssetActivated(Asset asset, {Duration? timeout}) {
    activationCalls++;
    return activate();
  }

  @override
  Map<AssetId, AssetActivationState> get activationStates => const {};
  @override
  Stream<Map<AssetId, AssetActivationState>> watchActivationStates() =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo extends CoinsRepo {
  _Repo(_Sdk sdk)
    : super(
        kdfSdk: sdk,
        mm2: mm2,
        tradingStatusService: _TradingStatus(),
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
  Stream<BalanceInfo> watchBalance(AssetId id, {bool activateIfNeeded = true}) {
    watchCalls++;
    return const Stream.empty();
  }

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
  @override
  bool isAssetBlocked(AssetId assetId) => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Arrr implements ArrrActivationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
