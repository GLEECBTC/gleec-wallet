part of 'backup_stores_test.dart';

void _keychainCases() {
  const channel = MethodChannel('test/backup_store');
  late _Bridge bridge;
  late bool apple;
  late ICloudKeychainBackupStore store;

  setUp(() {
    bridge = _Bridge(channel);
    apple = true;
    store = ICloudKeychainBackupStore(
      channel: channel,
      isApplePlatform: () => apple,
    );
  });
  tearDown(() => bridge.detach());

  test('is offered only on Apple platforms whose bridge says so', () async {
    bridge.reply = (_) => true;
    expect(await store.isAvailable(), isTrue);
    expect(bridge.calls.single.method, 'isAvailable');
    bridge.reply = (_) => throw PlatformException(code: 'unavailable');
    expect(await store.isAvailable(), isFalse);

    apple = false;
    bridge.calls.clear();
    expect(await store.isAvailable(), isFalse);
    await expectLater(
      store.list(),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
    expect(bridge.calls, isEmpty);
  });

  test('lists readable items and skips the rest', () async {
    final raw = jsonEncode({'created': '2026-03-04T05:06:07Z', 'v': 1});
    bridge.reply = (_) => [
      {'id': _id, 'data': utf8.encode(raw)},
      {'id': _id, 'data': utf8.encode('a second item under one id')},
      {'id': 'not-an-id', 'data': utf8.encode(raw)},
      {'id': _id2, 'data': Uint8List(maxBackupRecordBytes + 1)},
      {
        'id': _id3,
        'data': Uint8List.fromList([0xff, 0xfe]),
      },
      {'id': _id3, 'data': 'text, not bytes'},
      'not an item',
    ];
    final [backup] = await store.list();
    expect(bridge.calls.single.method, 'list');
    expect(backup.id, _id);
    expect(backup.store, BackupStoreKind.iCloudKeychain);
    expect(backup.raw, raw);
    expect(backup.created, DateTime.utc(2026, 3, 4, 5, 6, 7));

    bridge.reply = (_) => {'not': 'a list'};
    await expectLater(store.list(), _fails(PasskeyBackupFailure.storageFailed));
  });

  test('writes the record as bytes and deletes by id', () async {
    await store.write(_id, '{"record":1}');
    final write = bridge.calls.single;
    expect(write.method, 'write');
    expect(write.arguments, {'id': _id, 'data': utf8.encode('{"record":1}')});
    await store.delete(_id);
    expect(bridge.calls.last.method, 'delete');
    expect(bridge.calls.last.arguments, {'id': _id});
  });

  test('refuses a bad id or size before reaching the bridge', () async {
    for (final write in [
      () => store.write('../../escape', 'x'),
      () => store.write(_id, ''),
      () => store.write(_id, 'x' * (maxBackupRecordBytes + 1)),
      () => store.delete('short'),
    ]) {
      await expectLater(write(), _fails(PasskeyBackupFailure.storageFailed));
    }
    expect(bridge.calls, isEmpty);
  });

  test('maps bridge errors to store failures', () async {
    bridge.reply = (_) => throw PlatformException(code: 'unavailable');
    await expectLater(
      store.list(),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
    bridge.reply = (_) => throw PlatformException(code: 'storageFailed');
    await expectLater(
      store.write(_id, 'x'),
      _fails(PasskeyBackupFailure.storageFailed),
    );
    bridge.detach();
    await expectLater(
      store.delete(_id),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
  });
}
