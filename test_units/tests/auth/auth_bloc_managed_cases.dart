part of 'auth_bloc_test.dart';

void _managedSignInCases() {
  group('AuthBloc managed sign-in', () {
    late _Session s;
    setUp(() {
      s = _Session();
      WalletLoadTimeline.instance.reset();
    });
    tearDown(() => s.dispose());

    test('a cancelled automatic unlock reports nothing', () async {
      final user = await s.installManaged();
      s.vault.cancelReads = true;
      final state = await s.outcomeOf(
        AuthManagedSignInRequested(wallet: user.wallet, automatic: true),
      );
      expect(state.isError, isFalse);
      expect(state.authError, isNull);
      expect(state.currentUser, isNull);
      expect(s.engine.active, isNull);
      s.vault.cancelReads = false;
      final opened = await s.outcomeOf(
        AuthManagedSignInRequested(wallet: user.wallet),
      );
      expect(opened.authError, isNull);
      expect(opened.currentUser, s.engine.active);
    });

    test('a cancelled explicit unlock still says it was cancelled', () async {
      final user = await s.installManaged();
      s.vault.cancelReads = true;
      final state = await s.outcomeOf(
        AuthManagedSignInRequested(wallet: user.wallet),
      );
      expect(state.authError?.message, 'authManagedUnlockCanceled');
    });

    test('asking again for the open wallet changes nothing', () async {
      final user = await s.installManaged();
      final opened = await s.outcomeOf(
        AuthManagedSignInRequested(wallet: user.wallet, automatic: true),
      );
      expect(opened.currentUser, s.engine.active);
      final states = <AuthBlocState>[];
      final subscription = s.bloc.stream.listen(states.add);
      s.bloc.add(AuthManagedSignInRequested(wallet: user.wallet));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();
      expect(states, isEmpty);
      expect(s.bloc.state, opened);
      expect(s.engine.signInModes, hasLength(1));
      expect(s.engine.signOuts, 0);
      expect(s.coordinator.operationGate.allowsOperations, isTrue);
    });

    test('an unlock completes a session the engine already holds', () async {
      final user = await s.installManaged();
      // Opened by an earlier request whose result the app never showed.
      s.engine._activate(user);
      final state = await s.outcomeOf(
        AuthManagedSignInRequested(wallet: user.wallet),
      );
      expect(state.authError, isNull);
      expect(state.currentUser, s.engine.active);
      expect(s.engine.signInModes, isEmpty);
      expect(s.engine.signOuts, 0);
      expect(s.coordinator.operationGate.allowsOperations, isTrue);
    });

    test(
      'a held session the stored password does not open is closed',
      () async {
        final user = await s.installManaged();
        s.engine._activate(user);
        s.engine.password = 'Different-password-0!';
        final state = await s.outcomeOf(
          AuthManagedSignInRequested(wallet: user.wallet),
        );
        expect(state.authError?.message, 'authManagedUnlockFailed');
        expect(s.engine.active, isNull);
      },
    );
  });
}
