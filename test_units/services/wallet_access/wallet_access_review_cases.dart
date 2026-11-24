part of 'wallet_access_service_test.dart';

const _unreadable = {'version': 99, 'entryId': 'later-build-entry'};

void _reviewCases() {
  group('a device credential the system took away', () {
    late _Harness h;
    late KdfUser user;
    setUp(() async {
      h = _Harness();
      user = await h.install();
      h.backend.deviceAuthentication = true;
    });
    tearDown(() => h.dispose());

    for (final lost in ['invalidated', 'missing']) {
      test('reports the password as what protects it, key $lost', () async {
        if (lost == 'invalidated') {
          h.backend.metadataFailure = WalletAccessFailure.invalidated;
        } else {
          h.backend.infos.clear();
          h.backend.values.clear();
        }
        await h.service.didAuthenticate(user, password: _password);
        final status = await h.service.status();
        // The app offers device unlock for a wallet the password protects.
        expect(status.protection, CredentialProtection.password);
        expect(status.hasManagedCredential, isFalse);
        expect(status.requiresAuthentication, isTrue);
        expect(status.generatedPassword, isTrue);
      });
    }

    test('can be enrolled again through the repair of its key', () async {
      h.backend.metadataFailure = WalletAccessFailure.invalidated;
      await h.service.didAuthenticate(user, password: _password);
      h.backend.metadataFailure = null;
      h.backend.protectedWriteFailure = WalletAccessFailure.invalidated;
      await h.service.enrollDevice(
        walletId: user.walletId,
        password: _password,
      );
      expect(h.backend.repairs, 1);
      final status = await h.service.status();
      expect(status.hasManagedCredential, isTrue);
      expect(status.protection, CredentialProtection.authenticationBound);
      expect(h.coordinator.operationGate.allowsOperations, isTrue);
    });
  });

  group('a record this build cannot read', () {
    late _Harness h;
    late KdfUser user;
    setUp(() async {
      h = _Harness();
      user = await h.install();
    });
    tearDown(() => h.dispose());

    Future<void> store(Object? records) =>
        h.storage.write(_recordsKey, records);

    for (final other in <Object>[
      _unreadable,
      {'version': 1, 'entryId': 'later-build-entry', 'walletName': 7},
      {
        'version': 1,
        'entryId': 'later-build-entry',
        'walletName': 'Other',
        'protection': 'hardwareKey',
      },
      'not a record',
    ]) {
      test('of another wallet costs this one nothing: $other', () async {
        await store({...h.storedRecords, 'later-build-entry': other});
        await h.restart();
        h.auth.strictSignIn = true;
        expect(
          (await h.service.statusForWallet(user.wallet)).hasManagedCredential,
          isTrue,
        );
        expect(
          await h.service.recoverPasswordRotation(user.wallet, _password),
          isNull,
        );
        expect(await h.service.signInManaged(user.wallet), user);
        await h.service.recordPasswordManagerOutcome(
          walletId: user.walletId,
          outcome: PasswordManagerOutcome.accepted,
        );
        expect(h.record.manager, PasswordManagerOutcome.accepted);
        // Skipped, never rewritten or dropped.
        expect(h.storedRecords['later-build-entry'], other);
      });
    }

    test(
      'of this wallet still lets its password in, as password-only',
      () async {
        await store({
          _entry: {...h.record.toJson(), 'version': 99},
        });
        final stored = jsonEncode(h.storage.values[_recordsKey]);
        await h.restart();
        h.auth.strictSignIn = true;
        await expectLater(
          h.service.statusForWallet(user.wallet),
          _fails(WalletAccessFailure.invalidResponse),
        );
        await expectLater(
          h.service.signInManaged(user.wallet),
          _fails(WalletAccessFailure.invalidResponse),
        );
        expect(
          await h.service.recoverPasswordRotation(user.wallet, _password),
          isNull,
        );
        final signedIn = await h.auth.signIn(
          walletName: user.walletId.name,
          password: _password,
        );
        await h.service.didAuthenticate(signedIn, password: _password);
        final status = await h.service.status();
        expect(status.protection, CredentialProtection.password);
        expect(status.hasManagedCredential, isFalse);
        expect(status.requiresAuthentication, isTrue);
        expect(h.coordinator.operationGate.allowsOperations, isTrue);
        // Nothing is enrolled over a record a later build may still need.
        await expectLater(
          h.service.enrollDevice(walletId: user.walletId, password: _password),
          _fails(WalletAccessFailure.invalidResponse),
        );
        expect(jsonEncode(h.storage.values[_recordsKey]), stored);
      },
    );

    test('at all still lets a password in and is never overwritten', () async {
      await store('not a journal');
      await h.restart();
      h.auth.strictSignIn = true;
      expect(
        await h.service.recoverPasswordRotation(user.wallet, _password),
        isNull,
      );
      final signedIn = await h.auth.signIn(
        walletName: user.walletId.name,
        password: _password,
      );
      await h.service.didAuthenticate(signedIn, password: _password);
      expect(h.coordinator.operationGate.allowsOperations, isTrue);
      await h.service.signOut();
      await h.service.observeEngineUser(null);
      h.auth.active = null;
      await expectLater(
        h.service.createWallet(initialMetadata: {}),
        _fails(WalletAccessFailure.invalidResponse),
      );
      expect(h.storage.values[_recordsKey], 'not a journal');
      expect(h.auth.registrations, isEmpty);
    });

    test('keeps an observed session covered instead of failing it', () async {
      await store({
        _entry: {...h.record.toJson(), 'version': 99},
      });
      await h.restart();
      h.auth.activate(user);
      await h.service.observeEngineUser(user);
      expect(h.coordinator.state.walletEntryId, _entry);
      expect(h.coordinator.state.isLocked, isTrue);
      expect(await h.service.unlockCurrent(password: _password), isTrue);
    });
  });

  group('removing a wallet whose stored credential is gone', () {
    late _Harness h;
    late KdfUser user;
    late WalletsRepository repository;
    late List<String> deletionPasswords;
    setUp(() async {
      h = _Harness();
      user = await h.install();
      deletionPasswords = [];
      h.sdk.deletionManager = WalletDeletionManager(
        readWallets: () async => h.auth.users,
        pendingTransfers: _NoPendingTransfers(),
        deleteWallet:
            ({
              required walletName,
              required password,
              required validateTarget,
            }) async {
              await validateTarget(user);
              RpcDispatchGuard.ensureCurrent('delete_wallet');
              deletionPasswords.add(password);
              // Only the engine decides whether the password removes it.
              if (password != h.auth.enginePassword) {
                throw AuthException(
                  'Incorrect password',
                  type: AuthExceptionType.incorrectPassword,
                );
              }
              h.auth.users.remove(user);
              h.auth.active = null;
              for (final hook in h.auth.hooks) {
                await hook(user.walletId);
              }
            },
      );
      repository = WalletsRepository(
        h.sdk,
        _Mm2Api(),
        h.storage,
        walletAccess: h.service,
        fileLoader: _FileLoader(),
      );
    });
    tearDown(() => h.dispose());

    Future<WalletDeletionResult> delete(String password) async {
      final review = await repository.prepareWalletDeletion(user.wallet);
      final proof = await h.service.credentialForDeletion(
        user.wallet,
        password: password,
      );
      return repository.deleteWallet(
        user.wallet,
        password: proof,
        acknowledgedReview: review,
      );
    }

    Future<bool> intentJournaled() =>
        WalletCredentialCleanup(h.storage, h.backend).hasIntents;

    test('an invalidated key is still authorized for removal', () async {
      h.backend.metadataFailure = WalletAccessFailure.invalidated;
      final proof = await h.service.credentialForDeletion(
        user.wallet,
        password: _password,
      );
      expect(proof, _password);
      expect(h.backend.prepares, 1);
      expect(await intentJournaled(), isTrue);
    });

    test(
      'a missing vault item needs no authorization and goes with it',
      () async {
        h.backend.infos.clear();
        h.backend.values.clear();
        expect((await delete(_password)).status, WalletDeletionStatus.deleted);
        expect(h.backend.prepares, 0);
        expect(h.auth.users, isEmpty);
        expect(h.storage.values[_recordsKey], isEmpty);
        expect(await intentJournaled(), isFalse);
      },
    );

    for (final lost in ['missing', 'invalidated']) {
      test('a wrong password removes nothing, vault item $lost', () async {
        if (lost == 'missing') {
          h.backend.infos.clear();
          h.backend.values.clear();
        } else {
          h.backend.metadataFailure = WalletAccessFailure.invalidated;
        }
        final records = jsonEncode(h.storage.values[_recordsKey]);
        await expectLater(
          delete('Wrong-password-000000!'),
          _authFails(AuthExceptionType.incorrectPassword),
        );
        expect(deletionPasswords, ['Wrong-password-000000!']);
        expect(h.auth.users, [user]);
        expect(h.backend.deletes, 0);
        expect(jsonEncode(h.storage.values[_recordsKey]), records);
        // The refused attempt leaves neither a proof nor a journaled intent.
        expect(await intentJournaled(), isFalse);
        expect(
          () => h.service.deletionAuthorizationValidator(user.wallet),
          _fails(WalletAccessFailure.staleOperation),
        );
      });
    }

    test('a refused deletion can be retried and then completes', () async {
      await expectLater(
        delete('Wrong-password-000000!'),
        _authFails(AuthExceptionType.incorrectPassword),
      );
      expect(await intentJournaled(), isFalse);
      expect(h.backend.values[_credentialKey], _password);
      expect((await delete(_password)).status, WalletDeletionStatus.deleted);
      expect(h.backend.values, isEmpty);
      expect(await h.service.hasPendingCredentialCleanup, isFalse);
    });

    test('an intent left by a closed dialog is withdrawn at startup', () async {
      await h.service.credentialForDeletion(user.wallet, password: _password);
      expect(await intentJournaled(), isTrue);
      await h.restart();
      expect(await intentJournaled(), isFalse);
      expect(h.backend.values[_credentialKey], _password);
    });

    test(
      'a broken cleanup journal cannot stop the app from starting',
      () async {
        await h.storage.write(
          WalletCredentialCleanup.journalKey,
          'not a journal',
        );
        await h.restart();
        await h.storage.write(WalletCredentialCleanup.journalKey, {
          _entry: {'record': h.record.toJson(), 'engineDeleted': false},
        });
        h.auth.users.clear();
        h.backend.failDelete = true;
        h.backend.metadataFailure = WalletAccessFailure.storageFailed;
        await h.restart();
        expect(h.coordinator.state.hasWallet, isFalse);
      },
    );
  });

  group('instant creation', () {
    late _Harness h;
    setUp(() {
      h = _Harness();
      h.backend.deviceAuthentication = true;
    });
    tearDown(() => h.dispose());

    Future<KdfUser> create() => h.service.createWallet(initialMetadata: {});

    for (final failure in [
      WalletAccessFailure.unavailable,
      WalletAccessFailure.lockedOut,
      WalletAccessFailure.storageFailed,
    ]) {
      for (final removable in [true, false]) {
        test(
          '${failure.name} at confirmation leaves no orphan, clean=$removable',
          () async {
            h.backend.readbackFailure = failure;
            h.backend.promptedDelete = removable;
            await expectLater(create(), _fails(failure));
            // The protected write had landed before its readback failed.
            expect(h.backend.writes, 1);
            expect(h.backend.deletes, 1);
            expect(h.backend.values.isEmpty, removable);
            expect(h.storage.values[_recordsKey], isNull);
            expect(h.storage.values[_pendingKey], isNull);
            expect(h.auth.registrations, isEmpty);
            h.backend.readbackFailure = null;
            final created = await create();
            expect(h.auth.users, [created]);
            expect(h.coordinator.operationGate.allowsOperations, isTrue);
          },
        );
      }
    }

    test('an explicit cancel still creates the wallet unprotected', () async {
      h.backend.readbackFailure = WalletAccessFailure.canceled;
      h.backend.promptedDelete = true;
      final created = await create();
      final status = await h.service.status();
      expect(status.requiresAuthentication, isFalse);
      expect(h.auth.users, [created]);
    });

    test(
      'a half-created wallet opened later is no longer resumed into',
      () async {
        h.storage.failWrite = _lastKey;
        await expectLater(create(), _fails(WalletAccessFailure.storageFailed));
        final first = h.auth.users.single;
        expect(
          h.storage.values[_pendingKey],
          WalletAccessService.entryId(first),
        );
        h.storage.failWrite = null;
        await h.restart();
        await h.service.signInManaged(first.wallet);
        expect(h.storage.values[_pendingKey], isNull);
        await h.restart();
        final second = await create();
        expect(
          WalletAccessService.entryId(second),
          isNot(WalletAccessService.entryId(first)),
        );
        expect(h.auth.users, hasLength(2));
      },
    );

    for (final lost in ['missing', 'invalidated', 'record']) {
      test('a pending creation whose $lost is lost can be abandoned', () async {
        h.auth.failCreationOnce = true;
        await expectLater(create(), throwsStateError);
        final abandoned = h.storage.values[_pendingKey] as String;
        switch (lost) {
          case 'missing':
            h.backend.infos.clear();
            h.backend.values.clear();
          case 'invalidated':
            h.backend.metadataFailure = WalletAccessFailure.invalidated;
            h.backend.metadataFailureFor = WalletAccessRecord.credentialKeyFor(
              abandoned,
            );
          case 'record':
            await h.storage.write(_recordsKey, {
              abandoned: {...h.storedRecords[abandoned] as Map, 'version': 99},
            });
        }
        await h.restart();
        final created = await create();
        expect(WalletAccessService.entryId(created), isNot(abandoned));
        expect(h.auth.users, [created]);
        expect(h.storage.values[_pendingKey], isNull);
        // What was stored for the abandoned creation is left as it was.
        expect(h.storedRecords.keys, contains(abandoned));
      });
    }

    test(
      'a pending creation that only failed for now is still resumed',
      () async {
        h.auth.failCreationOnce = true;
        await expectLater(create(), throwsStateError);
        final pending = h.storage.values[_pendingKey] as String;
        await h.restart();
        h.backend.failNextRead = true;
        await expectLater(create(), _fails(WalletAccessFailure.storageFailed));
        expect(h.storage.values[_pendingKey], pending);
        expect(WalletAccessService.entryId(await create()), pending);
      },
    );
  });
}
