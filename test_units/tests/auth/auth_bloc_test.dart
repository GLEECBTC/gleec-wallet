import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// `KomodoDefiSdk.auth` is typed as the concrete `KomodoDefiLocalAuth`, which
// the SDK barrel does not re-export, so faking it means importing the package
// directly - the same reach the coins-bloc suites make into SDK internals.
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/analytics/wallet_load_timeline.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/model/wallet.dart';

/// `AuthBloc` had no test at all, which is how `_onLogIn` stayed the one auth
/// path that never got the optimistic emit its three siblings have.
///
/// These pin the properties that make the optimistic path safe: `loggedIn` is
/// emitted before metadata work, the wallet the user sees is the one KDF
/// returned, a failure still produces a typed error, and the watcher cannot
/// overwrite the optimistic user while the finalizer is still running.
void testAuthBloc() {
  group('AuthBloc sign-in', () {
    late _FakeAuth auth;
    late _FakeSdk sdk;

    AuthBloc buildBloc() {
      final bloc = AuthBloc(
        sdk,
        _FakeWalletsRepository(),
        _FakeSettingsRepository(),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);
      return bloc;
    }

    setUp(() {
      auth = _FakeAuth();
      sdk = _FakeSdk(auth);
      WalletLoadTimeline.instance.reset();
    });

    test('emits loggedIn without waiting on post-login metadata work', () async {
      // Metadata is deliberately incomplete, so `_repairMissingWalletMetadata`
      // has work to do. It must not be on the path to `loggedIn`.
      auth.userToReturn = _user(metadata: const {});
      final metadataGate = Completer<void>();
      auth.onSetKeyValue = (_, _) => metadataGate.future;

      final bloc = buildBloc();
      final loggedIn = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.logIn,
      );

      bloc.add(AuthSignInRequested(wallet: _wallet(), password: 'pw'));

      // Resolves only if the emit does not await the metadata write, which is
      // still blocked on `metadataGate`.
      final state = await loggedIn.timeout(const Duration(seconds: 2));
      expect(state.currentUser, isNotNull);
      expect(state.currentUser!.walletId.name, 'Wallet 1');

      metadataGate.complete();
    });

    test(
      'uses the user returned by signIn rather than re-fetching it',
      () async {
        auth.userToReturn = _user(metadata: const {'type': 'hdwallet'});

        final bloc = buildBloc();
        final loggedIn = bloc.stream.firstWhere(
          (state) => state.mode == AuthorizeMode.logIn,
        );
        bloc.add(AuthSignInRequested(wallet: _wallet(), password: 'pw'));
        await loggedIn.timeout(const Duration(seconds: 2));

        expect(auth.signInCalls, 1);
        // The two `currentUser` round trips this path used to make were asking
        // KDF to repeat what `signIn` had just returned.
        expect(auth.currentUserReads, 0);
      },
    );

    test(
      'records the auth window between signin_started and signed_in',
      () async {
        auth.userToReturn = _user(metadata: const {'type': 'hdwallet'});

        final bloc = buildBloc();
        final loggedIn = bloc.stream.firstWhere(
          (state) => state.mode == AuthorizeMode.logIn,
        );
        bloc.add(AuthSignInRequested(wallet: _wallet(), password: 'pw'));
        await loggedIn.timeout(const Duration(seconds: 2));

        expect(
          WalletLoadTimeline.instance.elapsedMsBetween(
            WalletLoadMark.signInStarted,
            WalletLoadMark.signedIn,
          ),
          isNotNull,
        );
      },
    );

    test('preserves the typed exception for an incorrect password', () async {
      auth.errorToThrow = AuthException(
        'Incorrect password',
        type: AuthExceptionType.incorrectPassword,
      );

      final bloc = buildBloc();
      final errored = bloc.stream.firstWhere(
        (state) => state.authError != null,
      );
      bloc.add(AuthSignInRequested(wallet: _wallet(), password: 'wrong'));

      final state = await errored.timeout(const Duration(seconds: 2));
      // Mapping this to a generic error is what would cost the UI its ability
      // to say "that password didn't open this wallet".
      expect(state.authError!.type, AuthExceptionType.incorrectPassword);
    });

    test('wraps a non-auth exception as a general auth error', () async {
      auth.errorToThrow = StateError('kdf unreachable');

      final bloc = buildBloc();
      final errored = bloc.stream.firstWhere(
        (state) => state.authError != null,
      );
      bloc.add(AuthSignInRequested(wallet: _wallet(), password: 'pw'));

      final state = await errored.timeout(const Duration(seconds: 2));
      expect(state.authError!.type, AuthExceptionType.generalAuthError);
    });

    test('rejects a legacy wallet without calling signIn', () async {
      final bloc = buildBloc();
      final errored = bloc.stream.firstWhere(
        (state) => state.authError != null,
      );

      bloc.add(
        AuthSignInRequested(wallet: _wallet(isLegacy: true), password: 'pw'),
      );

      await errored.timeout(const Duration(seconds: 2));
      expect(auth.signInCalls, 0);
    });

    test('a watcher emission does not drop optimistic metadata', () async {
      auth.userToReturn = _user(
        metadata: const {'type': 'hdwallet', 'has_backup': true},
      );

      final bloc = buildBloc();
      final loggedIn = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.logIn,
      );
      bloc.add(AuthSignInRequested(wallet: _wallet(), password: 'pw'));
      await loggedIn.timeout(const Duration(seconds: 2));

      // What the SDK watcher replays after login: the same wallet, but bare.
      auth.emitToWatcher(_user(metadata: const {}));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.currentUser?.metadata['has_backup'], true);
    });
  });

  group('AuthBloc seed import', () {
    late _FakeAuth auth;
    late _FakeSdk sdk;

    AuthBloc buildBloc() {
      final bloc = AuthBloc(
        sdk,
        _FakeWalletsRepository(),
        _FakeSettingsRepository(),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);
      return bloc;
    }

    setUp(() {
      auth = _FakeAuth();
      sdk = _FakeSdk(auth);
      WalletLoadTimeline.instance.reset();
    });

    test('a name collision errors instead of silently signing in', () async {
      // The restore path signs into the existing wallet here, which discards
      // the seed the user just typed. Import must not do that.
      auth.userToReturn = _user();

      final bloc = buildBloc();
      final errored = bloc.stream.firstWhere((state) => state.isError);
      bloc.add(
        AuthImportRequested(wallet: _wallet(), password: 'pw', seed: 'a b c'),
      );

      final state = await errored.timeout(const Duration(seconds: 2));
      expect(state.authError?.type, AuthExceptionType.walletAlreadyExists);
      expect(auth.signInCalls, 0);
    });

    test('fails closed when the collision check itself fails', () async {
      // Proceeding on an unverifiable lookup would reintroduce exactly the
      // risk the check exists to remove.
      auth.getUsersError = StateError('storage unavailable');

      final bloc = buildBloc();
      final errored = bloc.stream.firstWhere((state) => state.isError);
      bloc.add(
        AuthImportRequested(wallet: _wallet(), password: 'pw', seed: 'a b c'),
      );

      await errored.timeout(const Duration(seconds: 2));
      expect(auth.signInCalls, 0);
    });
  });

  group('AuthBloc seed backup confirmation', () {
    late _FakeAuth auth;
    late AuthBloc bloc;

    setUp(() {
      auth = _FakeAuth();
      bloc = AuthBloc(
        _FakeSdk(auth),
        _FakeWalletsRepository(),
        _FakeSettingsRepository(),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);
    });

    Future<void> selectUser(KdfUser user) async {
      auth.userToReturn = user;
      final selected = bloc.stream.firstWhere(
        (state) => state.currentUser?.walletId == user.walletId,
      );
      bloc.add(AuthModeChanged(mode: AuthorizeMode.logIn, currentUser: user));
      await selected;
    }

    test(
      'a stale confirmation never writes replacement wallet metadata',
      () async {
        final original = _user();
        final replacement = _user(name: 'Wallet 2');
        await selectUser(replacement);
        final replacementState = bloc.state;

        bloc.add(AuthSeedBackupConfirmed(expectedWalletId: original.walletId));
        await Future<void>.delayed(Duration.zero);

        expect(auth.metadataWriteWalletIds, isEmpty);
        expect(bloc.state, same(replacementState));
      },
    );

    test(
      'an SDK wallet switch before its auth event prevents the write',
      () async {
        final original = _user();
        await selectUser(original);
        auth.userToReturn = _user(name: 'Wallet 2');
        final originalState = bloc.state;

        bloc.add(AuthSeedBackupConfirmed(expectedWalletId: original.walletId));
        await Future<void>.delayed(Duration.zero);

        expect(auth.metadataWriteWalletIds, isEmpty);
        expect(bloc.state, same(originalState));
      },
    );

    test(
      'confirmation forwards wallet identity and publishes saved metadata',
      () async {
        final original = _user();
        await selectUser(original);
        auth.onSetKeyValue = (key, value) async {
          expect(key, 'has_backup');
          expect(value, isTrue);
          auth.userToReturn = _user(metadata: const {'has_backup': true});
        };
        final confirmed = bloc.stream.firstWhere(
          (state) => state.currentUser?.metadata['has_backup'] == true,
        );

        bloc.add(AuthSeedBackupConfirmed(expectedWalletId: original.walletId));
        await confirmed;

        expect(auth.metadataWriteWalletIds, [original.walletId]);
      },
    );

    for (final rejectsStaleWrite in [false, true]) {
      test(
        'wallet switch during ${rejectsStaleWrite ? 'rejected' : 'completed'} '
        'backup write cannot emit stale success',
        () async {
          final original = _user();
          final replacement = _user(name: 'Wallet 2');
          await selectUser(original);
          final writeStarted = Completer<void>();
          final writeGate = Completer<void>();
          auth.onSetKeyValue = (_, _) async {
            writeStarted.complete();
            await writeGate.future;
            if (rejectsStaleWrite) {
              throw const WalletChangedDisconnectException('Wallet changed');
            }
          };

          bloc.add(
            AuthSeedBackupConfirmed(expectedWalletId: original.walletId),
          );
          await writeStarted.future;
          await selectUser(replacement);
          final replacementState = bloc.state;
          writeGate.complete();
          await Future<void>.delayed(Duration.zero);

          expect(auth.metadataWriteWalletIds, [original.walletId]);
          expect(bloc.state, same(replacementState));
          expect(bloc.state.currentUser?.metadata['has_backup'], isNull);
        },
      );
    }
  });

  group('AuthBloc sign-out', () {
    test('clears state and resets the load timeline', () async {
      final auth = _FakeAuth()..userToReturn = _user();
      final sdk = _FakeSdk(auth);
      final bloc = AuthBloc(
        sdk,
        _FakeWalletsRepository(),
        _FakeSettingsRepository(),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);

      final loggedIn = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.logIn,
      );
      bloc.add(AuthSignInRequested(wallet: _wallet(), password: 'pw'));
      await loggedIn.timeout(const Duration(seconds: 2));

      final loggedOut = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.noLogin && !state.isLoading,
      );
      bloc.add(AuthSignOutRequested());
      final state = await loggedOut.timeout(const Duration(seconds: 2));

      expect(state.currentUser, isNull);
      expect(auth.signOutCalls, 1);
      // Left set, the next login would measure time-to-first-balance from the
      // previous session's sign-in.
      expect(
        WalletLoadTimeline.instance.elapsedMsBetween(
          WalletLoadMark.signedIn,
          WalletLoadMark.firstBalance,
        ),
        isNull,
      );
    });

    test('still clears local state when KDF sign-out throws', () async {
      final auth = _FakeAuth()
        ..userToReturn = _user()
        ..signOutError = StateError('kdf did not stop');
      final sdk = _FakeSdk(auth);
      final bloc = AuthBloc(
        sdk,
        _FakeWalletsRepository(),
        _FakeSettingsRepository(),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);

      final loggedIn = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.logIn,
      );
      bloc.add(AuthSignInRequested(wallet: _wallet(), password: 'pw'));
      await loggedIn.timeout(const Duration(seconds: 2));

      final loggedOut = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.noLogin && !state.isLoading,
      );
      bloc.add(AuthSignOutRequested());
      final state = await loggedOut.timeout(const Duration(seconds: 2));

      // A wallet the user cannot log out of is worse than a noisy log line.
      expect(state.currentUser, isNull);
    });
  });
}

