part of 'passkey_credential_backend_test.dart';

void _removalCases(_Rig Function() current) {
  group('removal and unreadable records', () {
    test('a delete-purpose unlock authorizes exactly one removal', () async {
      final rig = current();
      await rig.bound();
      expect(await rig.unlock(purpose: 'delete'), passkeyPassword);
      final token = await rig.backend.prepareDelete(_key, reason: 'Remove');
      expect(rig.authenticator.assertions, 1);
      await rig.backend.delete(_key, authorization: token);
      expect(await rig.backend.metadata(_key), isNull);
      expect(rig.vault.items, isEmpty);
      await rig.backend.delete(_key, authorization: token);
    });

    test('removal without a permit, or with a stale one, is refused', () async {
      final rig = current();
      await rig.bound();
      await expectLater(
        rig.backend.delete(_key),
        _fails(WalletAccessFailure.staleOperation),
      );
      final token = await rig.backend.prepareDelete(_key, reason: 'Remove');
      expect(rig.authenticator.assertions, 1);
      rig.now += const Duration(seconds: 61);
      await expectLater(
        rig.backend.delete(_key, authorization: token),
        _fails(WalletAccessFailure.staleOperation),
      );
      final again = await rig.backend.prepareDelete(_key, reason: 'Remove');
      rig.vault.deviceEvents.add(null);
      await expectLater(
        rig.backend.delete(_key, authorization: again),
        _fails(WalletAccessFailure.staleOperation),
      );
      expect(await rig.unlock(), passkeyPassword);
    });

    test('a permit dies with the revision it was issued for', () async {
      final rig = current();
      await rig.bound();
      final token = await rig.backend.prepareDeleteAfterPasswordVerification(
        _key,
        expectedRevision: 2,
      );
      expect(rig.authenticator.assertions, 0);
      await rig.backend.write(_key, 'Changed', requireAuthentication: true);
      await expectLater(
        rig.backend.delete(_key, authorization: token),
        _fails(WalletAccessFailure.staleOperation),
      );
      await expectLater(
        rig.backend.prepareDeleteAfterPasswordVerification(
          _key,
          expectedRevision: 2,
        ),
        _fails(WalletAccessFailure.staleOperation),
      );
    });

    test(
      'a lost provider does not prevent removal after password proof',
      () async {
        final rig = current();
        await rig.bound();
        rig.authenticator.passkeys.clear();
        final token = await rig.backend.prepareDeleteAfterPasswordVerification(
          _key,
          expectedRevision: 2,
        );
        await rig.backend.delete(_key, authorization: token);
        expect(rig.vault.items, isEmpty);
      },
    );

    test('removing a device record also removes an inert envelope', () async {
      final rig = current();
      await rig.bound();
      await rig.vault.write(_key, passkeyPassword, requireAuthentication: true);
      final token = await rig.backend.prepareDelete(_key, reason: 'Remove');
      expect(token, startsWith('device-'));
      await rig.backend.delete(_key, authorization: token);
      expect(rig.vault.items, isEmpty);
    });

    test(
      'an unreadable envelope reports invalidated and is never opened',
      () async {
        final rig = current();
        await rig.vault.write(
          _slot,
          jsonEncode({'kind': PasskeyEnvelope.kind, 'v': 2}),
          requireAuthentication: false,
        );
        await expectLater(
          rig.backend.metadata(_key),
          _fails(WalletAccessFailure.invalidated),
        );
        await expectLater(
          rig.unlock(),
          _fails(WalletAccessFailure.invalidated),
        );
        await expectLater(
          rig.backend.write(_key, 'x', requireAuthentication: true),
          _fails(WalletAccessFailure.invalidated),
        );
        expect(rig.authenticator.assertions, 0);
      },
    );

    test('repair replaces an unreadable envelope with device unlock', () async {
      final rig = current();
      await rig.vault.write(_slot, '{}', requireAuthentication: false);
      await rig.backend.repairInvalidated(_key, passkeyPassword);
      expect(rig.vault.holds(_slot), isFalse);
      expect(
        (await rig.backend.metadata(_key))?.protection,
        CredentialProtection.authenticationBound,
      );
      // The device record now governs, and it was never invalidated.
      await expectLater(
        rig.backend.repairInvalidated(_key, passkeyPassword),
        _fails(WalletAccessFailure.unavailable),
      );
    });

    test('an unreadable envelope is removable without a ceremony', () async {
      final rig = current();
      await rig.vault.write(_slot, '{}', requireAuthentication: false);
      final token = await rig.backend.prepareDelete(_key, reason: 'Remove');
      expect(rig.authenticator.assertions, 0);
      await rig.backend.delete(_key, authorization: token);
      expect(rig.vault.items, isEmpty);
    });

    test('binding replaces an unreadable envelope', () async {
      final rig = current();
      await rig.vault.write(_slot, '{}', requireAuthentication: false);
      await rig.backend.bindExistingPasskey(_key, passkeyPassword);
      expect(await rig.unlock(), passkeyPassword);
    });
  });
}
