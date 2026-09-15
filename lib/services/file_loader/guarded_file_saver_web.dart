import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'guarded_file_saver.dart';

GuardedFileSaver createGuardedFileSaver() => const WebGuardedFileSaver();

class WebGuardedFileSaver implements GuardedFileSaver {
  const WebGuardedFileSaver();

  @override
  Future<FileSaveOutcome> save({
    required String fileName,
    required String data,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
  }) async {
    await beforeWrite();
    beforeCommit();
    final body = web.document.body;
    if (body == null) return FileSaveOutcome.unconfirmed;
    final blob = web.Blob(
      [web.TextEncoder().encode(data)].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    try {
      body.append(anchor);
      beforeCommit();
      anchor.click();
      // Anchor downloads cannot report a blocked or cancelled save prompt.
      return FileSaveOutcome.unconfirmed;
    } finally {
      anchor.remove();
      web.URL.revokeObjectURL(url);
    }
  }
}
