part of 'wallet_access_service_test.dart';

/// Linux: the vault has no protected tier, so a working passkey's way back
/// is the vault's unattended storage, authorized by that passkey.
void _unattendedReturnCases() {
  group('return from a passkey to unattended storage', () {
    late _PasskeyReuse h;
    setUp(() => h = _PasskeyReuse());
    tearDown(() => h.dispose());

    Future<KdfUser> boundWithoutDeviceUnlock() async {
      h.vault.protectedTier = false;
      final user = await h.install(protected: false);
      await h.bound(user);
      return user;
    }

    test('one passkey assertion switches the wallet back', () async {
      final user = await boundWithoutDeviceUnlock();
      expect(
        (await h.service.status(walletId: user.walletId)).protection,
        CredentialProtection.passkey,
      );
      expect((await h.service.capabilities()).unattendedReturn, isTrue);

      await h.service.useDeviceStorageInstead(walletId: user.walletId);

      expect(h.authenticator.assertions, 1);
      final status = await h.service.status(walletId: user.walletId);
      expect(status.protection, CredentialProtection.osAccountProtected);
      expect(status.requiresAuthentication, isFalse);
      expect(h.vault.value(h.key), _password);
      expect(h.vault.holds(PasskeyCredentialBackend.slotFor(h.key)), isFalse);
      expect(h.coordinator.state.requiresAuthentication, isFalse);
    });

    test('is not offered where device unlock exists', () async {
      final user = await h.install(protected: false);
      await h.bound(user);
      expect((await h.service.capabilities()).unattendedReturn, isFalse);
      await expectLater(
        h.service.useDeviceStorageInstead(walletId: user.walletId),
        _fails(WalletAccessFailure.unavailable),
      );
      expect(h.authenticator.assertions, 0);
      expect(
        (await h.service.status(walletId: user.walletId)).protection,
        CredentialProtection.passkey,
      );
    });

    test('a declined passkey keeps the passkey in force', () async {
      final user = await boundWithoutDeviceUnlock();
      h.authenticator.failure = WalletAccessFailure.canceled;
      await expectLater(
        h.service.useDeviceStorageInstead(walletId: user.walletId),
        _fails(WalletAccessFailure.canceled),
      );
      expect(h.vault.holds(h.key), isFalse);
      expect(
        (await h.service.status(walletId: user.walletId)).protection,
        CredentialProtection.passkey,
      );
    });

    test('works whatever the rollout flag says', () async {
      final user = await boundWithoutDeviceUnlock();
      final flagOff = WalletAccessService(
        sdk: h.sdk,
        storage: h.storage,
        backend: h.backend,
        unlockCoordinator: h.coordinator,
        monotonicNow: () => Duration.zero,
      );
      addTearDown(flagOff.dispose);
      await flagOff.didAuthenticate(user, password: _password);
      expect((await flagOff.capabilities()).existingPasskeyCandidate, isFalse);

      await flagOff.useDeviceStorageInstead(walletId: user.walletId);
      expect(
        (await flagOff.status(walletId: user.walletId)).protection,
        CredentialProtection.osAccountProtected,
      );
    });
  });
}
