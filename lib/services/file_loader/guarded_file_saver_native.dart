import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' show Rect, RenderBox, Offset;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web_dex/app_config/app_config.dart';

import 'guarded_file_saver.dart';

GuardedFileSaver createGuardedFileSaver() {
  if (Platform.isAndroid) return const AndroidGuardedFileSaver();
  if (Platform.isIOS) return IosGuardedFileSaver();
  return DesktopGuardedFileSaver();
}

class DesktopGuardedFileSaver implements GuardedFileSaver {
  DesktopGuardedFileSaver({Future<String?> Function(String)? selectDestination})
    : _selectDestination = selectDestination ?? _chooseDestination;

  final Future<String?> Function(String) _selectDestination;

  static Future<String?> _chooseDestination(String fileName) =>
      FilePicker.platform.saveFile(fileName: fileName);

  @override
  Future<FileSaveOutcome> save({
    required String fileName,
    required String data,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
  }) async {
    final destination = await _selectDestination(path.basename(fileName));
    if (destination == null || destination.isEmpty) {
      return FileSaveOutcome.cancelled;
    }
    await beforeWrite();
    beforeCommit();
    // The final generation check and write share one synchronous turn.
    File(destination).writeAsStringSync(data, flush: true);
    return FileSaveOutcome.completed;
  }
}

class AndroidGuardedFileSaver implements GuardedFileSaver {
  const AndroidGuardedFileSaver({
    MethodChannel channel = const MethodChannel('gleec/sensitive-file-export'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<FileSaveOutcome> save({
    required String fileName,
    required String data,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
  }) async {
    final token = await _channel.invokeMethod<String>('chooseDestination', {
      'fileName': path.basename(fileName),
    });
    if (token == null) return FileSaveOutcome.cancelled;
    try {
      await beforeWrite();
      beforeCommit();
      await _channel.invokeMethod<void>('write', {
        'token': token,
        'data': data,
      });
      return FileSaveOutcome.completed;
    } finally {
      // The native side consumes successful writes. Otherwise this removes the
      // empty document and the destination capability, without sending data.
      await _channel.invokeMethod<void>('discard', {'token': token});
    }
  }
}

class IosGuardedFileSaver implements GuardedFileSaver {
  IosGuardedFileSaver({
    Future<Directory> Function()? temporaryDirectory,
    Future<ShareResult> Function(ShareParams)? share,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _share = share ?? _shareFile;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<ShareResult> Function(ShareParams) _share;

  static Future<ShareResult> _shareFile(ShareParams params) =>
      SharePlus.instance.share(params);

  @override
  Future<FileSaveOutcome> save({
    required String fileName,
    required String data,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
  }) async {
    final temporary = await _temporaryDirectory();
    final directory = await temporary.createTemp('key-export-');
    final file = File(path.join(directory.path, path.basename(fileName)));
    try {
      await beforeWrite();
      beforeCommit();
      file.writeAsStringSync(data, flush: true);
      final result = await _share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          sharePositionOrigin: _shareOrigin(),
        ),
      );
      return switch (result.status) {
        ShareResultStatus.success => FileSaveOutcome.completed,
        ShareResultStatus.dismissed => FileSaveOutcome.cancelled,
        ShareResultStatus.unavailable => FileSaveOutcome.unconfirmed,
      };
    } finally {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  }

  Rect? _shareOrigin() {
    final box = scaffoldKey.currentContext?.findRenderObject();
    return box is RenderBox ? box.localToGlobal(Offset.zero) & box.size : null;
  }
}