Wallet _wallet({bool isLegacy = false}) => Wallet(
  id: 'wallet-1',
  name: 'Wallet 1',
  config: WalletConfig(
    type: WalletType.hdwallet,
    activatedCoins: const [],
    hasBackup: true,
    seedPhrase: '',
    isLegacyWallet: isLegacy,
  ),
);

KdfUser _user({String name = 'Wallet 1', JsonMap metadata = const {}}) =>
    KdfUser(
      walletId: WalletId.fromName(
        name,
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      ),
      isBip39Seed: true,
      metadata: metadata,
    );

class _FakeAuth implements KomodoDefiLocalAuth {
  final StreamController<KdfUser?> _watcher =
      StreamController<KdfUser?>.broadcast();

  KdfUser? userToReturn;
  Object? errorToThrow;
  Object? signOutError;
  Object? getUsersError;
  int signInCalls = 0;
  int signOutCalls = 0;
  int currentUserReads = 0;
  final List<WalletId?> metadataWriteWalletIds = [];
  Future<void> Function(String key, dynamic value)? onSetKeyValue;

  void emitToWatcher(KdfUser? user) => _watcher.add(user);

  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
  }) async {
    signInCalls++;
    if (errorToThrow != null) throw errorToThrow!;
    return userToReturn ?? _user();
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (signOutError != null) throw signOutError!;
  }

  @override
  Future<KdfUser?> get currentUser async {
    currentUserReads++;
    return userToReturn;
  }

  @override
  Stream<KdfUser?> watchCurrentUser() => _watcher.stream;

  @override
  Future<List<KdfUser>> getUsers() async {
    if (getUsersError != null) throw getUsersError!;
    return userToReturn == null ? const [] : [userToReturn!];
  }

  @override
  Future<void> setOrRemoveActiveUserKeyValue(
    String key,
    dynamic value, {
    WalletId? expectedWalletId,
  }) async {
    metadataWriteWalletIds.add(expectedWalletId);
    final handler = onSetKeyValue;
    if (handler != null) await handler(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk(this.auth);

  @override
  final KomodoDefiLocalAuth auth;

  @override
  void connectStreaming() {}

  @override
  Future<void> disconnectStreaming() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWalletsRepository implements WalletsRepository {
  @override
  void invalidateCache() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<StoredSettings> loadSettings() async => StoredSettings.initial();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTradingStatusService implements TradingStatusService {
  @override
  bool isAssetBlocked(AssetId assetId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
