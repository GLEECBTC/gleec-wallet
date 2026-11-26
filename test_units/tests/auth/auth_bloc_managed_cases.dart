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

    for (final automatic in [false, true]) {
      test(
        'a stored unlock this device lost points a generated password to '
        'the recovery phrase${automatic ? ', automatically too' : ''}',
        () async {
          final user = await s.installManaged();
          s.vault.values.clear();
          final state = await s.outcomeOf(
            AuthManagedSignInRequested(
              wallet: user.wallet,
              automatic: automatic,
              generatedPassword: true,
            ),
          );
          expect(state.authError?.message, 'authManagedUnlockGoneGenerated');
          expect(managedUnlockGone(state.authError), isTrue);
          expect(state.currentUser, isNull);
          expect(s.engine.signInModes, isEmpty);
        },
      );
    }

    test(
      'a stored unlock this device lost asks for a chosen password',
      () async {
        final user = await s.installManaged();
        s.vault.values.clear();
        final state = await s.outcomeOf(
          AuthManagedSignInRequested(wallet: user.wallet),
        );
        expect(state.authError?.message, 'authManagedUnlockGone');
        expect(managedUnlockGone(state.authError), isTrue);
      },
    );

    test('a stored unlock the system invalidated is gone', () async {
      final user = await s.installManaged();
      s.vault.readFailure = WalletAccessFailure.invalidated;
      final state = await s.outcomeOf(
        AuthManagedSignInRequested(
          wallet: user.wallet,
          generatedPassword: true,
        ),
      );
      expect(state.authError?.message, 'authManagedUnlockGoneGenerated');
      expect(managedUnlockGone(state.authError), isTrue);
    });

    test(
      'a cancelled unlock of a generated password points to the phrase',
      () async {
        final user = await s.installManaged();
        s.vault.cancelReads = true;
        final state = await s.outcomeOf(
          AuthManagedSignInRequested(
            wallet: user.wallet,
            generatedPassword: true,
          ),
        );
        expect(state.authError?.message, 'authManagedUnlockCanceledGenerated');
        expect(managedUnlockGone(state.authError), isFalse);
      },
    );

    test(
      'a failed unlock suggests the password only when the owner chose it',
      () async {
        final user = await s.installManaged();
        s.engine.password = 'Different-password-0!';
        final generated = await s.outcomeOf(
          AuthManagedSignInRequested(
            wallet: user.wallet,
            generatedPassword: true,
          ),
        );
        expect(
          generated.authError?.message,
          'authManagedUnlockFailedGenerated',
        );
        expect(managedUnlockGone(generated.authError), isFalse);

        final chosen = await s.outcomeOf(
          AuthManagedSignInRequested(wallet: user.wallet),
        );
        expect(chosen.authError?.message, 'authManagedUnlockFailed');
      },
    );

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
    group('managed import', () {
      WalletTransferSecret secret({
        TransferWalletType type = TransferWalletType.hd,
        bool confirmed = true,
      }) => WalletTransferSecret(
        walletName: 'Moved',
        type: type,
        seed: 'moved seed words',
        phraseConfirmed: confirmed,
      );

      test(
        'a moved wallet opens with this device keeping its password',
        () async {
          final state = await s.outcomeOf(
            AuthManagedImportRequested(
              secret: secret(),
              walletName: 'Moved',
              source: ManagedImportSource.movedFromDevice,
            ),
          );
          expect(state.authError, isNull);
          expect(state.currentUser?.walletId.name, 'Moved');
          final entry = WalletAccessService.entryId(state.currentUser!);
          expect(s.engine.seeds[entry], 'moved seed words');
          expect(s.engine.password, hasLength(32));
          expect(s.engine.active?.metadata['wallet_provenance'], 'imported');
          expect(
            s.engine.active?.metadata['recovery_evidence'],
            RecoveryEvidence.phraseConfirmed.name,
          );
        },
      );

      test('an unconfirmed phrase stays unconfirmed after the move', () async {
        final state = await s.outcomeOf(
          AuthManagedImportRequested(
            secret: secret(confirmed: false),
            walletName: 'Moved',
            source: ManagedImportSource.passkeyBackup,
          ),
        );
        expect(
          state.currentUser?.metadata['recovery_evidence'],
          RecoveryEvidence.none.name,
        );
      });

      test('a legacy wallet opens with legacy derivation', () async {
        final state = await s.outcomeOf(
          AuthManagedImportRequested(
            secret: secret(type: TransferWalletType.legacy),
            walletName: 'Moved',
            source: ManagedImportSource.movedFromDevice,
          ),
        );
        expect(
          state.currentUser?.walletId.authOptions.derivationMethod,
          DerivationMethod.iguana,
        );
      });

      test('a taken name is reported, never renamed', () async {
        s.engine.add(name: 'Moved');
        final state = await s.outcomeOf(
          AuthManagedImportRequested(
            secret: secret(),
            walletName: 'Moved',
            source: ManagedImportSource.movedFromDevice,
          ),
        );
        expect(state.authError?.type, AuthExceptionType.walletAlreadyExists);
        expect(state.currentUser, isNull);
        expect(s.engine.active, isNull);
      });
    });
  });
}
