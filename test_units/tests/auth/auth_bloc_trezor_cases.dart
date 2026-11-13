part of 'auth_bloc_test.dart';

/// Trezor setup writes wallet metadata once the SDK sign-in stream has ended.
void _trezorSignInCases() {
  group('AuthBloc Trezor sign-in', () {
    late _FakeAuth auth;
    late AuthBloc bloc;

    setUp(() {
      auth = _FakeAuth()
        ..userToReturn = _trezorUser
        ..signInStates = [
          const AuthenticationState(
            status: AuthenticationStatus.initializing,
            message: 'Initializing',
          ),
          AuthenticationState.completed(_trezorUser),
        ];
      final sdk = _FakeSdk(auth);
      addTearDown(sdk.walletAssets.dispose);
      bloc = AuthBloc(
        sdk,
        _FakeWalletsRepository(),
        _FakeSettingsRepository(),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);
    });

    test('a first sign-in saves the default coins', () async {
      final loggedIn = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.logIn,
      );
      bloc.add(const AuthTrezorInitAndAuthStarted());

      final state = await loggedIn.timeout(const Duration(seconds: 2));

      expect(
        auth.userToReturn!.metadata['activated_coins'],
        unorderedEquals(enabledByDefaultCoins),
      );
      expect(state.currentUser!.metadata, containsPair('type', 'trezor'));
    });

    test('an existing coin selection is preserved', () async {
      final existingUser = _trezorUser.copyWith(
        metadata: {
          'activated_coins': ['GLEEC'],
        },
      );
      auth
        ..userToReturn = existingUser
        ..signInStates = [AuthenticationState.completed(existingUser)];
      final loggedIn = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.logIn,
      );
      bloc.add(const AuthTrezorInitAndAuthStarted());

      final state = await loggedIn.timeout(const Duration(seconds: 2));

      expect(state.currentUser!.metadata['activated_coins'], ['GLEEC']);
      expect(auth.userToReturn!.metadata['activated_coins'], ['GLEEC']);
    });

    test('an app resume during setup does not publish the wallet', () async {
      auth.signInStates = [
        const AuthenticationState(
          status: AuthenticationStatus.waitingForDeviceConfirmation,
          message: 'Confirm on device',
        ),
        AuthenticationState.completed(_trezorUser),
      ];
      final setupStarted = Completer<void>();
      final setupGate = Completer<void>();
      auth.onSetKeyValue = (key, _) async {
        if (key != 'type') return;
        setupStarted.complete();
        await setupGate.future;
      };
      final firstUser = bloc.stream.firstWhere(
        (state) => state.currentUser != null,
      );
      bloc.add(const AuthTrezorInitAndAuthStarted());
      await setupStarted.future;

      bloc.add(AuthStateRestoreRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      setupGate.complete();

      final state = await firstUser.timeout(const Duration(seconds: 2));
      expect(state.currentUser!.metadata, containsPair('type', 'trezor'));
    });

    test('a wallet change during setup is logged, not signed in', () async {
      auth.onSetKeyValue = (key, _) async {
        if (key == 'activated_coins') {
          auth.userToReturn = _user(name: 'Wallet 2');
        }
      };
      final warned = Logger.root.onRecord.firstWhere(
        (record) =>
            record.loggerName == 'AuthBloc' &&
            record.level == Level.WARNING &&
            record.error is WalletChangedDisconnectException,
      );
      bloc.add(const AuthTrezorInitAndAuthStarted());

      await warned.timeout(const Duration(seconds: 2));

      expect(bloc.state.currentUser, isNull);
      expect(auth.userToReturn!.metadata['activated_coins'], isNull);
    });
  });
}

final _trezorUser = KdfUser(
  walletId: WalletId.withPubkeyHash(
    'My Trezor',
    const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
      privKeyPolicy: PrivateKeyPolicy.trezor(),
    ),
    'pubkey-trezor',
  ),
  isBip39Seed: false,
);
