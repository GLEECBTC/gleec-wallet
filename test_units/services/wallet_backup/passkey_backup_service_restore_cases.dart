part of 'passkey_backup_service_test.dart';

void _restoreCases() {
  late _Rig rig;
  late PasskeyBackupEntry entry;
  setUp(() async {
    rig = _Rig();
    entry = await rig.create();
    rig.authenticator.requests.clear();
  });

  Future<StoredBackup> found() async =>
      (await rig.service.find(BackupStoreKind.iCloudKeychain)).single;

  group('unlock', () {
    test('opens with one prompt for the passkey it names', () async {
      final backup = await found();
      expect(backup.id, entry.id);
      expect(backup.created, entry.created);
      final secret = await rig.service.unlock(backup);
      expect(secret.walletName, 'Savings');
      expect(secret.seed, _secret().seed);
      expect(secret.phraseConfirmed, isTrue);
      final request = rig.authenticator.requests.single;
      expect(request.allowCredentials.single, rig.provider.passkeys[0].id);
      expect(request.salt, _prfSalt);
      expect(rig.provider.handedOut.every(_wiped), isTrue);
    });

    final wrong = <String, void Function(_Rig rig)>{
      'the passkey is gone': (rig) => rig.provider.passkeys.clear(),
      'another passkey answers': (rig) =>
          rig.authenticator.answerWith = _Passkey(40, Uint8List(32)),
      'its user handle differs': (rig) =>
          rig.authenticator.userHandle = Uint8List.fromList(List.filled(32, 3)),
      'its key differs here': (rig) =>
          rig.authenticator.changeKeyOn = (_) => true,
    };
    for (final MapEntry(key: name, value: arrange) in wrong.entries) {
      test('is the wrong passkey when $name', () async {
        final backup = await found();
        arrange(rig);
        await expectLater(
          rig.service.unlock(backup),
          _backupFails(PasskeyBackupFailure.wrongPasskey),
        );
        expect(rig.provider.handedOut.every(_wiped), isTrue);
      });
    }

    test('keeps the access failures it cannot name better', () async {
      final backup = await found();
      rig.authenticator.failOn = (_) => WalletAccessFailure.canceled;
      await expectLater(
        rig.service.unlock(backup),
        _backupFails(PasskeyBackupFailure.canceled),
      );
      rig.authenticator.failOn = (_) => WalletAccessFailure.lockedOut;
      await expectLater(
        rig.service.unlock(backup),
        _accessFails(WalletAccessFailure.lockedOut),
      );
    });
  });

  test('check opens the stored copy and records it here', () async {
    rig.now = DateTime.utc(2026, 12, 1, 8);
    expect(await rig.service.check(entry), rig.now);
    final [checked] = await rig.service.backupsFor('wallet-1');
    expect(checked.checkedHere, rig.now);
    expect(rig.authenticator.requests, hasLength(1));

    rig.keychain.records.clear();
    await expectLater(
      rig.service.check(entry),
      _backupFails(PasskeyBackupFailure.noBackupFound),
    );
  });

  test('remove deletes the record and the entry, then the passkey', () async {
    final backup = await found();
    final credentialId = rig.provider.passkeys.single.id;
    await rig.service.remove(entry);
    expect(rig.keychain.records, isEmpty);
    expect(await rig.service.backupsFor('wallet-1'), isEmpty);
    expect(rig.registrar.removed.map(_b64), [_b64(credentialId)]);
    // A copy made earlier no longer opens once the provider drops it.
    await expectLater(
      rig.service.unlock(backup),
      _backupFails(PasskeyBackupFailure.wrongPasskey),
    );
  });

  test('remove keeps everything while the store is out of reach', () async {
    rig.keychain.available = false;
    await expectLater(
      rig.service.remove(entry),
      _backupFails(PasskeyBackupFailure.storeUnavailable),
    );
    expect(await rig.service.backupsFor('wallet-1'), hasLength(1));
    expect(rig.registrar.removed, isEmpty);
  });

  test('export gives the copy kept here without asking the store', () async {
    final lists = rig.keychain.lists;
    final exported = await rig.service.exportFile(entry);
    expect(exported, rig.keychain.records[entry.id]);
    expect(rig.keychain.lists, lists);

    // Without a readable copy here it falls back to the store's.
    final stored = jsonDecode(
      rig.storage.values[PasskeyBackupIndex.storageKey]!,
    ) as Map<String, dynamic>;
    (stored[entry.id] as Map<String, dynamic>)['record'] = 'damaged';
    rig.storage.values[PasskeyBackupIndex.storageKey] = jsonEncode(stored);
    expect(await rig.service.exportFile(entry), exported);
    rig.keychain.records.clear();
    await expectLater(
      rig.service.exportFile(entry),
      _backupFails(PasskeyBackupFailure.noBackupFound),
    );
  });

  test('find offers only records this build can open, newest first', () async {
    final newer = _foreignRecord(_rp, created: DateTime.utc(2027));
    final other = _foreignRecord('other.example.net', seed: 98);
    rig.keychain.records
      ..[_idOf(newer)] = newer
      ..['AAAAAAAAAAAAAAAAAAAAAA'] = 'not a record'
      ..[_idOf(other)] = other
      // Filed under another record's id.
      ..['BBBBBBBBBBBBBBBBBBBBBB'] = rig.keychain.records[entry.id]!;
    final backups = await rig.service.find(BackupStoreKind.iCloudKeychain);
    expect(backups.map((backup) => backup.id), [_idOf(newer), entry.id]);
    expect(
      backups.every((b) => b.store == BackupStoreKind.iCloudKeychain),
      isTrue,
    );

    rig.keychain.records
      ..clear()
      ..['CCCCCCCCCCCCCCCCCCCCCC'] = _withVersion(newer, 2);
    await expectLater(
      rig.service.find(BackupStoreKind.iCloudKeychain),
      _backupFails(PasskeyBackupFailure.newerVersion),
    );
    rig.keychain.records.clear();
    expect(await rig.service.find(BackupStoreKind.iCloudKeychain), isEmpty);
    await expectLater(
      rig.service.find(BackupStoreKind.file),
      _backupFails(PasskeyBackupFailure.storeUnavailable),
    );
  });

  test('parseFile refuses what is not a backup for this host', () {
    expect(
      () => rig.service.parseFile('{"kind":"something else"}'),
      _backupFails(PasskeyBackupFailure.damaged),
    );
    expect(
      () => rig.service.parseFile(_foreignRecord('other.example.net')),
      _backupFails(PasskeyBackupFailure.otherRelyingParty),
    );
    expect(
      () => rig.service.parseFile(_withVersion(_foreignRecord(_rp), 2)),
      _backupFails(PasskeyBackupFailure.newerVersion),
    );
  });

  test('cancel ends both prompts', () async {
    await rig.service.cancel();
    expect(rig.registrar.cancels, 1);
    expect(rig.authenticator.cancels, 1);
  });
}

