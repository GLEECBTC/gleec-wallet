import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:web_dex/services/file_loader/guarded_file_saver.dart';
import 'package:web_dex/services/security/private_key_export_delivery.dart';
import 'package:web_dex/services/security/private_key_export_document.dart';

import 'private_key_export_test_support.dart';

void main() => testPrivateKeyExportDelivery();

void testPrivateKeyExportDelivery() {
  group('Private key export output boundary', () {
    for (final action in [
      PrivateKeyExportAction.copy,
      PrivateKeyExportAction.share,
    ]) {
      test(
        '${action.name} synchronously rechecks after asynchronous validation',
        () async {
          var current = true;
          var outputCalls = 0;
          final delivery = PlatformPrivateKeyExportDelivery(
            fileSaver: _FileSaver(),
            copy: (_) async {
              outputCalls++;
            },
            share: (_) async {
              outputCalls++;
              return const ShareResult('synthetic', ShareResultStatus.success);
            },
          );
          await expectLater(
            delivery.deliver(
              action: action,
              content: SensitiveString(exportKeySentinel),
              beforeWrite: () async {
                scheduleMicrotask(() => current = false);
              },
              beforeCommit: () {
                if (!current) throw StateError('session changed');
              },
            ),
            throwsStateError,
          );
          expect(outputCalls, 0);
        },
      );
    }

    for (final status in ShareResultStatus.values) {
      test('share ${status.name} reports its actual status', () async {
        final delivery = PlatformPrivateKeyExportDelivery(
          fileSaver: _FileSaver(),
          share: (_) async => ShareResult('synthetic', status),
        );
        final result = await delivery.deliver(
          action: PrivateKeyExportAction.share,
          content: SensitiveString(exportKeySentinel),
          beforeWrite: () async {},
          beforeCommit: () {},
        );
        expect(result, switch (status) {
          ShareResultStatus.success =>
            PrivateKeyExportDeliveryOutcome.completed,
          ShareResultStatus.dismissed =>
            PrivateKeyExportDeliveryOutcome.cancelled,
          ShareResultStatus.unavailable =>
            PrivateKeyExportDeliveryOutcome.unconfirmed,
        });
      });
    }

    test(
      'download forwards both checks and keeps unconfirmed distinct',
      () async {
        final saver = _FileSaver();
        final order = <String>[];
        final delivery = PlatformPrivateKeyExportDelivery(fileSaver: saver);
        final result = await delivery.deliver(
          action: PrivateKeyExportAction.download,
          content: SensitiveString(exportKeySentinel),
          beforeWrite: () async {
            order.add('async');
          },
          beforeCommit: () {
            order.add('sync');
          },
        );
        expect(order, ['async', 'sync']);
        expect(saver.data, exportKeySentinel);
        expect(result, PrivateKeyExportDeliveryOutcome.unconfirmed);
      },
    );

    test(
      'document exports supported keys and marks TRON assets unavailable',
      () {
        final content = privateKeyExportDocument(exportTestResult());
        final json = jsonDecode(content.value) as Map<String, dynamic>;
        expect(json['format'], 'gleec-private-key-export');
        expect(json['version'], 1);
        expect(json['complete_for_displayed_assets'], isFalse);
        expect(json, isNot(contains('contains_active_address_only')));
        final assets = json['assets'] as List<dynamic>;
        expect(assets[0]['coverage'], {
          'kind': 'offlineHdRange',
          'account_index': 0,
          'start_index': 0,
          'end_index': 10,
          'chain': 'External',
        });
        expect(assets[1]['asset_id']['coin'], 'ETH');
        expect(assets[1]['keys'], hasLength(1));
        for (final asset in assets.skip(2).take(2)) {
          expect(asset['unavailable_reason'], 'unsupportedProtocol');
          expect(asset['keys'], isEmpty);
          expect(asset, isNot(contains('coverage')));
        }
        expect(assets[4]['unavailable_reason'], 'assetUnavailable');
        expect(assets[4]['keys'], isEmpty);
        expect(content.value, contains(exportKeySentinel));
        expect(content.toString(), isNot(contains(exportKeySentinel)));
      },
    );
  });
}

class _FileSaver implements GuardedFileSaver {
  String? data;

  @override
  Future<FileSaveOutcome> save({
    required String fileName,
    required String data,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
  }) async {
    await beforeWrite();
    beforeCommit();
    this.data = data;
    return FileSaveOutcome.unconfirmed;
  }
}
