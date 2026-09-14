import 'package:flutter/services.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';

enum PrivateKeyExportAction { copy, download }

enum PrivateKeyExportDeliveryOutcome { completed, cancelled, unconfirmed }

abstract class PrivateKeyExportDelivery {
  Future<PrivateKeyExportDeliveryOutcome> deliver({
    required PrivateKeyExportAction action,
    required SensitiveString content,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
  });
}

class PlatformPrivateKeyExportDelivery implements PrivateKeyExportDelivery {
  PlatformPrivateKeyExportDelivery({
    GuardedFileSaver? fileSaver,
    Future<void> Function(String)? copy,
  }) : _fileSaver = fileSaver ?? GuardedFileSaver.fromPlatform(),
       _copy = copy ?? _copyToClipboard;

  final GuardedFileSaver _fileSaver;
  final Future<void> Function(String) _copy;

  static Future<void> _copyToClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<PrivateKeyExportDeliveryOutcome> deliver({
    required PrivateKeyExportAction action,
    required SensitiveString content,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
  }) async {
    switch (action) {
      case PrivateKeyExportAction.copy:
        await beforeWrite();
        beforeCommit();
        await _copy(content.value);
        return PrivateKeyExportDeliveryOutcome.completed;
      case PrivateKeyExportAction.download:
        final outcome = await _fileSaver.save(
          fileName:
              'private_keys_${DateTime.now().millisecondsSinceEpoch}.json',
          data: content.value,
          beforeWrite: beforeWrite,
          beforeCommit: beforeCommit,
        );
        return switch (outcome) {
          FileSaveOutcome.completed =>
            PrivateKeyExportDeliveryOutcome.completed,
          FileSaveOutcome.cancelled =>
            PrivateKeyExportDeliveryOutcome.cancelled,
          FileSaveOutcome.unconfirmed =>
            PrivateKeyExportDeliveryOutcome.unconfirmed,
        };
    }
  }
}
