part of 'backup_stores_test.dart';

String _fileName(String id) => 'gleec-passkey-backup-$id.json';

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

class _FakeAuthorizer implements GoogleDriveAuthorizer {
  bool available = true;
  int grants = 0;
  PasskeyBackupFailure? failure;
  Completer<void>? gate;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String> authorize() async {
    await gate?.future;
    if (failure case final failure?) throw PasskeyBackupException(failure);
    return 'token-${++grants}';
  }
}

/// The parts of Drive REST v3 the store uses, over one app data folder.
class _FakeDrive {
  final files = <String, ({String name, Uint8List body})>{};
  final requests = <http.Request>[];

  /// A reply to send instead of the folder's own, or null for that.
  http.Response? Function(http.Request request)? override;
  int _next = 0;

  late final client = MockClient((request) async {
    requests.add(request);
    return override?.call(request) ?? _serve(request);
  });

  String add(String name, String body, {String? fileId}) {
    final id = fileId ?? 'file${_next++}';
    files[id] = (name: name, body: utf8.encode(body));
    return id;
  }

  http.Response _serve(http.Request request) {
    final url = request.url;
    final id = url.pathSegments.last;
    final file = files[id];
    return switch ((request.method, url.path)) {
      ('GET', '/drive/v3/files') => _list(url.queryParameters['q']!),
      ('GET', _) when url.queryParameters['alt'] == 'media' =>
        file == null
            ? http.Response('', 404)
            : http.Response.bytes(file.body, 200),
      ('DELETE', _) =>
        files.remove(id) == null
            ? http.Response('', 404)
            : http.Response('', 204),
      ('POST', '/upload/drive/v3/files') => _create(request),
      ('PATCH', _) when file != null => _update(id, file.name, request),
      _ => http.Response('', 400),
    };
  }

  http.Response _list(String query) {
    final prefix = RegExp("^name contains '(.+)'\$").firstMatch(query)![1]!;
    return _json({
      'files': [
        for (final MapEntry(:key, :value) in files.entries)
          if (value.name.contains(prefix)) {'id': key, 'name': value.name},
      ],
    });
  }

  http.Response _create(http.Request request) {
    final (metadata, media) = _multipart(request);
    final name = metadata['name'] as String;
    final id = add(name, utf8.decode(media));
    return _json({'kind': 'drive#file', 'id': id, 'name': name});
  }

  http.Response _update(String id, String name, http.Request request) {
    files[id] = (name: name, body: request.bodyBytes);
    return _json({'id': id, 'name': name});
  }
}

/// The metadata and media of a multipart/related upload, strictly framed.
(Map<String, dynamic>, Uint8List) _multipart(http.Request request) {
  final type = request.headers['content-type']!;
  final boundary = RegExp(r'^multipart/related; boundary=([A-Za-z0-9_-]+)$')
      .firstMatch(type)![1]!;
  final parts = utf8.decode(request.bodyBytes).split('--$boundary');
  expect(parts, hasLength(4));
  expect(parts.first, isEmpty);
  expect(parts.last, '--\r\n');
  (String, String) part(String raw) {
    final [headers, content] = raw.split('\r\n\r\n');
    expect(content, endsWith('\r\n'));
    return (headers.trim(), content.substring(0, content.length - 2));
  }

  final (metadataType, metadata) = part(parts[1]);
  final (mediaType, media) = part(parts[2]);
  expect(metadataType, 'Content-Type: application/json; charset=UTF-8');
  expect(mediaType, 'Content-Type: application/json');
  return (
    jsonDecode(metadata) as Map<String, dynamic>,
    Uint8List.fromList(utf8.encode(media)),
  );
}