void _availabilityCases() {
  test('lists usable stores in the order to offer them', () async {
    final rig = _Rig();
    var availability = await rig.service.availability();
    expect(availability.canCreate, isTrue);
    expect(availability.canRestore, isTrue);
    expect(availability.stores, [
      BackupStoreKind.iCloudKeychain,
      BackupStoreKind.googleDrive,
      BackupStoreKind.file,
    ]);
    rig.keychain.available = false;
    availability = await rig.service.availability();
    expect(availability.stores, [
      BackupStoreKind.googleDrive,
      BackupStoreKind.file,
    ]);
  });

  test('Google Drive is offered only when the build enables it', () async {
    final rig = _Rig(
      config: const WalletTransferConfig(
        passkeyBackupEnabled: true,
        backupRpId: _rp,
      ),
    );
    expect((await rig.service.availability()).stores, [
      BackupStoreKind.iCloudKeychain,
      BackupStoreKind.file,
    ]);
  });

  test('is off without a configured host, platform or bridge', () async {
    final rigs = [
      _Rig(config: const WalletTransferConfig(backupRpId: _rp)),
      _Rig(
        config: const WalletTransferConfig(
          passkeyBackupEnabled: true,
          backupRpId: 'dex.gleec.com',
        ),
      ),
      _Rig(platformSupported: false),
      _Rig()..registrar.supported = false,
      _Rig()..authenticator.supported = false,
    ];
    for (final rig in rigs) {
      final availability = await rig.service.availability();
      expect(availability.canCreate, isFalse);
      expect(availability.canRestore, isFalse);
      expect(availability.stores, isEmpty);
    }
  });
}

String _idOf(String raw) =>
    (jsonDecode(raw) as Map<String, dynamic>)['id'] as String;

String _withVersion(String raw, int version) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  json['v'] = version;
  return jsonEncode(json);
}
