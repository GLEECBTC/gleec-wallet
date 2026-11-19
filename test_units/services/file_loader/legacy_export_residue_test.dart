import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:web_dex/services/file_loader/legacy_export_residue_native.dart';

/// The shape of `EncryptionTool.encryptData`: AES-CBC ciphertext, its IV and
/// the PBKDF2 salt, each base64.
Map<String, String> _envelope({
  int ciphertextBytes = 48,
  int ivBytes = 16,
  int saltBytes = 16,
}) => {
  '0': base64.encode(List.filled(ciphertextBytes, 7)),
  '1': base64.encode(List.filled(ivBytes, 1)),
  '2': base64.encode(List.filled(saltBytes, 2)),
};

void main() {
  group('Legacy iOS export residue', () {
    late Directory documents;

    setUp(() async {
      documents = await Directory.systemTemp.createTemp('export-residue-');
    });
    tearDown(() async => documents.delete(recursive: true));

    Future<File> write(String name, Object content) {
      final file = File(path.join(documents.path, name));
      return content is List<int>
          ? file.writeAsBytes(content)
          : file.writeAsString(content as String);
    }

    test('removes private key exports and legacy wallet files', () async {
      const removable = {
        'private_keys_1754031200123.txt': '{"BTC": [{"private_key": "x"}]}',
        'private_keys_1754031200124.json': '{}',
      };
      for (final entry in removable.entries) {
        await write(entry.key, entry.value);
      }
      // Named after the wallet: plain, with a dot, and pretty-printed JSON.
      await write('My wallet.txt', jsonEncode(_envelope()));
      await write('Savings.2024', jsonEncode(_envelope(ciphertextBytes: 64)));
      await write(
        'Trading.json',
        const JsonEncoder.withIndent('  ').convert(_envelope()),
      );

      final removed = await purgeExportResidueIn(documents);

      expect(
        removed,
        unorderedEquals([
          ...removable.keys,
          'My wallet.txt',
          'Savings.2024',
          'Trading.json',
        ]),
      );
      expect(await documents.list().isEmpty, isTrue);
      expect(await purgeExportResidueIn(documents), isEmpty);
    });

    test('keeps every file that is not exactly one of those', () async {
      final kept = <String, Object>{
        'private_keys_notes.txt': 'text',
        'private_keys_123.txt.bak': 'text',
        'swap_data.json': '{"uuid": "a", "events": [], "maker": "b"}',
        'notes.txt': 'not json',
        'short_iv.txt': jsonEncode(_envelope(ivBytes: 8)),
        'long_salt.txt': jsonEncode(_envelope(saltBytes: 32)),
        'unaligned.txt': jsonEncode(_envelope(ciphertextBytes: 47)),
        'empty_ciphertext.txt': jsonEncode(_envelope(ciphertextBytes: 0)),
        'extra_key.txt': jsonEncode({..._envelope(), '3': 'x'}),
        'not_base64.txt': jsonEncode({..._envelope(), '1': '!!!'}),
        'list.txt': jsonEncode([1, 2, 3]),
        'binary.hive': [0xff, 0xfe, 0x00, 0x81, 0x9f],
      };
      for (final entry in kept.entries) {
        await write(entry.key, entry.value);
      }
      // Bigger than any wallet file, so it is not even read.
      final large = jsonEncode({
        ..._envelope(),
        '0': base64.encode(List.filled(800 * 1024, 7)),
      });
      expect(large.length, greaterThan(1024 * 1024));
      await write('large.txt', large);

      expect(await purgeExportResidueIn(documents), isEmpty);
      expect(await documents.list().length, kept.length + 1);
    });

    test('never follows links or looks into folders', () async {
      final elsewhere = await Directory.systemTemp.createTemp('elsewhere-');
      addTearDown(() => elsewhere.delete(recursive: true));
      final target = await File(path.join(elsewhere.path, 'private_keys_1.txt'))
          .writeAsString(jsonEncode(_envelope()));
      final link = await Link(path.join(documents.path, 'private_keys_2.txt'))
          .create(target.path);
      final kdf = await Directory(path.join(documents.path, '.kdf')).create();
      final seed = await File(path.join(kdf.path, 'private_keys_3.txt'))
          .writeAsString(jsonEncode(_envelope()));

      expect(await purgeExportResidueIn(documents), isEmpty);
      expect(await link.exists(), isTrue);
      expect(await target.exists(), isTrue);
      expect(await seed.exists(), isTrue);
    });

    test('does nothing when the directory is missing', () async {
      final missing = Directory(path.join(documents.path, 'missing'));

      expect(await purgeExportResidueIn(missing), isEmpty);
    });

    test('on iOS, cleans Documents and counts what it removed', () async {
      await write('private_keys_1754031200123.txt', '{}');
      await write('My wallet.txt', jsonEncode(_envelope()));
      await write('notes.txt', 'kept');

      final removed = await purgeLegacyExportResidue(
        isIOS: true,
        documents: () async => documents,
      );

      expect(removed, 2);
      expect(await documents.list().length, 1);
    });

    test('off iOS, never looks at Documents', () async {
      final removed = await purgeLegacyExportResidue(
        isIOS: false,
        documents: () => fail('Documents must not be read off iOS'),
      );

      expect(removed, 0);
    });
  });
}
