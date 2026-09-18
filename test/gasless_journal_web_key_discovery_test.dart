@TestOn('browser')
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('deployed web storage discovers only bounded V1 GasFree keys', () async {
    final legacyKey =
        'gasless_pending_transfers_v1_'
        '${sha256.convert(utf8.encode('deployed-preview-v1-journal'))}';
    final secondLegacyKey =
        'gasless_pending_transfers_v1_'
        '${sha256.convert(utf8.encode('second-deployed-preview-v1-journal'))}';
    final unrelatedKey =
        'gasless_pending_transfers_v2_'
        '${sha256.convert(utf8.encode('unrelated-current-journal'))}';
    final rawLegacyKey = 'FlutterSecureStorage.$legacyKey';
    final rawSecondLegacyKey = 'FlutterSecureStorage.$secondLegacyKey';
    final rawUnrelatedKey = 'FlutterSecureStorage.$unrelatedKey';
    web.window.localStorage.setItem(rawLegacyKey, 'encrypted-v1-marker');
    web.window.localStorage.setItem(
      rawSecondLegacyKey,
      'second-encrypted-v1-marker',
    );
    web.window.localStorage.setItem(rawUnrelatedKey, 'encrypted-v2-marker');
    addTearDown(() {
      web.window.localStorage.removeItem(rawLegacyKey);
      web.window.localStorage.removeItem(rawSecondLegacyKey);
      web.window.localStorage.removeItem(rawUnrelatedKey);
    });

    final storage = SecureGaslessTransferStorage();
    final discovery = storage as GaslessTransferKeyDiscovery;

    await expectLater(
      discovery.keysWithPrefix('gasless_pending_transfers_v1_', maxKeys: 1),
      throwsStateError,
    );
    expect(
      await discovery.keysWithPrefix(
        'gasless_pending_transfers_v1_',
        maxKeys: 64,
      ),
      {legacyKey, secondLegacyKey},
    );
  });
}
