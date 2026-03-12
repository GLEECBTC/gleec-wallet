import 'package:file_picker/file_picker.dart';
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
  });
  Future<void> upload({
    required void Function(String name, String? content) onUpload,
    required void Function(String) onError,
    LoadFileType? fileType,
  });
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
