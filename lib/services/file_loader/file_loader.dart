import 'package:file_picker/file_picker.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/file_loader/file_loader_stub.dart'
    if (dart.library.io) 'package:web_dex/services/file_loader/file_loader_native.dart'
    if (dart.library.js_interop) 'package:web_dex/services/file_loader/file_loader_web.dart';

abstract class FileLoader {
  const FileLoader();

  factory FileLoader.fromPlatform() => createFileLoader();

  Future<void> save({
    required String fileName,
    required String data,
    required LoadFileType type,
    void Function()? beforeWrite,
    GuardedDestinationSelector? selectDestination,
  });
  Future<void> upload({
    required void Function(String name, String? content) onUpload,
    required void Function(String) onError,
    LoadFileType? fileType,
  });
}

/// Closed cancellation result for guarded exports; no wallet data is included.
class FileSaveCancelledException implements Exception {
  const FileSaveCancelledException();
}

/// Browser download requests cannot establish whether a file was saved.
class FileSaveUnconfirmedException implements Exception {
  const FileSaveUnconfirmedException();
}

/// Sensitive text exports use destination selection without passing contents
/// to the picker, then recheck authorization immediately before the write.
Future<void> saveGuardedTextFile({
  required String fileName,
  required String data,
  required LoadFileType type,
  required void Function() beforeWrite,
  GuardedDestinationSelector? selectDestination,
}) async {
  if (type != LoadFileType.text) {
    throw UnsupportedError('Guarded file export requires text content');
  }
  beforeWrite();
  final outcome = await GuardedFileSaver.fromPlatform().save(
    fileName: fileName.contains('.') ? fileName : '$fileName.txt',
    data: data,
    beforeWrite: () async => beforeWrite(),
    beforeCommit: beforeWrite,
    selectDestination: selectDestination,
  );
  if (outcome == FileSaveOutcome.cancelled) {
    throw const FileSaveCancelledException();
  }
  if (outcome == FileSaveOutcome.unconfirmed) {
    throw const FileSaveUnconfirmedException();
  }
}

enum LoadFileType {
  compressed,
  text;

  FileType get fileType {
    switch (this) {
      case LoadFileType.compressed:
      case LoadFileType.text:
        return FileType.custom;
    }
  }

  String get mimeType {
    switch (this) {
      case LoadFileType.compressed:
        return 'application/zip';
      case LoadFileType.text:
        return 'text/plain';
    }
  }

  String get extension {
    switch (this) {
      case LoadFileType.compressed:
        return 'zip';
      case LoadFileType.text:
        return 'txt';
    }
  }
}
