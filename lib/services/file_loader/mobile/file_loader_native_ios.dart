import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/services/file_loader/diagnostic_artifacts_native.dart';
import 'package:web_dex/shared/utils/zip.dart';

class FileLoaderNativeIOS implements FileLoader {
  const FileLoaderNativeIOS();

  Rect? _getSharePositionOrigin() {
    final context = scaffoldKey.currentContext;
    if (context == null) return null;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;

    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Future<void> save({
    required String fileName,
    required String data,
    LoadFileType type = LoadFileType.text,
  }) async {
    switch (type) {
      case LoadFileType.text:
        if (path.extension(fileName).toLowerCase() == '.json') {
          await _saveAsJsonFile(fileName: fileName, data: data);
        } else {
          await _saveAsTextFile(fileName: fileName, data: data);
        }
        break;
      case LoadFileType.compressed:
        await _saveAsCompressedFile(fileName: fileName, data: data);
        break;
    }
  }

  Future<void> _saveAsTextFile({
    required String fileName,
    required String data,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final String suggestedName = path.extension(fileName).isEmpty
        ? '$fileName.txt'
        : fileName;
    final filePath = path.join(directory.path, suggestedName);
    final File file = File(filePath);
    await file.writeAsString(data);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(file.path, name: '$fileName.txt', mimeType: 'text/plain'),
        ],
        sharePositionOrigin: _getSharePositionOrigin(),
      ),
    );
  }

  Future<void> _saveAsJsonFile({
    required String fileName,
    required String data,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final String suggestedName = path.extension(fileName).isEmpty
        ? '$fileName.json'
        : fileName;
    final filePath = path.join(directory.path, suggestedName);

    String prettyData = data;
    try {
      final dynamic decoded = json.decode(data);
      prettyData = const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {}

    final File file = File(filePath);
    await file.writeAsString(prettyData);

    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _saveAsCompressedFile({
    required String fileName,
    required String data,
  }) async {
    final isDiagnostic = fileName.startsWith('komodo_wallet_log_');
    final directory = isDiagnostic
        ? await diagnosticShareDirectory()
        : await getApplicationDocumentsDirectory();
    final filePath = path.join(directory.path, '$fileName.zip');

    final compressedBytes = createZipOfSingleFile(
      fileName: fileName,
      fileContent: data,
    );

    final File compressedFile = File(filePath);
    await compressedFile.writeAsBytes(compressedBytes);

    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              compressedFile.path,
              name: '$fileName.zip',
              mimeType: 'application/zip',
            ),
          ],
          sharePositionOrigin: _getSharePositionOrigin(),
        ),
      );
    } finally {
      if (isDiagnostic && await compressedFile.exists()) {
        await compressedFile.delete();
      }
    }
  }

  @override
  Future<void> upload({
    required void Function(String name, String content) onUpload,
    required void Function(String) onError,
    LoadFileType? fileType,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: fileType == null ? FileType.any : fileType.fileType,
        allowedExtensions: fileType != null ? [fileType.extension] : null,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;
      if (path == null) return;

      final selectedFile = File(path);
      final data = await selectedFile.readAsString();

      onUpload(file.name, data);
    } catch (e) {
      onError(e.toString());
    }
  }
}
