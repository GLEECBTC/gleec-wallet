part of 'google_drive_backup_store.dart';

const _filesUrl = 'https://www.googleapis.com/drive/v3/files';
const _uploadUrl = 'https://www.googleapis.com/upload/drive/v3/files';
const _maxReplyBytes = 256 * 1024;
const _maxPages = 10;

/// Drive ids go into request paths, so only their documented alphabet is
/// accepted.
final _driveFileId = RegExp(r'^[A-Za-z0-9_-]{1,256}$');
final _backupFileName = RegExp(
  r'^gleec-passkey-backup-([A-Za-z0-9_-]{22})\.json$',
);

/// A file this store wrote: its name carries the record id.
final class _DriveFile {
  const _DriveFile(this.id, this.backupId);

  final String id;
  final String backupId;

  static _DriveFile? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || !_driveFileId.hasMatch(id) || name is! String) {
      return null;
    }
    final match = _backupFileName.firstMatch(name);
    return match == null ? null : _DriveFile(id, match[1]!);
  }
}

final class _Reply {
  const _Reply(this.status, this.body);

  final int status;

  /// Null when the body was larger than the request allows.
  final Uint8List? body;
}

extension _DriveRequests on GoogleDriveBackupStore {
  /// Every page, so a delete or readback never misses a record. Bounded:
  /// past [_maxPages] the folder is not this app's to trust.
  Future<List<_DriveFile>> _files(String token) async {
    final found = <_DriveFile>[];
    String? page;
    for (var pages = 0; pages < _maxPages; pages++) {
      final uri = Uri.parse(_filesUrl).replace(
        queryParameters: {
          'spaces': 'appDataFolder',
          'fields': 'nextPageToken,files(id,name)',
          'pageSize': '100',
          'q': "name contains '${GoogleDriveBackupStore.filePrefix}'",
          if (page != null) 'pageToken': page,
        },
      );
      final json = _json(await _send(http.Request('GET', uri), token));
      final files = json['files'];
      final next = json['nextPageToken'];
      if (files is! List || (next != null && next is! String)) {
        throw GoogleDriveBackupStore._storageFailed;
      }
      found.addAll([
        for (final file in files)
          if (_DriveFile.tryParse(file) case final parsed?) parsed,
      ]);
      if (next == null || (next as String).isEmpty) return found;
      page = next;
    }
    throw GoogleDriveBackupStore._storageFailed;
  }

  /// Null for a file that vanished, or one too large or not text, which no
  /// record can be.
  Future<String?> _download(String token, String fileId) async {
    final reply = await _send(
      http.Request('GET', Uri.parse('$_filesUrl/$fileId?alt=media')),
      token,
      maxBytes: maxBackupRecordBytes,
      allowNotFound: true,
    );
    final body = reply.body;
    if (reply.status == 404 || body == null || body.isEmpty) return null;
    try {
      return utf8.decode(body);
    } on FormatException {
      return null;
    }
  }

  Future<void> _create(
    String token,
    String id,
    String raw,
    Uint8List body,
  ) async {
    final name = GoogleDriveBackupStore.fileNameFor(id);
    var boundary = _boundary();
    while (raw.contains(boundary)) {
      boundary = _boundary();
    }
    final metadata = jsonEncode({
      'name': name,
      'parents': ['appDataFolder'],
    });
    final request =
        http.Request('POST', Uri.parse('$_uploadUrl?uploadType=multipart'))
          ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
          ..bodyBytes = [
            ...utf8.encode(
              '--$boundary\r\n'
              'Content-Type: application/json; charset=UTF-8\r\n\r\n'
              '$metadata\r\n'
              '--$boundary\r\n'
              'Content-Type: application/json\r\n\r\n',
            ),
            ...body,
            ...utf8.encode('\r\n--$boundary--\r\n'),
          ];
    final created = _json(await _send(request, token));
    final fileId = created['id'];
    if (fileId is! String ||
        !_driveFileId.hasMatch(fileId) ||
        created['name'] != name) {
      throw GoogleDriveBackupStore._storageFailed;
    }
  }

  Future<void> _update(String token, String fileId, Uint8List body) async {
    final request =
        http.Request('PATCH', Uri.parse('$_uploadUrl/$fileId?uploadType=media'))
          ..headers['Content-Type'] = 'application/json'
          ..bodyBytes = body;
    final updated = _json(await _send(request, token));
    if (updated['id'] != fileId) throw GoogleDriveBackupStore._storageFailed;
  }

  Future<void> _deleteFile(String token, String fileId) => _send(
    http.Request('DELETE', Uri.parse('$_filesUrl/$fileId')),
    token,
    allowNotFound: true,
  );

  Future<_Reply> _send(
    http.Request request,
    String token, {
    int maxBytes = _maxReplyBytes,
    bool allowNotFound = false,
  }) async {
    request.headers['Authorization'] = 'Bearer $token';
    final _Reply reply;
    try {
      final response = await _client.send(request).timeout(_timeout);
      reply = _Reply(
        response.statusCode,
        await _collect(response.stream, maxBytes).timeout(_timeout),
      );
    } on Object {
      // Nothing from the request travels on: its URL and token stay here.
      throw GoogleDriveBackupStore._unavailable;
    }
    final status = reply.status;
    if (status >= 200 && status < 300) return reply;
    if (status == 404 && allowNotFound) return reply;
    if (status == 401 || status == 403) {
      // Expired, revoked, or the Drive permission was not granted: the
      // next action asks again.
      forgetToken();
      throw GoogleDriveBackupStore._unavailable;
    }
    if (status == 408 || status == 429 || status >= 500) {
      throw GoogleDriveBackupStore._unavailable;
    }
    throw GoogleDriveBackupStore._storageFailed;
  }

  Map<String, dynamic> _json(_Reply reply) {
    final body = reply.body;
    if (body != null) {
      try {
        final json = jsonDecode(utf8.decode(body));
        if (json is Map<String, dynamic>) return json;
      } on Object {
        // Falls through to the failure below.
      }
    }
    throw GoogleDriveBackupStore._storageFailed;
  }

  String _boundary() =>
      'gleec-${base64Url.encode([for (var i = 0; i < 18; i++) _random.nextInt(256)])}';
}

Future<Uint8List?> _collect(Stream<List<int>> stream, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
    if (builder.length > maxBytes) return null;
  }
  return builder.takeBytes();
}
