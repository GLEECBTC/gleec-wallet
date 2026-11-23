part of 'wallet_access_service_test.dart';

/// The service over the real passkey tier, with a fake device vault and
/// passkey provider standing in for the operating system.
class _PasskeyReuse {
  _PasskeyReuse({bool enabled = true}) {
    service = WalletAccessService(
      sdk: sdk,
      storage: storage,
      backend: backend,
      unlockCoordinator: coordinator,
      monotonicNow: () => Duration.zero,
      existingPasskeyEnrollment: enabled,
    );
  }

  final storage = _Storage();
  final auth = _Auth();
  late final sdk = _Sdk(auth);
  final vault = FakeDeviceVault();
  final authenticator = FakePasskeyAuthenticator();
  late final backend = PasskeyCredentialBackend(
    base: vault,
    authenticator: authenticator,
  );
  final coordinator = WalletUnlockCoordinator(
    operationGate: WalletOperationGate(),
    monotonicNow: () => Duration.zero,
  );
  late final WalletAccessService service;

  String get key => WalletAccessRecord.credentialKeyFor(_entry);

  Future<KdfUser> install({bool protected = true}) async {
    final user = _user();
    auth.users.add(user);
    auth.activate(user);
    final record = WalletAccessRecord(
      entryId: _entry,
      walletName: 'Wallet',
      isHd: true,
      pubkeyHash: _hash,
      phase: 'ready',
      protection: protected
          ? CredentialProtection.authenticationBound
          : CredentialProtection.osAccountProtected,
      requiresAuthentication: protected,
    );
    await storage.write(_recordsKey, {_entry: record.toJson()});
    await vault.write(key, _password, requireAuthentication: protected);
    await service.didAuthenticate(user, password: _password);
    vault.prompts = 0;
    return user;
  }

  Future<void> bound(KdfUser user) async {
    await service.useExistingPasskey(walletId: user.walletId);
    vault.prompts = 0;
    authenticator.assertions = 0;
  }

  Future<void> dispose() async {
    await service.dispose();
    await backend.dispose();
    await auth.sessions.dispose();
  }
}

