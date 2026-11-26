part of 'passkey_backup_service_test.dart';

final _prfSalt = Uint8List.fromList(
  sha256.convert(utf8.encode('gleec.wallet.passkey-backup.v1/prf')).bytes,
);

/// Nothing of a failed creation is left: no record, no entry, and the new
/// passkey reported removed.
void _expectUndone(_Rig rig) {
  expect(rig.keychain.records, isEmpty);
  expect(rig.storage.values[PasskeyBackupIndex.storageKey] ?? '{}', '{}');
  expect(rig.registrar.removed.map(_b64), [_b64(rig.provider.made.last.id)]);
  expect(rig.provider.handedOut.every(_wiped), isTrue);
}

void _createCases() {
  late _Rig rig;
  setUp(() => rig = _Rig());

  test('seals with the key given at creation after one sign-in', () async {
    final entry = await rig.create();

    final registration = rig.registrar.requests.single;
    expect(registration.rpId, _rp);
    expect(registration.userName, 'Gleec Wallet recovery');
    expect(registration.displayName, 'Gleec Wallet recovery – Savings');
    expect(registration.userId, hasLength(32));
    expect(registration.challenge, hasLength(32));
    expect(registration.prfSalt, _prfSalt);
    final assertion = rig.authenticator.requests.single;
    expect(assertion.rpId, _rp);
    expect(assertion.salt, _prfSalt);
    expect(assertion.allowCredentials.single, rig.provider.passkeys[0].id);

    expect(entry.walletKey, 'wallet-1');
    expect(entry.store, BackupStoreKind.iCloudKeychain);
    expect(entry.created, DateTime.utc(2026, 11, 18, 12, 30, 15));
    expect(entry.synced, isTrue);
    expect(entry.providerName, 'Google Password Manager');
    expect(entry.checkedHere, entry.created);
    expect((await rig.service.backupsFor('wallet-1')).single.id, entry.id);
    expect(await rig.service.backupsFor('wallet-2'), isEmpty);

    // Independently of the service: the stored copy opens with the passkey.
    final raw = rig.keychain.records[entry.id]!;
    expect(raw, isNot(contains('Correct')));
    final record = PasskeyBackupRecord.decode(raw, expectedRpId: _rp);
    final opened = record.open(rig.provider.passkeys[0].prf(_prfSalt));
    expect(opened.seed, _secret().seed);
    expect(opened.type, TransferWalletType.legacy);
    expect(record.userHandle, registration.userId);
    expect(rig.registrar.removed, isEmpty);
    expect(rig.provider.handedOut, hasLength(2));
    expect(rig.provider.handedOut.every(_wiped), isTrue);
  });

  test('without a key at creation two sign-ins must agree', () async {
    rig.registrar.prfAtCreation = false;
    final entry = await rig.create();
    final [first, second] = rig.authenticator.requests;
    expect(second.challenge, isNot(first.challenge));
    expect(second.allowCredentials.single, first.allowCredentials.single);
    expect(rig.keychain.records.keys, [entry.id]);
    expect(rig.provider.handedOut.every(_wiped), isTrue);
  });

  test('a key that differs from creation is not reproducible', () async {
    rig.registrar.creationPrf = Uint8List.fromList(List.filled(32, 9));
    await expectLater(
      rig.create(),
      _backupFails(PasskeyBackupFailure.notReproducible),
    );
    _expectUndone(rig);
  });

  test('two sign-ins that disagree are not reproducible', () async {
    rig.registrar.prfAtCreation = false;
    rig.authenticator.changeKeyOn = (call) => call == 1;
    await expectLater(
      rig.create(),
      _backupFails(PasskeyBackupFailure.notReproducible),
    );
    _expectUndone(rig);
  });

  test('a passkey kept on this device alone is refused', () async {
    rig.registrar
      ..flags = _deviceBound
      ..transports = const ['internal'];
    await expectLater(
      rig.create(),
      _backupFails(PasskeyBackupFailure.localOnly),
    );
    expect(rig.authenticator.requests, isEmpty);
    _expectUndone(rig);
  });

  test('a passkey made on another device over QR is refused', () async {
    for (final (flags, transports) in [
      (_synced, ['hybrid']),
      // Checked first: a phone's passkey seen here is not this device's.
      (_deviceBound, ['hybrid']),
    ]) {
      rig = _Rig();
      rig.registrar
        ..flags = flags
        ..transports = transports;
      await expectLater(
        rig.create(),
        _backupFails(PasskeyBackupFailure.createdElsewhere),
      );
      expect(rig.authenticator.requests, isEmpty);
      _expectUndone(rig);
    }
  });

  test('a security key reaches other devices without syncing', () async {
    rig.registrar
      ..flags = _deviceBound
      ..transports = const ['usb'];
    final entry = await rig.create();
    expect(entry.synced, isFalse);
  });

  test(
    'a provider that reports no transports is judged by its flags',
    () async {
      rig.registrar
        ..flags = _synced
        ..transports = const [];
      final entry = await rig.create();
      expect(entry.synced, isTrue);
      rig = _Rig();
      rig.registrar
        ..flags = _deviceBound
        ..transports = const [];
      await expectLater(
        rig.create(),
        _backupFails(PasskeyBackupFailure.localOnly),
      );
      _expectUndone(rig);
    },
  );

  group('a failure after the passkey exists undoes everything', () {
    final steps = <String, (void Function(_Rig rig), Matcher)>{
      'registration check': (
        (rig) => rig.registrar.wrongChallenge = true,
        _accessFails(WalletAccessFailure.invalidResponse),
      ),
      'sign-in canceled': (
        (rig) => rig.authenticator.failOn = (_) => WalletAccessFailure.canceled,
        _backupFails(PasskeyBackupFailure.canceled),
      ),
      'no PRF at sign-in': (
        (rig) =>
            rig.authenticator.failOn = (_) =>
                WalletAccessFailure.prfUnavailable,
        _backupFails(PasskeyBackupFailure.prfUnavailable),
      ),
      'second sign-in fails': (
        (rig) {
          rig.registrar.prfAtCreation = false;
          rig.authenticator.failOn = (call) =>
              call == 1 ? WalletAccessFailure.busy : null;
        },
        _accessFails(WalletAccessFailure.busy),
      ),
      'cancel between prompts': (
        (rig) => rig.authenticator.beforeReply = rig.service.cancel,
        _backupFails(PasskeyBackupFailure.canceled),
      ),
      'store write': (
        (rig) => rig.keychain.writeFailure = PasskeyBackupFailure.storageFailed,
        _backupFails(PasskeyBackupFailure.storageFailed),
      ),
      'store write lands but reports failure': (
        (rig) => rig.keychain
          ..writeFailure = PasskeyBackupFailure.storeUnavailable
          ..writeLandsAnyway = true,
        _backupFails(PasskeyBackupFailure.storeUnavailable),
      ),
      'store list': (
        (rig) =>
            rig.keychain.listFailure = PasskeyBackupFailure.storeUnavailable,
        _backupFails(PasskeyBackupFailure.storeUnavailable),
      ),
      'store loses the record': (
        (rig) => rig.keychain.hideOnList = true,
        _backupFails(PasskeyBackupFailure.storageFailed),
      ),
      'index write': (
        (rig) => rig.storage.refuseWrites = true,
        _backupFails(PasskeyBackupFailure.storageFailed),
      ),
    };
    for (final MapEntry(key: step, value: (arrange, matcher))
        in steps.entries) {
      test(step, () async {
        arrange(rig);
        await expectLater(rig.create(), matcher);
        _expectUndone(rig);
      });
    }
  });

  group('a stored copy that does not read back is not kept', () {
    final tampering = <String, String Function(String raw)>{
      'truncated': (raw) => raw.substring(0, raw.length - 2),
      'a flipped seed byte': (raw) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final seed = json['seed'] as String;
        final flipped = seed[10] == 'A' ? 'B' : 'A';
        json['seed'] = seed.replaceRange(10, 11, flipped);
        return jsonEncode(json);
      },
      'another record': (_) => _foreignRecord(_rp),
    };
    for (final MapEntry(key: name, value: tamper) in tampering.entries) {
      test(name, () async {
        rig.keychain.tamper = tamper;
        await expectLater(
          rig.create(),
          _backupFails(PasskeyBackupFailure.storageFailed),
        );
        _expectUndone(rig);
        expect(rig.keychain.deleted, hasLength(1));
      });
    }
  });

  test('a file backup keeps its proven copy here to be saved', () async {
    final entry = await rig.create(store: BackupStoreKind.file);
    expect(rig.keychain.records, isEmpty);
    final exported = await rig.service.exportFile(entry);
    final parsed = rig.service.parseFile('\n$exported\n');
    expect(parsed.id, entry.id);
    expect(parsed.store, BackupStoreKind.file);
    expect(parsed.created, entry.created);
    expect(await rig.service.unlock(parsed), isA<WalletTransferSecret>());
  });

  test('an unavailable store fails before any prompt', () async {
    rig.keychain.available = false;
    await expectLater(
      rig.create(),
      _backupFails(PasskeyBackupFailure.storeUnavailable),
    );
    rig = _Rig(config: const WalletTransferConfig(passkeyBackupEnabled: true));
    await expectLater(
      rig.create(),
      _backupFails(PasskeyBackupFailure.notConfigured),
    );
    rig = _Rig(
      config: const WalletTransferConfig(
        passkeyBackupEnabled: true,
        backupRpId: _rp,
      ),
    );
    await expectLater(
      rig.create(store: BackupStoreKind.googleDrive),
      _backupFails(PasskeyBackupFailure.storeUnavailable),
    );
    expect(rig.registrar.requests, isEmpty);
  });

  test('a registration the platform refuses leaves nothing behind', () async {
    rig.registrar.failure = WalletAccessFailure.unavailable;
    await expectLater(
      rig.create(),
      _backupFails(PasskeyBackupFailure.unavailable),
    );
    expect(rig.registrar.removed, isEmpty);
    expect(rig.keychain.records, isEmpty);
  });

  test('never reports removed a passkey another backup uses', () async {
    final first = await rig.create();
    rig.registrar
      ..reuse = rig.provider.passkeys.single
      ..wrongChallenge = true;
    await expectLater(
      rig.create(),
      _accessFails(WalletAccessFailure.invalidResponse),
    );
    expect(rig.registrar.removed, isEmpty);
    expect(rig.keychain.records.keys, [first.id]);
  });

  test('one ceremony at a time', () async {
    final release = Completer<void>();
    rig.authenticator.beforeReply = () => release.future;
    final pending = rig.create();
    await expectLater(rig.create(), _accessFails(WalletAccessFailure.busy));
    release.complete();
    expect((await pending).id, isNotEmpty);
  });

  test('the name shown is cut to 64 characters', () {
    final name = PasskeyBackupService.displayNameFor('W' * 64);
    expect(name.runes, hasLength(64));
    expect(name, startsWith('Gleec Wallet recovery – WWW'));
    expect(PasskeyBackupService.displayNameFor('😀' * 64).runes, hasLength(64));
  });

  test('Google Drive signs in before any passkey prompt', () async {
    rig.drive.prepareFailure = const PasskeyBackupException(
      PasskeyBackupFailure.canceled,
    );
    await expectLater(
      rig.create(store: BackupStoreKind.googleDrive),
      _backupFails(PasskeyBackupFailure.canceled),
    );
    expect(rig.drive.prepares, 1);
    expect(rig.registrar.requests, isEmpty);
    expect(rig.authenticator.requests, isEmpty);
    expect(rig.drive.deleted, isEmpty);
  });

  test('a backup is recorded as unfinished while it is written', () async {
    PasskeyBackupEntryState? during;
    rig.keychain.onWrite = () async {
      during = (await rig.index.entriesFor('wallet-1')).single.state;
    };
    final entry = await rig.create();
    expect(during, PasskeyBackupEntryState.unfinished);
    expect(entry.state, PasskeyBackupEntryState.ready);
    expect(
      (await rig.index.entriesFor('wallet-1')).single.state,
      PasskeyBackupEntryState.ready,
    );
  });

  test('a check finishes a backup an earlier run left unfinished', () async {
    final created = await rig.create();
    final raw = (await rig.index.record(created.id))!;
    final leftover = PasskeyBackupEntry(
      id: created.id,
      walletKey: created.walletKey,
      store: created.store,
      created: created.created,
      synced: created.synced,
      state: PasskeyBackupEntryState.unfinished,
    );
    await rig.index.save(leftover, raw);
    await rig.service.check(leftover);
    final finished = (await rig.index.entriesFor('wallet-1')).single;
    expect(finished.state, PasskeyBackupEntryState.ready);
    expect(finished.checkedHere, isNotNull);
  });

  test('a file backup is neither saved nor checked until saved', () async {
    final entry = await rig.create(store: BackupStoreKind.file);
    expect(entry.state, PasskeyBackupEntryState.fileNotSaved);
    expect(entry.checkedHere, isNull);
    await rig.service.markFileSaved(entry);
    final saved = (await rig.index.entriesFor('wallet-1')).single;
    expect(saved.state, PasskeyBackupEntryState.ready);
    expect(saved.checkedHere, isNull);
  });
}

/// A record sealed to a passkey no fake provider holds.
String _foreignRecord(String rpId, {DateTime? created, int seed = 99}) =>
    PasskeyBackupRecord.seal(
      rpId: rpId,
      passkey: RegisteredPasskey(
        credentialId: Uint8List.fromList(List.filled(16, 0xee)),
        backupEligible: true,
        backupState: true,
        transports: const ['internal'],
      ),
      userHandle: Uint8List.fromList(List.filled(32, 0xdd)),
      prf: Uint8List.fromList(List.filled(32, 0xcc)),
      secret: _secret(name: 'Other'),
      created: created ?? DateTime.utc(2026),
      random: Random(seed),
    ).encode();
