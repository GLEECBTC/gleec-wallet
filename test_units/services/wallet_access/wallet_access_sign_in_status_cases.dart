part of 'wallet_access_service_test.dart';

WalletAccessRecord _restoredRecord({
  String entryId = _entry,
  String phase = 'ready',
  bool generated = true,
  PasswordManagerOutcome manager = PasswordManagerOutcome.unavailable,
  String? rotationEnvelope,
}) => WalletAccessRecord(
  entryId: entryId,
  walletName: 'Wallet',
  isHd: true,
  pubkeyHash: _hash,
  phase: phase,
  protection: CredentialProtection.authenticationBound,
  requiresAuthentication: true,
  generated: generated,
  manager: manager,
  rotationEnvelope: rotationEnvelope,
);

/// The catalog entry the SDK rebuilds from the engine's wallet names when
/// its own keychain item was not restored: a new ID and the name alone.
KdfUser _rebuiltUser({String id = 'rebuilt-entry'}) => KdfUser(
  walletId: WalletId.fromName('Wallet', _options),
  isBip39Seed: true,
  metadata: {'_wallet_entry_id': id, 'type': 'hdwallet'},
);

void _signInStatusCases() {
  group('Sign-in status of a wallet without its stored unlock', () {
    late _Harness h;
    setUp(() => h = _Harness());
    tearDown(() => h.dispose());

    Future<void> journal(List<WalletAccessRecord> records) => h.storage.write(
      _recordsKey,
      {for (final record in records) record.entryId: record.toJson()},
    );

    Future<WalletAccessStatus> restored(
      List<WalletAccessRecord> records, {
      KdfUser? user,
    }) async {
      final signingIn = user ?? _user();
      h.auth.users.add(signingIn);
      await journal(records);
      return h.service.statusForWallet(signingIn.wallet);
    }

    test('a restored record without its vault entry is lost', () async {
      final status = await restored([
        _restoredRecord(manager: PasswordManagerOutcome.accepted),
      ]);

      expect(status.entryId, _entry);
      expect(status.lostProtection, CredentialProtection.authenticationBound);
      expect(status.hasManagedCredential, isFalse);
      expect(status.requiresAuthentication, isTrue);
      expect(status.protection, CredentialProtection.password);
      expect(status.generatedPassword, isTrue);
      expect(status.passwordManager, PasswordManagerOutcome.accepted);
      expect(h.backend.metadataReads, 1);
      // An open wallet's status keeps reporting the missing credential.
      await expectLater(
        h.service.status(walletId: _user().walletId),
        _fails(WalletAccessFailure.missingCredential),
      );
    });

    test('a chosen password is not reported as generated', () async {
      final status = await restored([_restoredRecord(generated: false)]);

      expect(status.lostProtection, isNotNull);
      expect(status.generatedPassword, isFalse);
    });

    test('a journaled password change is one the owner knows', () async {
      final record = _restoredRecord(rotationEnvelope: 'sealed-former');
      expect(
        (await restored([record])).generatedPassword,
        isFalse,
        reason: 'lost',
      );

      await h.backend.write(
        record.credentialKey,
        _password,
        requireAuthentication: true,
      );
      final kept = await h.service.statusForWallet(_user().wallet);
      expect(kept.hasManagedCredential, isTrue);
      expect(kept.generatedPassword, isFalse, reason: 'kept');
    });

    test('a vault entry the system invalidated is lost', () async {
      h.backend.metadataFailure = WalletAccessFailure.invalidated;

      final status = await restored([_restoredRecord()]);

      expect(status.lostProtection, CredentialProtection.authenticationBound);
      expect(status.generatedPassword, isTrue);
    });

    test('a protected entry that lost its enrollment is lost', () async {
      final record = _restoredRecord();
      h.backend.infos[record.credentialKey] = const CredentialRecordInfo(
        protection: CredentialProtection.osAccountProtected,
        enrolled: false,
      );

      expect((await restored([record])).lostProtection, isNotNull);
    });

    test('other vault failures stay errors', () async {
      h.backend.metadataFailure = WalletAccessFailure.storageFailed;

      await expectLater(
        restored([_restoredRecord()]),
        _fails(WalletAccessFailure.storageFailed),
      );
    });

    test('a vault entry that is here keeps the stored unlock', () async {
      final record = _restoredRecord();
      await h.backend.write(
        record.credentialKey,
        _password,
        requireAuthentication: true,
      );

      final status = await restored([record]);

      expect(status.hasManagedCredential, isTrue);
      expect(status.lostProtection, isNull);
      expect(h.backend.metadataReads, 1);
    });

    test('a wallet that opens with its password alone loses nothing', () async {
      final status = await restored([
        _restoredRecord().copyWith(
          managed: false,
          protection: CredentialProtection.password,
        ),
      ]);

      expect(status.lostProtection, isNull);
      expect(status.hasManagedCredential, isFalse);
    });

    test('a record of another identity stays an error', () async {
      await expectLater(
        restored([
          _restoredRecord().copyWith(
            pubkeyHash: '2222222222222222222222222222222222222222',
          ),
        ]),
        _fails(WalletAccessFailure.invalidResponse),
      );
    });

    test('a hardware wallet never takes a record by its name', () async {
      final trezor = KdfUser(
        walletId: WalletId.fromName('Wallet', _options),
        isBip39Seed: true,
        metadata: const {'_wallet_entry_id': 'trezor-entry', 'type': 'trezor'},
      );

      final status = await restored([_restoredRecord()], user: trezor);

      expect(status.lostProtection, isNull);
      expect(status.requiresAuthentication, isFalse);
    });

    test('a password-verified wallet whose record this build cannot read '
        'keeps its password status', () async {
      final user = await h.install();
      await h.storage.write(_recordsKey, {
        _entry: {'version': 99, 'entryId': _entry, 'walletName': 'Wallet'},
      });

      final status = await h.service.statusForWallet(user.wallet);

      expect(status.protection, CredentialProtection.password);
      expect(status.requiresAuthentication, isTrue);
    });

    test('a rebuilt catalog entry finds the record of its former ID', () async {
      final status = await restored([
        _restoredRecord(manager: PasswordManagerOutcome.declined),
      ], user: _rebuiltUser());

      expect(status.entryId, 'rebuilt-entry');
      expect(status.lostProtection, CredentialProtection.authenticationBound);
      expect(status.generatedPassword, isTrue);
      expect(status.passwordManager, PasswordManagerOutcome.declined);
      expect(h.backend.metadataReads, 1);
    });

    for (final (state, lost) in [
      ('missing', true),
      ('invalidated', true),
      ('unenrolled', true),
      ('present', false),
    ]) {
      test('a former record whose vault entry is $state '
          '${lost ? 'is lost' : 'keeps the plain status'}', () async {
        final record = _restoredRecord();
        if (state == 'invalidated') {
          h.backend.metadataFailure = WalletAccessFailure.invalidated;
        } else if (state != 'missing') {
          h.backend.infos[record.credentialKey] = CredentialRecordInfo(
            protection: CredentialProtection.authenticationBound,
            enrolled: state == 'present',
          );
        }

        final status = await restored([record], user: _rebuiltUser());

        expect(status.lostProtection, lost ? isNotNull : isNull);
      });
    }

    test(
      'a former record that never held a stored unlock is not lost',
      () async {
        final status = await restored([
          _restoredRecord().copyWith(
            managed: false,
            protection: CredentialProtection.password,
          ),
        ], user: _rebuiltUser());

        expect(status.lostProtection, isNull);
      },
    );

    test('a name-only entry with a record of its own takes no other', () async {
      final status = await restored([
        const WalletAccessRecord(
          entryId: 'rebuilt-entry',
          walletName: 'Wallet',
          isHd: true,
          phase: 'ready',
          protection: CredentialProtection.password,
          requiresAuthentication: true,
          managed: false,
          generated: false,
        ),
        _restoredRecord(),
      ], user: _rebuiltUser());

      expect(status.lostProtection, isNull);
    });

    test('a verified entry never takes a removed wallet\'s record', () async {
      final status = await restored([
        _restoredRecord(),
      ], user: _user(id: 'recreated-entry'));

      expect(status.lostProtection, isNull);
      expect(status.generatedPassword, isFalse);
    });

    test('records another entry claims, or two of one name, are not '
        'guessed between', () async {
      h.auth.users.add(_user(name: 'Other', id: 'claimed-entry'));
      expect(
        (await restored([
          _restoredRecord(entryId: 'claimed-entry'),
        ], user: _rebuiltUser())).lostProtection,
        isNull,
      );

      await journal([
        _restoredRecord(),
        _restoredRecord(entryId: 'test-wallet-entry-0002'),
      ]);
      expect(
        (await h.service.statusForWallet(_rebuiltUser().wallet)).lostProtection,
        isNull,
      );
    });

    test('a wallet being removed or never finished is not taken', () async {
      await h.storage.write(WalletCredentialCleanup.journalKey, {
        _entry: {'record': _restoredRecord().toJson(), 'engineDeleted': true},
      });
      expect(
        (await restored([
          _restoredRecord(),
        ], user: _rebuiltUser())).lostProtection,
        isNull,
      );

      await h.storage.delete(WalletCredentialCleanup.journalKey);
      await journal([_restoredRecord(phase: 'provisioning')]);
      expect(
        (await h.service.statusForWallet(_rebuiltUser().wallet)).lostProtection,
        isNull,
      );
    });

    test('a lookup that fails leaves the plain password status', () async {
      await h.storage.write(WalletCredentialCleanup.journalKey, 'not json');

      final status = await restored([_restoredRecord()], user: _rebuiltUser());

      expect(status.lostProtection, isNull);
      expect(status.requiresAuthentication, isTrue);
    });

    test('after a password sign-in the status names the lost lock', () async {
      final user = await h.install();
      await h.backend.delete(
        WalletAccessRecord.credentialKeyFor(_entry),
        authorization: 'test',
      );

      final status = await h.service.status();

      expect(status.hasManagedCredential, isFalse);
      expect(status.lostProtection, CredentialProtection.authenticationBound);
      expect(
        (await h.service.statusForWallet(user.wallet)).lostProtection,
        CredentialProtection.authenticationBound,
      );
    });
  });
}