void _passkeyReuseCases() {
  group('native reuse of an existing passkey', () {
    late _PasskeyReuse h;
    setUp(() => h = _PasskeyReuse());
    tearDown(() => h.dispose());

    test(
      'switches device unlock to a passkey with one device prompt',
      () async {
        final user = await h.install();
        expect(
          (await h.service.capabilities()).existingPasskeyCandidate,
          isTrue,
        );
        await h.service.useExistingPasskey(walletId: user.walletId);

        expect(h.vault.prompts, 1, reason: 'authorization only');
        expect(h.authenticator.assertions, 2, reason: 'choose, then verify');
        final status = await h.service.status(walletId: user.walletId);
        expect(status.protection, CredentialProtection.passkey);
        expect(status.requiresAuthentication, isTrue);
        expect(h.vault.holds(h.key), isFalse);
        final record = WalletAccessRecord.fromJson(
          Map<String, dynamic>.from(
            (h.storage.values[_recordsKey] as Map)[_entry] as Map,
          ),
        );
        expect(record.protection, CredentialProtection.passkey);
        expect(record.managed, isTrue);
      },
    );

    test('stays off until its rollout flag is on', () async {
      await h.dispose();
      h = _PasskeyReuse(enabled: false);
      final user = await h.install();
      expect(
        (await h.service.capabilities()).existingPasskeyCandidate,
        isFalse,
      );
      await expectLater(
        h.service.useExistingPasskey(walletId: user.walletId),
        _fails(WalletAccessFailure.unavailable),
      );
      expect(h.authenticator.assertions, 0);
      expect(h.vault.holds(h.key), isTrue);
    });

    test('unlocks the locked app with the bound passkey', () async {
      final user = await h.install(protected: false);
      await h.bound(user);
      h.coordinator.lock();
      expect(await h.service.unlockCurrent(), isTrue);
      expect(h.authenticator.assertions, 1);
      expect(h.vault.prompts, 0);
    });

    test('a declined passkey leaves device unlock in force', () async {
      final user = await h.install();
      h.authenticator.failure = WalletAccessFailure.canceled;
      await expectLater(
        h.service.useExistingPasskey(walletId: user.walletId),
        _fails(WalletAccessFailure.canceled),
      );
      expect(
        (await h.service.status(walletId: user.walletId)).protection,
        CredentialProtection.authenticationBound,
      );
    });

    test('returns to device unlock through the passkey', () async {
      final user = await h.install();
      await h.bound(user);
      await h.service.enrollDevice(walletId: user.walletId);
      expect(h.authenticator.assertions, 1, reason: 'authorization only');
      expect(
        (await h.service.status(walletId: user.walletId)).protection,
        CredentialProtection.authenticationBound,
      );
      expect(h.vault.holds(PasskeyCredentialBackend.slotFor(h.key)), isFalse);
    });

    test('returns to device unlock with the password alone', () async {
      final user = await h.install();
      await h.bound(user);
      h.authenticator.passkeys.clear();
      await h.service.enrollDevice(
        walletId: user.walletId,
        password: _password,
      );
      expect(h.authenticator.assertions, 0);
      expect(
        (await h.service.status(walletId: user.walletId)).protection,
        CredentialProtection.authenticationBound,
      );
    });

    test(
      'chooses another passkey with the password when one is lost',
      () async {
        final user = await h.install(protected: false);
        await h.bound(user);
        h.authenticator.passkeys
          ..clear()
          ..add(FakePasskey(9));
        await h.service.replacePasskeyUsingPassword(
          walletId: user.walletId,
          password: _password,
        );
        expect(h.authenticator.assertions, 2);
        h.coordinator.lock();
        expect(await h.service.unlockCurrent(), isTrue);
      },
    );

    test('a lost passkey can be dropped for the password alone', () async {
      final user = await h.install(protected: false);
      await h.bound(user);
      h.authenticator.passkeys.clear();
      await h.service.stopUsingPasskey(
        walletId: user.walletId,
        password: _password,
      );
      expect(h.authenticator.assertions, 0);
      expect(h.vault.items, isEmpty, reason: 'no envelope is left behind');
      final status = await h.service.status(walletId: user.walletId);
      expect(status.protection, CredentialProtection.password);
      expect(status.hasManagedCredential, isFalse);
      expect(status.requiresAuthentication, isTrue);
      await expectLater(
        h.service.stopUsingPasskey(
          walletId: user.walletId,
          password: _password,
        ),
        _fails(WalletAccessFailure.missingCredential),
      );
    });

    test('a password change reseals under the same passkey', () async {
      final user = await h.install(protected: false);
      await h.bound(user);
      final outcome = await h.service.changePasswordWithOutcome(
        walletId: user.walletId,
        newPassword: _replacement,
      );
      expect(outcome, PasswordChangeOutcome.completed);
      // The current password through the passkey, then the reseal; the
      // readback reuses the reseal's key.
      expect(h.authenticator.assertions, 2);
      expect(
        await h.backend.read(
          h.key,
          reason: 'check',
          requireAuthentication: true,
        ),
        _replacement,
      );
    });

    test('replaces an envelope a password change left behind', () async {
      final user = await h.install(protected: false);
      await h.bound(user);
      // What a password change the vault could not follow leaves: the
      // record no longer relies on the stored credential.
      final records = Map<String, dynamic>.from(
        h.storage.values[_recordsKey] as Map,
      );
      final record = WalletAccessRecord.fromJson(
        Map<String, dynamic>.from(records[_entry] as Map),
      );
      await h.storage.write(_recordsKey, {
        ...records,
        _entry: record
            .copyWith(managed: false, protection: CredentialProtection.password)
            .toJson(),
      });
      await h.service.useExistingPasskey(
        walletId: user.walletId,
        password: _password,
      );
      expect(
        (await h.service.status(walletId: user.walletId)).protection,
        CredentialProtection.passkey,
      );
    });
  });
}
