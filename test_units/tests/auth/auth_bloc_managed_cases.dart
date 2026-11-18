part of 'auth_bloc_test.dart';

/// Managed sign-in whose outcome each test chooses.
class _ManagedAccess extends _FakeWalletAccess {
  _ManagedAccess(this.outcome);
  final Future<KdfUser> Function() outcome;
  final requests = <bool>[];
  int invalidations = 0;

  @override
  void invalidatePendingOperations() => invalidations++;

  @override
  Future<KdfUser> signInManaged(Wallet wallet, {bool automatic = false}) {
    requests.add(automatic);
    return outcome();
  }
}

void _managedSignInCases() {
  group('AuthBloc managed sign-in', () {
    late _FakeSdk sdk;
    const canceled = WalletAccessException(WalletAccessFailure.canceled);

    setUp(() {
      sdk = _FakeSdk(_FakeAuth());
      WalletLoadTimeline.instance.reset();
    });

    AuthBloc build(_ManagedAccess access) {
      final bloc = AuthBloc(
        sdk,
        _FakeWalletsRepository(),
        _FakeSettingsRepository(),
        _FakeTradingStatusService(),
        walletAccessService: access,
      );
      addTearDown(bloc.close);
      return bloc;
    }

    Future<AuthBlocState> outcomeOf(AuthBloc bloc, AuthBlocEvent event) {
      final settled = bloc.stream
          .firstWhere((state) => !state.isLoading)
          .timeout(const Duration(seconds: 2));
      bloc.add(event);
      return settled;
    }

    test('a cancelled automatic unlock reports nothing', () async {
      final bloc = build(_ManagedAccess(() async => throw canceled));
      final state = await outcomeOf(
        bloc,
        AuthManagedSignInRequested(wallet: _wallet(), automatic: true),
      );
      expect(state.isError, isFalse);
      expect(state.authError, isNull);
      expect(state.currentUser, isNull);
    });

    test('a cancelled explicit unlock still says it was cancelled', () async {
      final bloc = build(_ManagedAccess(() async => throw canceled));
      final state = await outcomeOf(
        bloc,
        AuthManagedSignInRequested(wallet: _wallet()),
      );
      expect(state.authError?.message, startsWith('Unlock canceled'));
    });

    test('asking again for the open wallet changes nothing', () async {
      final user = _user();
      final access = _ManagedAccess(() async => user);
      final bloc = build(access);
      final opened = await outcomeOf(
        bloc,
        AuthManagedSignInRequested(wallet: user.wallet, automatic: true),
      );
      expect(opened.currentUser, user);
      final invalidations = access.invalidations;
      final states = <AuthBlocState>[];
      final subscription = bloc.stream.listen(states.add);
      bloc.add(AuthManagedSignInRequested(wallet: user.wallet));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();
      expect(states, isEmpty);
      expect(bloc.state, opened);
      expect(access.requests, [true]);
      expect(access.invalidations, invalidations);
    });
  });
}
