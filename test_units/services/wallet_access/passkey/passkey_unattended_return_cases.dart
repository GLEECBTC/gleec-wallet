part of 'passkey_credential_backend_test.dart';

/// Linux: a vault with no protected tier, so the way back from a passkey is
/// the vault's unattended record.
void _unattendedReturnCases(_Rig Function() rigOf) {
  group('return to unattended storage', () {
    test('is offered only by a vault without a protected tier', () async {
      final rig = rigOf();
      expect((await rig.backend.capabilities()).unattendedReturn, isFalse);
      rig.vault.protectedTier = false;
      expect((await rig.backend.capabilities()).unattendedReturn, isTrue);
    });

    test(
      'a device without a screen lock yet keeps its protected tier',
      () async {
        final rig = rigOf()..vault.deviceAuthentication = false;
        expect((await rig.backend.capabilities()).unattendedReturn, isFalse);
        await rig.bound();
        await expectLater(
          rig.backend.replacePasskeyWithUnattended(
            _key,
            passkeyPassword,
            expectedRevision: 2,
          ),
          _fails(WalletAccessFailure.unavailable),
        );
        expect(rig.vault.holds(_key), isFalse);
      },
    );

    test('writes the unattended record and retires the envelope', () async {
      final rig = rigOf()..vault.protectedTier = false;
      await rig.bound();
      await rig.backend.replacePasskeyWithUnattended(
        _key,
        passkeyPassword,
        expectedRevision: 2,
      );
      expect(rig.vault.prompts, 0);
      expect(rig.vault.holds(_slot), isFalse);
      final info = await rig.backend.metadata(_key);
      expect(info?.protection, CredentialProtection.osAccountProtected);
      expect(info?.enrolled, isFalse);
      expect(await rig.backend.read(_key, reason: 'readback'), passkeyPassword);
    });

    test('never stands in for a vault that can protect the record', () async {
      final rig = rigOf();
      await rig.bound();
      await expectLater(
        rig.backend.replacePasskeyWithUnattended(
          _key,
          passkeyPassword,
          expectedRevision: 2,
        ),
        _fails(WalletAccessFailure.unavailable),
      );
      expect(
        (await rig.backend.metadata(_key))?.protection,
        CredentialProtection.passkey,
      );
    });

    test('refuses a revision it was not authorized against', () async {
      final rig = rigOf()..vault.protectedTier = false;
      await rig.bound();
      await expectLater(
        rig.backend.replacePasskeyWithUnattended(
          _key,
          passkeyPassword,
          expectedRevision: 1,
        ),
        _fails(WalletAccessFailure.staleOperation),
      );
      expect(rig.vault.holds(_key), isFalse);
      expect(
        (await rig.backend.metadata(_key))?.protection,
        CredentialProtection.passkey,
      );
    });
  });
}
