part of 'wallet_access_service_test.dart';

/// The engine's session and what the app shows must not come apart: a failed
/// sign-in over a signed-in engine refuses every retry as already signed in.
void _sessionCases() {
  group('a managed sign-in that outlives its authorization', () {
    late _Harness h;
    late KdfUser user;

    Future<void> start({bool protected = true}) async {
      h = _Harness();
      user = await h.install(protected: protected);
      await h.restart();
      h.auth.strictSignIn = true;
      h.auth.signInReached = Completer<void>();
      h.auth.pendingSignIn = Completer<void>();
    }

    tearDown(() => h.dispose());

    test('is shown covered after focus was lost, never as a failure', () async {
      await start();
      final signingIn = h.service.signInManaged(user.wallet);
      await h.auth.signInReached!.future;
      h.coordinator.inactive();
      h.auth.pendingSignIn!.complete();
      expect(await signingIn, user);
      expect(h.auth.active, user);
      expect(h.auth.signOuts, 0);
      // Attached, but nothing was unlocked on an expired authorization.
      expect(h.coordinator.state.walletEntryId, _entry);
      expect(h.coordinator.state.isLocked, isTrue);
      h.coordinator.resume();
      expect(h.coordinator.state.coversContent, isTrue);
      expect(h.coordinator.operationGate.allowsOperations, isFalse);
      expect((await h.service.lastWallet())?.name, user.walletId.name);
      expect(await h.service.unlockCurrent(), isTrue);
      expect(h.coordinator.operationGate.allowsOperations, isTrue);
    });

    test('keeps the device lock that interrupted it', () async {
      await start();
      final signingIn = h.service.signInManaged(user.wallet);
      await h.auth.signInReached!.future;
      h.backend.deviceEvents.add(null);
      h.auth.pendingSignIn!.complete();
      expect(await signingIn, user);
      h.coordinator.resume();
      expect(h.coordinator.state.isLocked, isTrue);
      expect(h.coordinator.operationGate.allowsOperations, isFalse);
    });

    test('attaches an unattended wallet as any observed session', () async {
      await start(protected: false);
      final signingIn = h.service.signInManaged(user.wallet);
      await h.auth.signInReached!.future;
      h.coordinator.inactive();
      h.auth.pendingSignIn!.complete();
      expect(await signingIn, user);
      h.coordinator.resume();
      expect(h.coordinator.state.requiresAuthentication, isFalse);
      expect(h.coordinator.state.hasWallet, isTrue);
    });

    test(
      'signs the engine out when superseded, so the next one works',
      () async {
        await start();
        final signingIn = h.service.signInManaged(user.wallet);
        final superseded = expectLater(
          signingIn,
          _fails(WalletAccessFailure.staleOperation),
        );
        await h.auth.signInReached!.future;
        h.service.invalidatePendingOperations();
        h.auth.pendingSignIn!.complete();
        await superseded;
        expect(h.auth.active, isNull);
        expect(h.coordinator.state.hasWallet, isFalse);
        h.auth.pendingSignIn = null;
        expect(await h.service.signInManaged(user.wallet), user);
        expect(h.coordinator.operationGate.allowsOperations, isTrue);
      },
    );

    test('signs the engine out when its completion cannot be stored', () async {
      await start();
      h.auth.pendingSignIn = null;
      h.storage.failWrite = _lastKey;
      await expectLater(
        h.service.signInManaged(user.wallet),
        _fails(WalletAccessFailure.storageFailed),
      );
      expect(h.auth.active, isNull);
      h.storage.failWrite = null;
      expect(await h.service.signInManaged(user.wallet), user);
    });

    test('is shown covered while the engine cannot confirm it', () async {
      await start();
      h.auth.pendingSignIn = null;
      h.auth.verificationError = AuthException(
        'KDF is not available. Please try again.',
        type: AuthExceptionType.apiConnectionError,
      );
      expect(await h.service.signInManaged(user.wallet), user);
      expect(h.auth.active, user);
      expect(h.coordinator.state.isLocked, isTrue);
      await expectLater(
        h.service.unlockCurrent(),
        _authFails(AuthExceptionType.apiConnectionError),
      );
      h.auth.verificationError = null;
      expect(await h.service.unlockCurrent(), isTrue);
    });
  });

  group('a typed sign-in the engine finished too late', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('can be attached covered and then unlocked', () async {
      final user = await h.install();
      await h.restart();
      final attempt = h.service.captureAuthenticationAttempt();
      h.coordinator.inactive();
      h.auth.activate(user);
      await expectLater(
        h.service.didAuthenticate(
          user,
          expectedAttempt: attempt,
          password: _password,
        ),
        _fails(WalletAccessFailure.staleOperation),
      );
      expect(h.coordinator.state.hasWallet, isFalse);
      await h.service.attachCoveredSession(user);
      h.coordinator.resume();
      expect(h.coordinator.state.isLocked, isTrue);
      expect(h.coordinator.operationGate.allowsOperations, isFalse);
      expect(await h.storage.read(_signedOutKey), isFalse);
      expect(await h.service.unlockCurrent(password: _password), isTrue);
    });

    test('is not attached for a wallet the engine does not hold', () async {
      final user = await h.install();
      await h.restart();
      await expectLater(
        h.service.attachCoveredSession(user),
        _fails(WalletAccessFailure.staleOperation),
      );
      h.auth.activate(_user(id: 'replacement-entry'));
      await expectLater(
        h.service.attachCoveredSession(user),
        _fails(WalletAccessFailure.staleOperation),
      );
      expect(h.coordinator.state.hasWallet, isFalse);
    });
  });

  group('switching the derivation mode of a wallet with a record', () {
    const otherHash = '2222222222222222222222222222222222222222';
    late _Harness h;
    late KdfUser hd;
    late KdfUser iguana;
    setUp(() async {
      h = _Harness();
      hd = await h.install();
      await h.restart();
      // The engine names the same seed differently in each mode.
      iguana = KdfUser(
        walletId: WalletId.withPubkeyHash(
          'Wallet',
          const AuthOptions(derivationMethod: DerivationMethod.iguana),
          otherHash,
        ),
        isBip39Seed: true,
        // As in the app, the type in metadata keeps naming the first mode.
        metadata: hd.metadata,
      );
      h.auth.users[0] = iguana;
      h.auth.activate(iguana);
    });
    tearDown(() => h.dispose());

    test(
      'a verified password carries the record to the new identity',
      () async {
        await h.service.didAuthenticate(iguana, password: _password);
        expect(h.coordinator.operationGate.allowsOperations, isTrue);
        expect(h.record.pubkeyHash, otherHash);
        final status = await h.service.status();
        expect(status.hasManagedCredential, isTrue);
        expect(status.protection, CredentialProtection.authenticationBound);
        // The stored credential keeps opening the wallet in this mode, also
        // from a wallet list that still names the first one.
        await h.restart();
        expect(iguana.wallet.config.type, WalletType.hdwallet);
        expect(
          (await h.service.statusForWallet(iguana.wallet)).hasManagedCredential,
          isTrue,
        );
        expect(await h.service.signInManaged(iguana.wallet), iguana);
        expect(
          await h.service.credentialForDeletion(
            iguana.wallet,
            password: _password,
          ),
          _password,
        );
      },
    );

    test('an unverified session cannot rebind the record', () async {
      await expectLater(
        h.service.status(),
        _fails(WalletAccessFailure.invalidResponse),
      );
      await h.service.observeEngineUser(iguana);
      expect(h.record.pubkeyHash, _hash);
      expect(h.coordinator.state.isLocked, isTrue);
      await expectLater(
        h.service.didAuthenticate(iguana, password: 'Wrong-password-000000!'),
        _authFails(AuthExceptionType.incorrectPassword),
      );
      expect(h.record.pubkeyHash, _hash);
    });
  });

  group('changes reported by another tab', () {
    late _Harness h;
    late KdfUser user;
    setUp(() async {
      h = _Harness();
      user = await h.install();
    });
    tearDown(() => h.dispose());

    test('for another wallet leave this session and its work alone', () async {
      h.auth.verificationReached = Completer<void>();
      h.auth.pendingVerification = Completer<void>();
      final authorizing = h.service.authorize(walletId: user.walletId);
      await h.auth.verificationReached!.future;
      h.backend.protectionEvents.add('gleec.wallet.another-entry');
      h.auth.pendingVerification!.complete();
      expect(await authorizing, _password);
      expect(h.coordinator.state.isLocked, isFalse);
      expect(h.coordinator.operationGate.allowsOperations, isTrue);
    });

    for (final key in [_credentialKey, null]) {
      test(
        'for ${key == null ? 'an unnamed wallet' : 'this wallet'} lock it',
        () async {
          h.auth.verificationReached = Completer<void>();
          h.auth.pendingVerification = Completer<void>();
          final authorizing = h.service.authorize(walletId: user.walletId);
          final revoked = expectLater(
            authorizing,
            _fails(WalletAccessFailure.staleOperation),
          );
          await h.auth.verificationReached!.future;
          h.backend.protectionEvents.add(key);
          h.auth.pendingVerification!.complete();
          await revoked;
          expect(h.coordinator.operationGate.allowsOperations, isFalse);
        },
      );
    }

    test('lock a sign-in in progress, whose wallet is not yet known', () async {
      await h.restart();
      h.auth.signInReached = Completer<void>();
      h.auth.pendingSignIn = Completer<void>();
      final signingIn = h.service.signInManaged(user.wallet);
      final revoked = expectLater(
        signingIn,
        _fails(WalletAccessFailure.staleOperation),
      );
      await h.auth.signInReached!.future;
      h.backend.protectionEvents.add('gleec.wallet.another-entry');
      h.auth.pendingSignIn!.complete();
      await revoked;
      expect(h.auth.active, isNull);
    });
  });

  group('explicit sign-out', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('is recorded even when another tab moves the revision', () async {
      await h.install();
      h.backend.pendingCancel = Completer<void>();
      h.backend.cancelReached = Completer<void>();
      final signingOut = h.service.signOut();
      await h.backend.cancelReached!.future;
      h.backend.protectionEvents.add(_credentialKey);
      h.backend.pendingCancel!.complete();
      await signingOut;
      // The engine is about to stop; the next launch must not walk back in.
      expect(await h.service.automaticEntrySuppressed, isTrue);
      expect(await h.service.lastWallet(), isNull);
      expect(await h.service.unlockCurrent(password: _password), isFalse);
    });
  });

  group('background lock timing', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    test('offers exactly the choices of the lock policy', () {
      expect(walletLockGraceOptions.map((option) => option.inSeconds), [
        0,
        30,
        300,
        900,
      ]);
    });

    for (final option in walletLockGraceOptions) {
      test('keeps ${option.inSeconds}s across a restart', () async {
        await h.service.setBackgroundGrace(option);
        expect(h.coordinator.backgroundGrace, option);
        expect(
          await h.storage.read('wallet_access_grace_seconds_v1'),
          option.inSeconds,
        );
        await h.restart();
        expect(h.coordinator.backgroundGrace, option);
      });
    }

    for (final stored in <Object?>[null, 45, -1, 3600, '300', 30.5]) {
      test('falls back to the default for a stored $stored', () async {
        if (stored != null) {
          h.storage.values['wallet_access_grace_seconds_v1'] = stored;
        }
        await h.restart();
        expect(h.coordinator.backgroundGrace, walletLockGraceDefault);
      });
    }

    test(
      'falls back to the default for a duration that is not offered',
      () async {
        await h.service.setBackgroundGrace(const Duration(minutes: 5));
        await h.service.setBackgroundGrace(const Duration(hours: 1));
        expect(h.coordinator.backgroundGrace, walletLockGraceDefault);
        expect(
          await h.storage.read('wallet_access_grace_seconds_v1'),
          walletLockGraceDefault.inSeconds,
        );
      },
    );

    test(
      'a longer choice keeps a short absence unlocked and still expires',
      () async {
        await h.install();
        await h.service.setBackgroundGrace(const Duration(minutes: 5));
        h.coordinator.background();
        h.monotonic += const Duration(minutes: 4, seconds: 59);
        h.coordinator.resume();
        expect(h.coordinator.state.isLocked, isFalse);
        h.coordinator.background();
        h.monotonic += const Duration(minutes: 5);
        h.coordinator.resume();
        expect(h.coordinator.state.isLocked, isTrue);
      },
    );
  });
}
