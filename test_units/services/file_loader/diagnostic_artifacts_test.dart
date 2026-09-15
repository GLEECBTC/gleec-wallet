import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:web_dex/services/file_loader/diagnostic_artifacts_native.dart';

void main() {
  group('Legacy diagnostic archive migration', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'diagnostic-migration-',
      );
    });
    tearDown(() async => directory.delete(recursive: true));

    test(
      'deletes exact legacy archives and preserves wallet/user files',
      () async {
        const removed = 'komodo_wallet_log_07.09.2026_20-52-41.zip';
        const retained = [
          'wallet.json',
          'private_keys_123.json',
          'komodo_wallet_log_notes.zip',
          'komodo_wallet_log_07.09.2026_20-52-41.zip.backup',
          'another_log_07.09.2026_20-52-41.zip',
        ];
        for (final name in [removed, ...retained]) {
          await File(path.join(directory.path, name)).writeAsString('fixture');
        }
        await purgeDiagnosticArchivesIn(directory);
        expect(
          await File(path.join(directory.path, removed)).exists(),
          isFalse,
        );
        for (final name in retained) {
          expect(
            await File(path.join(directory.path, name)).readAsString(),
            'fixture',
          );
        }
        await purgeDiagnosticArchivesIn(directory);
        expect(await directory.list().length, retained.length);
      },
    );

    test(
      'does not follow matching links or traverse unrelated directories',
      () async {
        final nested = await Directory(
          path.join(directory.path, 'backups'),
        ).create();
        final wallet = await File(
          path.join(nested.path, 'wallet.json'),
        ).writeAsString('wallet fixture');
        final link = await Link(
          path.join(
            directory.path,
            'komodo_wallet_log_07.09.2026_20-52-41.zip',
          ),
        ).create(wallet.path);
        await purgeDiagnosticArchivesIn(directory);
        expect(await link.exists(), isTrue);
        expect(await wallet.readAsString(), 'wallet fixture');
      },
    );
  });
}
