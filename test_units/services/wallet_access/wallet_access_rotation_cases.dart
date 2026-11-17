part of 'wallet_access_service_test.dart';

/// A wallet created instantly opens only with its stored credential: nobody
/// has seen its generated password. These cases hold a password change to
/// never putting that credential out of reach while the engine still uses it.
void _rotationCases() {
  group('password change keeps the working credential in reach', () {
    late _Harness h;
    late KdfUser user;
    setUp(() async {
      h = _Harness();
      user = await h.install();
    });
    tearDown(() => h.dispose());

    Future<void> expectFormerCredentialInCharge() async {
      expect(h.auth.enginePassword, _password);
      expect(h.record.rotationEnvelope, isNull);
      expect(h.record.phase, 'ready');
      expect(h.backend.values[_credentialKey], _password);
      final status = await h.service.status();
      expect(status.hasManagedCredential, isTrue);
      expect(await h.service.authorize(walletId: user.walletId), _password);
    }

    test(
      'an app left before the change is journaled journals nothing',
      () async {
        var recordReads = 0;
        h.storage.onRead = (key) {
          // The second read is the change loading its record, after the
          // authorization and before the envelope is sealed and saved.
          if (key == _recordsKey && ++recordReads == 2) {
            h.coordinator.inactive();
          }
        };
        await expectLater(
          h.service.changePassword(
            walletId: user.walletId,
            newPassword: _replacement,
          ),
          _fails(WalletAccessFailure.staleOperation),
        );
        h.storage.onRead = null;
        expect(h.auth.passwordChanges, 0);
        h.coordinator.resume();
        await expectFormerCredentialInCharge();
      },
    );

    test('a change refused at dispatch withdraws its envelope', () async {
      h.auth.passwordChangeReached = Completer<void>();
      h.auth.pendingPasswordChange = Completer<void>();
      final changing = h.service.changePassword(
        walletId: user.walletId,
        newPassword: _replacement,
      );
      final refused = expectLater(
        changing,
        _fails(WalletAccessFailure.staleOperation),
      );
      await h.auth.passwordChangeReached!.future;
      expect(h.record.rotationEnvelope, isNotNull);
      h.coordinator.inactive();
      h.auth.pendingPasswordChange!.complete();
      await refused;
      h.coordinator.resume();
      await expectFormerCredentialInCharge();
    });

    test('a password the engine rejects withdraws its envelope', () async {
      h.auth.passwordChangeReached = Completer<void>();
      h.auth.pendingPasswordChange = Completer<void>();
      final changing = h.service.changePassword(
        walletId: user.walletId,
        newPassword: _replacement,
      );
      final rejected = expectLater(
        changing,
        _authFails(AuthExceptionType.incorrectPassword),
      );
      await h.auth.passwordChangeReached!.future;
      // The engine answers for another password than the one just verified.
      h.auth.enginePassword = 'Engine-Side-Secret-1234!';
      h.auth.pendingPasswordChange!.complete();
      await rejected;
      expect(h.record.rotationEnvelope, isNull);
      expect(h.auth.passwordChanges, 0);
    });

    test('an unclear failure is settled by asking the engine', () async {
      h.auth.failPasswordChange = 'before';
      await expectLater(
        h.service.changePassword(
          walletId: user.walletId,
          newPassword: _replacement,
        ),
        _fails(WalletAccessFailure.storageFailed),
      );
      await expectFormerCredentialInCharge();
    });

    test(
      'a failure reported after the engine changed still completes',
      () async {
        h.auth.failPasswordChange = 'after';
        expect(
          await h.service.changePasswordWithOutcome(
            walletId: user.walletId,
            newPassword: _replacement,
          ),
          PasswordChangeOutcome.completed,
        );
        expect(h.auth.enginePassword, _replacement);
        expect(h.backend.values[_credentialKey], _replacement);
        expect(h.record.rotationEnvelope, isNull);
        expect(
          await h.service.authorize(walletId: user.walletId),
          _replacement,
        );
      },
    );

    test(
      'an unreachable engine keeps the envelope until it can answer',
      () async {
        h.auth.failPasswordChange = 'before';
        h.auth.passwordChangeReached = Completer<void>();
        h.auth.pendingPasswordChange = Completer<void>();
        final changing = h.service.changePassword(
          walletId: user.walletId,
          newPassword: _replacement,
        );
        final failed = expectLater(
          changing,
          _fails(WalletAccessFailure.storageFailed),
        );
        await h.auth.passwordChangeReached!.future;
        h.auth.verificationError = AuthException(
          'KDF is not available. Please try again.',
          type: AuthExceptionType.apiConnectionError,
        );
        h.auth.pendingPasswordChange!.complete();
        await failed;
        expect(h.record.rotationEnvelope, isNotNull);
        // The stored credential is still offered, and using it once the engine
        // answers proves the change never happened.
        expect((await h.service.status()).hasManagedCredential, isTrue);
        await expectLater(
          h.service.authorize(walletId: user.walletId),
          _authFails(AuthExceptionType.apiConnectionError),
        );
        expect(h.record.rotationEnvelope, isNotNull);
        h.auth.verificationError = null;
        expect(await h.service.authorize(walletId: user.walletId), _password);
        await expectFormerCredentialInCharge();
      },
    );

    for (final failure in [
      WalletAccessFailure.canceled,
      WalletAccessFailure.lockedOut,
    ]) {
      for (final step in ['write', 'readback']) {
        test(
          '${failure.name} at the vault $step is not a failed change',
          () async {
            if (step == 'readback') {
              h.backend.readbackFailure = failure;
            } else {
              h.backend.protectedWriteFailure = failure;
            }
            expect(
              await h.service.changePasswordWithOutcome(
                walletId: user.walletId,
                newPassword: _replacement,
              ),
              PasswordChangeOutcome.deviceUnlockNeedsSetup,
            );
            expect(h.auth.enginePassword, _replacement);
            expect(h.record.rotationEnvelope, isNull);
            expect(h.record.managed, isFalse);
            expect(h.record.generated, isFalse);
            final status = await h.service.status();
            expect(status.protection, CredentialProtection.password);
            expect(status.hasManagedCredential, isFalse);
            expect(status.requiresAuthentication, isTrue);
            // The session the user changed the password in stays open.
            expect(h.coordinator.state.isLocked, isFalse);
            expect(h.coordinator.operationGate.allowsOperations, isTrue);
            expect(
              await h.service.authorize(
                walletId: user.walletId,
                password: _replacement,
              ),
              _replacement,
            );
          },
        );
      }
    }

    test(
      'the plain call also completes when only device unlock is lost',
      () async {
        h.backend.protectedWriteFailure = WalletAccessFailure.canceled;
        await h.service.changePassword(
          walletId: user.walletId,
          newPassword: _replacement,
        );
        expect(h.auth.enginePassword, _replacement);
      },
    );

    test(
      'a lock during the vault update is kept, and the change reported',
      () async {
        h.backend.onProtectedWrite = () async => h.coordinator.lock();
        expect(
          await h.service.changePasswordWithOutcome(
            walletId: user.walletId,
            newPassword: _replacement,
          ),
          PasswordChangeOutcome.deviceUnlockNeedsSetup,
        );
        expect(h.auth.enginePassword, _replacement);
        expect(h.coordinator.state.isLocked, isTrue);
        expect(h.coordinator.operationGate.allowsOperations, isFalse);
        expect(h.record.rotationEnvelope, isNull);
        await expectLater(
          h.service.unlockCurrent(password: _password),
          _authFails(AuthExceptionType.incorrectPassword),
        );
        expect(await h.service.unlockCurrent(password: _replacement), isTrue);
      },
    );

    test('an unattended wallet becomes password-protected as before', () async {
      await h.dispose();
      h = _Harness();
      user = await h.install(protected: false);
      expect(h.coordinator.state.requiresAuthentication, isFalse);
      expect(
        await h.service.changePasswordWithOutcome(
          walletId: user.walletId,
          newPassword: _replacement,
        ),
        PasswordChangeOutcome.completed,
      );
      expect(h.backend.values, isEmpty);
      expect(h.record.managed, isFalse);
      expect(h.coordinator.state.requiresAuthentication, isTrue);
      expect(h.coordinator.state.isLocked, isFalse);
    });
  });

  group('a journaled change after the process died', () {
    late _Harness h;
    late KdfUser user;
    setUp(() async {
      h = _Harness();
      user = await h.install();
      await h.journalInterruptedChange();
      h.auth.strictSignIn = true;
    });
    tearDown(() => h.dispose());

    test('the stored credential still signs in and settles it', () async {
      await h.restart();
      expect(
        (await h.service.statusForWallet(user.wallet)).hasManagedCredential,
        isTrue,
      );
      expect(await h.service.signInManaged(user.wallet), user);
      expect(h.record.rotationEnvelope, isNull);
      expect(h.record.phase, 'ready');
      expect(h.coordinator.operationGate.allowsOperations, isTrue);
    });

    test('the stored credential still authorizes in the session', () async {
      expect(await h.service.authorize(walletId: user.walletId), _password);
      expect(h.record.rotationEnvelope, isNull);
    });

    test('a credential the engine outgrew asks for the new password', () async {
      h.auth.enginePassword = _replacement;
      await expectLater(
        h.service.authorize(walletId: user.walletId),
        _fails(WalletAccessFailure.missingCredential),
      );
      await h.restart();
      await expectLater(
        h.service.signInManaged(user.wallet),
        _fails(WalletAccessFailure.missingCredential),
      );
      expect(h.auth.active, isNull);
      expect(h.record.rotationEnvelope, isNotNull);
      // Recovery signs in once and hands that session over: a second
      // sign-in would be refused as already signed in.
      final recovered = await h.service.recoverPasswordRotation(
        user.wallet,
        _replacement,
      );
      expect(recovered, user);
      expect(h.auth.active, user);
      await h.service.didAuthenticate(recovered!, password: _replacement);
      expect(h.record.rotationEnvelope, isNull);
      expect(h.backend.values[_credentialKey], _replacement);
      expect(h.coordinator.operationGate.allowsOperations, isTrue);
    });

    test('the new password applies a change the engine never made', () async {
      await h.restart();
      final recovered = await h.service.recoverPasswordRotation(
        user.wallet,
        _replacement,
      );
      expect(recovered, user);
      expect(h.auth.enginePassword, _replacement);
      expect(h.auth.passwordChanges, 1);
      expect(h.backend.values[_credentialKey], _replacement);
      expect(h.record.rotationEnvelope, isNull);
      await h.service.didAuthenticate(recovered!, password: _replacement);
    });

    test(
      'a recovery that fails leaves the engine signed out for a retry',
      () async {
        await h.restart();
        h.auth.failPasswordChange = 'before';
        await expectLater(
          h.service.recoverPasswordRotation(user.wallet, _replacement),
          _fails(WalletAccessFailure.storageFailed),
        );
        expect(h.auth.active, isNull);
        expect(h.auth.enginePassword, _password);
        expect(
          await h.service.recoverPasswordRotation(user.wallet, _replacement),
          user,
        );
        expect(h.auth.enginePassword, _replacement);
      },
    );

    test(
      'recovery interrupted after sign-in still hands the session over',
      () async {
        h.auth.enginePassword = _replacement;
        await h.restart();
        h.auth.signInReached = Completer<void>();
        h.auth.pendingSignIn = Completer<void>();
        final recovering = h.service.recoverPasswordRotation(
          user.wallet,
          _replacement,
        );
        await h.auth.signInReached!.future;
        h.coordinator.inactive();
        h.auth.pendingSignIn!.complete();
        expect(await recovering, user);
        // Nothing was repaired on an expired authorization.
        expect(h.backend.values[_credentialKey], _password);
        expect(h.record.rotationEnvelope, isNotNull);
      },
    );

    test(
      'the former password signs in normally and nothing is recovered',
      () async {
        await h.restart();
        expect(
          await h.service.recoverPasswordRotation(user.wallet, _password),
          isNull,
        );
        expect(h.auth.active, isNull);
        expect(h.auth.signIns, 0);
      },
    );
  });

  group('password sign-in without anything to recover', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('the other derivation mode is not a missing wallet', () async {
      final user = await h.install();
      await h.restart();
      final switched = user.wallet.copyWith(
        config: user.wallet.config.copyWith(type: WalletType.iguana),
      );
      expect(
        await h.service.recoverPasswordRotation(switched, _password),
        isNull,
      );
      expect(h.auth.signIns, 0);
    });

    test('a wallet without a record, or an unknown one, has nothing', () async {
      final user = _user();
      h.auth.users.add(user);
      expect(
        await h.service.recoverPasswordRotation(user.wallet, _password),
        isNull,
      );
      expect(
        await h.service.recoverPasswordRotation(
          _user(name: 'Elsewhere').wallet,
          _password,
        ),
        isNull,
      );
    });
  });
}
