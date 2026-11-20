import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_main/wallet_main.dart';

final _walletA = _wallet('wallet-a', 'seed-a');
final _walletB = _wallet('wallet-b', 'seed-b');

WalletId _wallet(String name, String hash) => WalletId.withPubkeyHash(
  name,
  const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
  hash,
);

class _Auth extends Fake implements KomodoDefiLocalAuth {
  _Auth() {
    replace(_walletA);
  }

  final sessions = AuthSessionTracker();
  Completer<AuthSessionContext>? capture;

  void replace(WalletId? wallet) {
    sessions.invalidate();
    if (wallet != null) {
      sessions.observe(KdfUser(walletId: wallet, isBip39Seed: true));
    }
  }

  @override
  Future<AuthSessionContext> captureSessionContext() async =>
      capture?.future ??
      sessions.current ??
      (throw const AuthSessionChangedException());

  @override
  bool isSessionContextCurrent(AuthSessionContext session) =>
      sessions.isCurrent(session);
}

class _Sdk extends Fake implements KomodoDefiSdk {
  @override
  final _Auth auth = _Auth();
}

class _Read {
  final started = Completer<void>();
  final result = Completer<List<Coin>>();
}

class _Harness {
  _Harness() {
    loader = WalletDataLoader(
      sdk,
      loadCoins: () {
        final read = reads[readCount++];
        read.started.complete();
        return read.result.future;
      },
    );
  }

  final sdk = _Sdk();
  final reads = [_Read(), _Read()];
  final publications = <WalletId>[];
  int readCount = 0;
  bool mounted = true;
  WalletId? viewWallet = _walletA;
  late final WalletDataLoader loader;

  Future<void> load(WalletId wallet) => loader.load(
    walletId: wallet,
    isViewCurrent: () => mounted && viewWallet == wallet,
    publish: (_) => publications.add(wallet),
  );
}

void main() {
  group('wallet data publication', () {
    test('normal loads and refreshes each publish once', () async {
      final h = _Harness();
      for (final read in h.reads) {
        final pending = h.load(_walletA);
        await read.started.future;
        read.result.complete([]);
        await pending;
      }
      expect(h.publications, [_walletA, _walletA]);
    });

    test('clear cancels a held producer and permits a later load', () async {
      final h = _Harness();
      final old = h.load(_walletA);
      await h.reads[0].started.future;
      h.loader.invalidate();
      h.reads[0].result.complete([]);
      await old;
      expect(h.publications, isEmpty);

      final next = h.load(_walletA);
      await h.reads[1].started.future;
      h.reads[1].result.complete([]);
      await next;
      expect(h.publications, [_walletA]);
    });

    test('late wallet A cannot replace wallet B subscriptions', () async {
      final h = _Harness();
      final old = h.load(_walletA);
      await h.reads[0].started.future;
      h.sdk.auth.replace(_walletB);
      h.viewWallet = _walletB;
      final next = h.load(_walletB);
      await h.reads[1].started.future;
      h.reads[1].result.complete([]);
      await next;
      h.reads[0].result.complete([]);
      await old;
      expect(h.publications, [_walletB]);
    });

    test('a newer refresh supersedes the same session\'s held load', () async {
      final h = _Harness();
      final old = h.load(_walletA);
      await h.reads[0].started.future;
      final next = h.load(_walletA);
      await h.reads[1].started.future;
      h.reads[1].result.complete([]);
      await next;
      h.reads[0].result.complete([]);
      await old;
      expect(h.publications, [_walletA]);
    });

    for (final wallet in [null, _walletA, _wallet('wallet-a', 'new-seed')]) {
      test(
        'session replacement with $wallet cancels the old producer',
        () async {
          final h = _Harness();
          final pending = h.load(_walletA);
          await h.reads[0].started.future;
          // No UI notification: the SDK session itself must revoke the result.
          h.sdk.auth.replace(wallet);
          h.reads[0].result.complete([]);
          await pending;
          expect(h.publications, isEmpty);
        },
      );
    }

    test('a disposed view never publishes after its lookup finishes', () async {
      final h = _Harness();
      final pending = h.load(_walletA);
      await h.reads[0].started.future;
      h.mounted = false;
      h.loader.invalidate();
      h.reads[0].result.complete([]);
      await pending;
      expect(h.publications, isEmpty);
    });

    test(
      'clear while capturing the session prevents even the coin read',
      () async {
        final h = _Harness();
        final session = h.sdk.auth.sessions.current!;
        h.sdk.auth.capture = Completer<AuthSessionContext>();
        final pending = h.load(_walletA);
        h.loader.invalidate();
        h.sdk.auth.capture!.complete(session);
        await pending;
        expect(h.readCount, 0);
        expect(h.publications, isEmpty);
      },
    );

    test(
      'a stale same-name wallet request cannot use the new identity',
      () async {
        final h = _Harness();
        h.sdk.auth.replace(_wallet('wallet-a', 'new-seed'));
        await h.load(_walletA);
        expect(h.readCount, 0);
        expect(h.publications, isEmpty);
      },
    );
  });
}
