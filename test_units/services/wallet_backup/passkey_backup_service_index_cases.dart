part of 'passkey_backup_service_test.dart';

const _idA = 'AAAAAAAAAAAAAAAAAAAAAA';
const _idB = 'BBBBBBBBBBBBBBBBBBBBBB';

void _indexCases() {
  late _JsonStorage storage;
  late PasskeyBackupIndex index;
  setUp(() {
    storage = _JsonStorage();
    index = PasskeyBackupIndex(storage: storage);
  });

  PasskeyBackupEntry entryFor(String id, {String wallet = 'wallet-1'}) =>
      PasskeyBackupEntry(
        id: id,
        walletKey: wallet,
        store: BackupStoreKind.googleDrive,
        created: DateTime.utc(2026, 1, 2, 3, 4, 5),
        synced: true,
        providerName: 'Bitwarden',
      );

  Map<String, dynamic> stored() =>
      jsonDecode(storage.values[PasskeyBackupIndex.storageKey]!)
          as Map<String, dynamic>;

  test('keeps versioned JSON that another instance reads back', () async {
    await index.save(entryFor(_idA), 'record-a');
    await index.save(entryFor(_idB, wallet: 'wallet-2'), 'record-b');
    expect(stored()[_idA], {
      'version': 1,
      'id': _idA,
      'walletKey': 'wallet-1',
      'store': 'googleDrive',
      'created': '2026-01-02T03:04:05.000Z',
      'synced': true,
      'providerName': 'Bitwarden',
      'checkedHere': null,
      'state': 'ready',
      'record': 'record-a',
    });

    final again = PasskeyBackupIndex(storage: storage);
    final [entry] = await again.entriesFor('wallet-1');
    expect(entry.id, _idA);
    expect(entry.store, BackupStoreKind.googleDrive);
    expect(entry.created, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(entry.synced, isTrue);
    expect(entry.providerName, 'Bitwarden');
    expect(entry.checkedHere, isNull);
    expect(await again.record(_idB), 'record-b');

    await again.markChecked(_idA, DateTime.utc(2026, 5, 1));
    expect((await index.entry(_idA))!.checkedHere, DateTime.utc(2026, 5, 1));
    await again.remove(_idA);
    expect(await index.entry(_idA), isNull);
    expect(await index.records(), ['record-b']);
  });

  test('leaves entries it cannot read exactly as stored', () async {
    final later = {'version': 2, 'id': _idB, 'shape': 'unknown'};
    storage.values[PasskeyBackupIndex.storageKey] = jsonEncode({
      _idB: later,
      'not-an-id': entryFor(_idA).id,
    });
    await index.save(entryFor(_idA), 'record-a');
    expect(stored()[_idB], later);
    expect(stored()['not-an-id'], _idA);
    expect((await index.entriesFor('wallet-1')).single.id, _idA);
    expect(await index.entry(_idB), isNull);
  });

  test('never overwrites an index it cannot read', () async {
    final unreadable = jsonEncode(['not', 'a', 'map']);
    storage.values[PasskeyBackupIndex.storageKey] = unreadable;
    expect(await index.entriesFor('wallet-1'), isEmpty);
    await expectLater(
      index.save(entryFor(_idA), 'record-a'),
      _backupFails(PasskeyBackupFailure.storageFailed),
    );
    expect(storage.values[PasskeyBackupIndex.storageKey], unreadable);
  });

  test('a write that is refused or not kept fails', () async {
    storage.refuseWrites = true;
    await expectLater(
      index.save(entryFor(_idA), 'record-a'),
      _backupFails(PasskeyBackupFailure.storageFailed),
    );
    storage
      ..refuseWrites = false
      ..dropWrites = true;
    await expectLater(
      index.save(entryFor(_idA), 'record-a'),
      _backupFails(PasskeyBackupFailure.storageFailed),
    );
  });

  test('changes nothing for an entry already removed', () async {
    await index.markChecked(_idA, DateTime.utc(2026));
    await index.remove(_idA);
    expect(storage.values, isEmpty);
  });
}