void _driveCases() {
  late _FakeDrive drive;
  late _FakeAuthorizer authorizer;
  late DateTime now;
  late GoogleDriveBackupStore store;
  final record = jsonEncode({'created': '2026-01-01T00:00:00Z', 'v': 1});

  setUp(() {
    drive = _FakeDrive();
    authorizer = _FakeAuthorizer();
    now = DateTime.utc(2026, 11, 18);
    store = GoogleDriveBackupStore(
      authorizer: authorizer,
      client: drive.client,
      clock: () => now,
      random: Random(5),
    );
  });

  test('lists the app data folder and reads each backup', () async {
    final first = drive.add(_fileName(_id), record);
    final second = drive.add(_fileName(_id2), '{"v":1}');
    drive
      ..add('gleec-passkey-backup-notes.txt', 'not a backup')
      ..add(_fileName(_id3), record, fileId: 'bad/id');
    final backups = await store.list();
    expect(backups.map((backup) => backup.id), [_id, _id2]);
    expect(backups.first.raw, record);
    expect(backups.first.created, DateTime.utc(2026));
    expect(backups.first.store, BackupStoreKind.googleDrive);

    final [list, ...reads] = drive.requests;
    expect(list.method, 'GET');
    expect('${list.url.origin}${list.url.path}', _filesEndpoint);
    expect(list.url.queryParameters, {
      'spaces': 'appDataFolder',
      'fields': 'nextPageToken,files(id,name)',
      'pageSize': '100',
      'q': "name contains 'gleec-passkey-backup-'",
    });
    expect(reads.map((read) => '${read.url}'), [
      '$_filesEndpoint/$first?alt=media',
      '$_filesEndpoint/$second?alt=media',
    ]);
    for (final request in drive.requests) {
      expect(request.headers['authorization'], 'Bearer token-1');
    }
  });

  test('follows every page, so no record is missed', () async {
    final first = drive.add(_fileName(_id), record);
    final second = drive.add(_fileName(_id2), record);
    drive.override = (request) {
      if (request.method != 'GET' || request.url.path != '/drive/v3/files') {
        return null;
      }
      final token = request.url.queryParameters['pageToken'];
      return _json(
        token == null
            ? {
                'nextPageToken': 'page-2',
                'files': [
                  {'id': first, 'name': _fileName(_id)},
                ],
              }
            : {
                'files': [
                  {'id': second, 'name': _fileName(_id2)},
                ],
              },
      );
    };
    final backups = await store.list();
    expect(backups.map((backup) => backup.id), [_id, _id2]);
    final lists = drive.requests.where(
      (request) => request.url.path == '/drive/v3/files',
    );
    expect(lists.map((request) => request.url.queryParameters['pageToken']), [
      null,
      'page-2',
    ]);
  });

  test('refuses a folder whose pages never end', () async {
    drive.override = (request) =>
        request.method == 'GET' && request.url.path == '/drive/v3/files'
        ? _json({'nextPageToken': 'again', 'files': <Object>[]})
        : null;
    await expectLater(
      store.list(),
      throwsA(
        isA<PasskeyBackupException>().having(
          (e) => e.failure,
          'failure',
          PasskeyBackupFailure.storageFailed,
        ),
      ),
    );
    expect(
      drive.requests.where((request) => request.url.path == '/drive/v3/files'),
      hasLength(10),
    );
  });

  test('creates the file in the app data folder', () async {
    await store.write(_id, record);
    final [list, upload] = drive.requests;
    expect(list.method, 'GET');
    expect(upload.method, 'POST');
    expect(
      '${upload.url}',
      'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
    );
    final (metadata, media) = _multipart(upload);
    expect(metadata, {
      'name': _fileName(_id),
      'parents': ['appDataFolder'],
    });
    expect(utf8.decode(media), record);
    expect(drive.files.values.single.name, _fileName(_id));
    expect(authorizer.grants, 1);
  });

  test('replaces the content of the file that holds the id', () async {
    final fileId = drive.add(_fileName(_id), 'earlier');
    await store.write(_id, record);
    final update = drive.requests.last;
    expect(update.method, 'PATCH');
    expect(
      '${update.url}',
      'https://www.googleapis.com/upload/drive/v3/files/$fileId'
          '?uploadType=media',
    );
    expect(update.headers['content-type'], 'application/json');
    expect(utf8.decode(drive.files[fileId]!.body), record);
    expect(drive.files, hasLength(1));
  });

  test('deletes every file holding the id', () async {
    drive
      ..add(_fileName(_id), record)
      ..add(_fileName(_id), record);
    final kept = drive.add(_fileName(_id2), record);
    await store.delete(_id);
    expect(drive.files.keys, [kept]);
    expect(
      drive.requests.where((request) => request.method == 'DELETE'),
      hasLength(2),
    );

    // One that is already gone is not a failure.
    drive.add(_fileName(_id), record);
    drive.override = (request) =>
        request.method == 'DELETE' ? http.Response('', 404) : null;
    await store.delete(_id);
  });

  test('checks every id and name the server returns', () async {
    final replies = <http.Response? Function(http.Request)>[
      (r) => r.method == 'POST'
          ? _json({'id': '../escape', 'name': _fileName(_id)})
          : null,
      (r) => r.method == 'POST' ? _json({'id': 'file9', 'name': 'x'}) : null,
      (r) => r.method == 'PATCH' ? _json({'id': 'another'}) : null,
    ];
    drive.add(_fileName(_id2), record);
    for (final (index, reply) in replies.indexed) {
      drive.override = reply;
      await expectLater(
        store.write(index == 2 ? _id2 : _id, record),
        _fails(PasskeyBackupFailure.storageFailed),
      );
    }
    for (final reply in [
      _json({'files': 'none'}),
      http.Response('<html>', 200),
    ]) {
      drive.override = (_) => reply;
      await expectLater(
        store.list(),
        _fails(PasskeyBackupFailure.storageFailed),
      );
    }
  });

  test('skips content no record can be', () async {
    drive.add(_fileName(_id), 'x' * (maxBackupRecordBytes + 1));
    drive.files['binary'] = (
      name: _fileName(_id2),
      body: Uint8List.fromList([0xff, 0xfe]),
    );
    drive.add(_fileName(_id3), '');
    expect(await store.list(), isEmpty);
  });

  test('maps HTTP and network failures without their details', () async {
    const failures = {
      401: PasskeyBackupFailure.storeUnavailable,
      403: PasskeyBackupFailure.storeUnavailable,
      408: PasskeyBackupFailure.storeUnavailable,
      429: PasskeyBackupFailure.storeUnavailable,
      500: PasskeyBackupFailure.storeUnavailable,
      503: PasskeyBackupFailure.storeUnavailable,
      400: PasskeyBackupFailure.storageFailed,
      404: PasskeyBackupFailure.storageFailed,
    };
    for (final MapEntry(key: status, value: failure) in failures.entries) {
      drive.override = (_) =>
          http.Response('{"error":"token-1 rejected"}', status);
      await expectLater(store.list(), _fails(failure));
    }
    drive.override = (_) => throw http.ClientException(
      'connection reset',
      Uri.parse('https://www.googleapis.com/?access_token=token-9'),
    );
    await expectLater(
      store.list(),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
  });

  test('asks again after the server refuses the token', () async {
    drive.override = (_) => http.Response('', 401);
    await expectLater(
      store.list(),
      _fails(PasskeyBackupFailure.storeUnavailable),
    );
    drive.override = null;
    await store.list();
    expect(authorizer.grants, 2);
    expect(drive.requests.last.headers['authorization'], 'Bearer token-2');
  });

  test('keeps a token in memory for five minutes at most', () async {
    await store.list();
    now = now.add(const Duration(minutes: 4));
    await store.write(_id, record);
    expect(authorizer.grants, 1);
    now = now.add(const Duration(minutes: 1, seconds: 1));
    await store.list();
    expect(authorizer.grants, 2);
    store.forgetToken();
    await store.delete(_id);
    expect(authorizer.grants, 3);
  });

  test('concurrent actions share one sign-in', () async {
    final gate = Completer<void>();
    authorizer.gate = gate;
    final both = Future.wait([store.list(), store.list()]);
    gate.complete();
    await both;
    expect(authorizer.grants, 1);
  });

  test('sends nothing without a sign-in or a valid id', () async {
    authorizer.failure = PasskeyBackupFailure.canceled;
    await expectLater(store.list(), _fails(PasskeyBackupFailure.canceled));
    await expectLater(
      store.write('not an id', record),
      _fails(PasskeyBackupFailure.storageFailed),
    );
    await expectLater(
      store.delete('../$_id'),
      _fails(PasskeyBackupFailure.storageFailed),
    );
    expect(drive.requests, isEmpty);
    expect(await store.isAvailable(), isTrue);
    authorizer.available = false;
    expect(await store.isAvailable(), isFalse);
  });
}

const _filesEndpoint = 'https://www.googleapis.com/drive/v3/files';
