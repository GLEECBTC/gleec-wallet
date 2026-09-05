import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/mm2/mm2.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/arrr_activation/arrr_activation_service.dart';
import 'package:web_dex/services/arrr_activation/arrr_config.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/storage/base_storage.dart';

void testWalletOperationIdentity() {
  group('Wallet operation identity', () {
    late _FakeAuth auth;
    late _FakeSdk sdk;
    late _FakeArrrActivationService activation;
    late CoinsRepo repo;
    late List<Coin> events;

    final arrr = Asset.fromJson(<String, dynamic>{
      'coin': 'ARRR',
      'fname': 'Pirate Chain',
      'chain_id': 1,
      'type': 'ZHTLC',
      'light_wallet_d_servers': <Map<String, dynamic>>[],
    });

    setUp(() {
      auth = _FakeAuth(_user('Original'));
      sdk = _FakeSdk(auth);
      activation = _FakeArrrActivationService();
      repo = CoinsRepo(
        kdfSdk: sdk,
        mm2: mm2,
        tradingStatusService: _UnusedTradingStatusService(),
        arrrActivationService: activation,
      );
      events = [];
      final subscription = repo.watchCoinActivationState().listen(events.add);
      addTearDown(() async {
        await subscription.cancel();
        repo.dispose();
      });
    });

    test(
      'queued ZHTLC metadata rejection cannot suspend the replacement wallet',
      () async {
        final originalWalletId = auth.user.walletId;
        final metadataStarted = Completer<void>();
        final metadataGate = Completer<void>();
        auth.beforeMetadataWrite = () async {
          metadataStarted.complete();
          await metadataGate.future;
        };
        activation.result.complete(
          const ArrrActivationResultSuccess(Stream<ActivationProgress>.empty()),
        );
        final finished = expectLater(
          repo.activateAssetsSync([arrr]),
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        await metadataStarted.future.timeout(const Duration(seconds: 2));
        final replacement = _user('Replacement');
        auth.user = replacement;
        metadataGate.complete();
        await finished;
        await Future<void>.delayed(Duration.zero);

        expect(auth.metadataWriteWalletIds, [originalWalletId]);
        expect(auth.user, same(replacement));
        expect(events, isEmpty);
      },
    );

    for (final succeeds in [false, true]) {
      test(
        'late ZHTLC ${succeeds ? 'success' : 'failure'} cannot change replacement activation state',
        () async {
          final finished = expectLater(
            repo.activateAssetsSync([arrr], addToWalletMetadata: false),
            throwsA(isA<WalletChangedDisconnectException>()),
          );
          await activation.started.future.timeout(const Duration(seconds: 2));
          auth.user = _user('Replacement');
          activation.result.complete(
            succeeds
                ? const ArrrActivationResultSuccess(
                    Stream<ActivationProgress>.empty(),
                  )
                : const ArrrActivationResultError('Activation failed'),
          );
          await finished;
          await Future<void>.delayed(Duration.zero);

          expect(auth.metadataWriteWalletIds, isEmpty);
          expect(events, isEmpty);
        },
      );
    }

    test(
      'matching name-only identity cannot authorize wallet export',
      () async {
        final fullUser = auth.user;
        auth.user = fullUser.copyWith(
          walletId: WalletId.fromName(
            fullUser.walletId.name,
            fullUser.walletId.authOptions,
          ),
        );
        final fileLoader = _RecordingFileLoader();
        final repository = WalletsRepository(
          sdk,
          _UnusedMm2Api(),
          _UnusedStorage(),
          fileLoader: fileLoader,
        );

        await expectLater(
          repository.downloadEncryptedWallet(
            auth.user.wallet,
            'password',
            expectedWalletId: auth.user.walletId,
          ),
          throwsA(isA<WalletChangedDisconnectException>()),
        );

        expect(fileLoader.savedFileNames, isEmpty);
      },
    );

    test(
      'a mnemonic returned after wallet replacement cannot be exported',
      () async {
        final original = auth.user;
        final mnemonicStarted = Completer<void>();
        final mnemonicGate = Completer<Mnemonic>();
        auth.readMnemonic = () {
          mnemonicStarted.complete();
          return mnemonicGate.future;
        };
        final fileLoader = _RecordingFileLoader();
        final repository = WalletsRepository(
          sdk,
          _UnusedMm2Api(),
          _UnusedStorage(),
          fileLoader: fileLoader,
        );

        final finished = expectLater(
          repository.downloadEncryptedWallet(
            original.wallet,
            'password',
            expectedWalletId: original.walletId,
          ),
          throwsA(isA<WalletChangedDisconnectException>()),
        );
        await mnemonicStarted.future.timeout(const Duration(seconds: 2));
        auth.user = _user('Replacement');
        mnemonicGate.complete(
          Mnemonic.plaintext('replacement recovery phrase'),
        );
        await finished;

        expect(fileLoader.savedFileNames, isEmpty);
      },
    );
  });
}

KdfUser _user(String name) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    name,
    const AuthOptions(derivationMethod: DerivationMethod.iguana),
    'pubkey-$name',
  ),
  isBip39Seed: true,
);

class _FakeAuth implements KomodoDefiLocalAuth {
  _FakeAuth(this.user);

  KdfUser user;
  Future<void> Function()? beforeMetadataWrite;
  Future<Mnemonic> Function()? readMnemonic;
  final List<WalletId> metadataWriteWalletIds = [];

  @override
  Future<KdfUser?> get currentUser async => user;

  @override
  Future<void> updateActiveUserKeyValue(
    String key,
    dynamic Function(dynamic currentValue) transform, {
    required WalletId expectedWalletId,
  }) async {
    metadataWriteWalletIds.add(expectedWalletId);
    await beforeMetadataWrite?.call();
    if (user.walletId != expectedWalletId) {
      throw const WalletChangedDisconnectException('Wallet changed');
    }
    final metadata = Map<String, dynamic>.from(user.metadata);
    metadata[key] = transform(metadata[key]);
    user = user.copyWith(metadata: metadata);
  }

  @override
  Future<Mnemonic> getMnemonicPlainText(String walletPassword) =>
      readMnemonic!();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk(this.auth);

  @override
  final KomodoDefiLocalAuth auth;

  @override
  final ActivatedAssetsCache activatedAssetsCache =
      _EmptyActivatedAssetsCache();

  @override
  Map<AssetId, AssetActivationState> get activationStates => const {};

  @override
  Stream<Map<AssetId, AssetActivationState>> watchActivationStates() =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EmptyActivatedAssetsCache implements ActivatedAssetsCache {
  @override
  Future<List<Asset>> getActivatedAssets({bool forceRefresh = false}) async =>
      [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeArrrActivationService implements ArrrActivationService {
  final started = Completer<void>();
  final result = Completer<ArrrActivationResult>();

  @override
  Future<ArrrActivationResult> activateArrr(
    Asset asset, {
    ZhtlcUserConfig? initialConfig,
  }) {
    started.complete();
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingFileLoader implements FileLoader {
  final List<String> savedFileNames = [];

  @override
  Future<void> save({
    required String fileName,
    required String data,
    required LoadFileType type,
  }) async {
    savedFileNames.add(fileName);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedMm2Api implements Mm2Api {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedTradingStatusService implements TradingStatusService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedStorage implements BaseStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
