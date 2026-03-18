import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/shared/utils/utils.dart';

FileLoader createFileLoader() => const FileLoaderWeb();

class FileLoaderWeb implements FileLoader {
  const FileLoaderWeb();

  @override
  Future<void> save({
    required String fileName,
    required String data,
    required LoadFileType type,
  }) async {
    switch (type) {
      case LoadFileType.text:
        if (fileName.toLowerCase().endsWith('.json')) {
          await _saveAsJsonFile(filename: fileName, data: data);
        } else {
          await _saveAsTextFile(filename: fileName, data: data);
        }
      case LoadFileType.compressed:
        await _saveAsCompressedFile(fileName: fileName, data: data);
    }
  }

  Future<void> _saveAsTextFile({
    required String filename,
    required String data,
  }) async {
    final dataArray = web.TextEncoder().encode(data);
    final blob = web.Blob(
      [dataArray].toJS,
      web.BlobPropertyBag(type: 'text/plain'),
    );

    final url = web.URL.createObjectURL(blob);

    try {
      // Create an anchor element and set the attributes
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = filename
        ..style.display = 'none';

      // Append to the DOM and trigger click
      web.document.body?.append(anchor);
      anchor
        ..click()
        ..remove();
    } finally {
      // Revoke the object URL
      web.URL.revokeObjectURL(url);
    }
  }

  Future<void> _saveAsJsonFile({
    required String filename,
    required String data,
  }) async {
    String prettyData = data;
    try {
      final dynamic decoded = json.decode(data);
      prettyData = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}

    final dataArray = web.TextEncoder().encode(prettyData);
    final blob = web.Blob(
      [dataArray].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );

    final url = web.URL.createObjectURL(blob);

    try {
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = filename
        ..style.display = 'none';
      web.document.body?.append(anchor);
      anchor
        ..click()
        ..remove();
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }

  Future<void> _saveAsCompressedFile({
    required String fileName,
    required String data,
  }) async {
    try {
      // add the extension of the contained file to the filename, so that the
      // extracted file is simply the filename excluding '.zip'
      final fileNameWithExt = '$fileName.txt';

      final encoder = web.TextEncoder();
      final dataArray = encoder.encode(data);
      final blob = web.Blob(
        [dataArray].toJS,
        web.BlobPropertyBag(type: 'text/plain'),
      );

      final response = web.Response(blob);
      final compressionStream = web.CompressionStream('gzip');
      final compressedResponse = web.Response(
        response.body!.pipeThrough(
          web.ReadableWritablePair(
            readable: compressionStream.readable,
            writable: compressionStream.writable,
          ),
        ),
      );

      final compressedBlob = await compressedResponse.blob().toDart;
      final url = web.URL.createObjectURL(compressedBlob);

      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..download = '$fileNameWithExt.zip'
        ..style.display = 'none';

      web.document.body?.append(anchor);
      anchor
        ..click()
        ..remove();

      web.URL.revokeObjectURL(url);
    } catch (e) {
      log('Error compressing and saving file: $e').ignore();
    }
  }

  @override
  Future<void> upload({
    required void Function(String name, String? content) onUpload,
    required void Function(String) onError,
    LoadFileType? fileType,
  }) async {
    final uploadInput = web.HTMLInputElement()..type = 'file';

    if (fileType != null) {
      uploadInput.accept = _getMimeType(fileType);
    }

    uploadInput.click();
    uploadInput.onChange.listen((event) {
      final web.FileList? files = uploadInput.files;
      if (files == null) {
        return;
      }

      if (files.length == 1) {
        final file = files.item(0);
        if (file == null) {
          onError('No file was selected.');
          return;
        }
        final reader = web.FileReader();

        reader.onLoadEnd.listen((_) {
          final result = reader.result;
          if (result == null) {
            onError('Failed to read ${file.name}.');
            return;
          }

          final dartResult = result.dartify();
          if (dartResult case final String content) {
            onUpload(file.name, content);
            return;
          }

          onError('Unsupported file content returned for ${file.name}.');
        });

        reader.onerror = ((JSAny _) {
          onError(reader.error?.message ?? 'Failed to read ${file.name}.');
          return null;
        }).toJS;
        reader.readAsText(file);
      }
    });
  }

  String _getMimeType(LoadFileType type) {
    switch (type) {
      case LoadFileType.compressed:
        return 'application/zip';
      case LoadFileType.text:
        return 'text/plain';
    }
  }
}
