import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_file/wallet_file_codec.dart';
import 'package:web_dex/services/wallet_file/wallet_file_format.dart';

void main() => testWalletFileFormat();

/// A structurally valid version 2 file. Its ciphertext opens with nothing:
/// these cases are decided before any key is derived.
Map<String, Object?> _validFile() => jsonDecode(
  WalletFileDocument(
    WalletFileHeader(
      walletType: WalletType.hdwallet,
      kdf: WalletFileKdf(Uint8List(16)),
      nonce: Uint8List(12),
    ),
    Uint8List(48),
  ).encode(),
) as Map<String, Object?>;

WalletFileKind _kindOf(Object? json) =>
    WalletFileInspection.of(jsonEncode(json)).kind;

Map<String, Object?> _with(void Function(Map<String, Object?> file) change) {
  final file = _validFile();
  change(file);
  return file;
}

Map<String, Object?> _section(Map<String, Object?> file, String key) =>
    file[key]! as Map<String, Object?>;

void testWalletFileFormat() {
  group('Wallet file format', () {
    test('a valid header is current and names its wallet type', () {
      final inspection = WalletFileInspection.of(jsonEncode(_validFile()));
      expect(inspection.kind, WalletFileKind.current);
      expect(inspection.recordedType, WalletType.hdwallet);
    });

    test('a byte-order mark and surrounding whitespace are ignored', () {
      final text = '\uFEFF\n  ${jsonEncode(_validFile())}\r\n';
      expect(WalletFileInspection.of(text).kind, WalletFileKind.current);
    });

    test('associated data depends on values, not on spelling or order', () {
      final original = WalletFileInspection.of(jsonEncode(_validFile()));
      final reordered = _validFile().entries.toList().reversed;
      final rewritten = WalletFileInspection.of(
        const JsonEncoder.withIndent('    ')
            .convert(Map.fromEntries(reordered)),
      );
      expect(
        rewritten.document!.header.associatedData,
        original.document!.header.associatedData,
      );
      final changed = WalletFileInspection.of(
        jsonEncode(
          _with(
            (file) => _section(file, 'kdf')['salt'] = base64Encode(
              List.filled(16, 7),
            ),
          ),
        ),
      );
      expect(
        changed.document!.header.associatedData,
        isNot(original.document!.header.associatedData),
      );
    });

    test('no field is optional and no unknown field is accepted', () {
      expect(
        _kindOf(_with((file) => file['note'] = 'x')),
        WalletFileKind.damaged,
      );
      expect(
        _kindOf(_with((file) => file.remove('cipher'))),
        WalletFileKind.damaged,
      );
      for (final section in ['wallet', 'kdf', 'cipher']) {
        expect(
          _kindOf(_with((file) => _section(file, section)['extra'] = 1)),
          WalletFileKind.damaged,
          reason: section,
        );
      }
      expect(
        _kindOf(_with((file) => _section(file, 'kdf').remove('salt'))),
        WalletFileKind.damaged,
      );
    });

    test('Argon2id parameters are exactly the writer\'s', () {
      final cases = <(String, Object?)>[
        // Weaker than the engine's own, or costlier than a file needs.
        ('memory_kib', 32768),
        ('memory_kib', 65537),
        ('memory_kib', 262144),
        ('iterations', 1),
        ('iterations', 3),
        ('parallelism', 0),
        ('parallelism', 2),
        ('iterations', '2'),
        ('memory_kib', null),
      ];
      for (final (key, value) in cases) {
        expect(
          _kindOf(_with((file) => _section(file, 'kdf')[key] = value)),
          WalletFileKind.damaged,
          reason: '$key $value',
        );
      }
    });

    test('a broken copy of a current file is damaged, not legacy', () {
      final text = jsonEncode(_validFile());
      final ciphertext = _validFile()['ciphertext']! as String;
      final broken = <String, String>{
        'truncated': text.substring(0, text.length ~/ 2),
        // A mail client wrapping the base64 breaks the JSON string.
        'wrapped': text.replaceFirst(
          ciphertext,
          '${ciphertext.substring(0, 20)}\n${ciphertext.substring(20)}',
        ),
        'retyped quotes': text.replaceAll('"', '\u201C'),
        'renamed': text.replaceFirst('gleec-wallet-file', 'wallet-file'),
        'encoded twice': jsonEncode(text),
      };
      for (final MapEntry(key: name, value: content) in broken.entries) {
        expect(
          WalletFileInspection.of(content).kind,
          WalletFileKind.damaged,
          reason: name,
        );
      }
    });

    test('only the recorded algorithms are accepted', () {
      final changes = <void Function(Map<String, Object?>)>[
        (file) => _section(file, 'kdf')['algorithm'] = 'argon2i',
        (file) => _section(file, 'kdf')['version'] = 0x10,
        (file) => _section(file, 'cipher')['algorithm'] = 'aes-128-cbc',
        (file) => file['format'] = 'gleec-wallet-file-x',
      ];
      for (final change in changes) {
        expect(_kindOf(_with(change)), isNot(WalletFileKind.current));
      }
    });

    test('the wallet type and its derivation must be a known pair', () {
      final pairs = <List<String>>[
        ['hdwallet', 'Iguana'],
        ['iguana', 'HDWallet'],
        ['trezor', 'HDWallet'],
        ['hdwallet', 'hdWallet'],
      ];
      for (final [type, derivation] in pairs) {
        final file = _with((file) {
          _section(file, 'wallet')
            ..['type'] = type
            ..['derivation'] = derivation;
        });
        expect(
          _kindOf(file),
          WalletFileKind.damaged,
          reason: '$type/$derivation',
        );
      }
      final iguana = _with((file) {
        _section(file, 'wallet')
          ..['type'] = 'iguana'
          ..['derivation'] = 'Iguana';
      });
      final inspection = WalletFileInspection.of(jsonEncode(iguana));
      expect(inspection.recordedType, WalletType.iguana);
    });

    test('salt, nonce and ciphertext must be canonical and sized', () {
      final short = base64Encode(Uint8List(15));
      final urlSafe = base64Url.encode(List.filled(16, 0xfb));
      final changes = <void Function(Map<String, Object?>)>[
        (file) => _section(file, 'kdf')['salt'] = short,
        (file) => _section(file, 'kdf')['salt'] = urlSafe,
        (file) => _section(file, 'kdf')['salt'] = 'not base64!',
        (file) =>
            _section(file, 'cipher')['nonce'] = base64Encode(Uint8List(16)),
        (file) => file['ciphertext'] = base64Encode(Uint8List(16)),
        (file) => file['ciphertext'] = base64Encode(Uint8List(64 * 1024 + 1)),
        (file) => file['ciphertext'] = 42,
      ];
      for (final change in changes) {
        expect(_kindOf(_with(change)), WalletFileKind.damaged);
      }
    });

    test('a later version is newer, never a wrong password', () async {
      final newer = _with((file) => file['version'] = 3);
      expect(_kindOf(newer), WalletFileKind.newer);
      expect(
        _kindOf(_with((file) => file['version'] = 1)),
        WalletFileKind.damaged,
      );
      expect(
        _kindOf(_with((file) => file['version'] = '2')),
        WalletFileKind.damaged,
      );
      await expectLater(
        const WalletFileCodec().open(password: 'x', content: jsonEncode(newer)),
        throwsA(
          isA<WalletFileException>().having(
            (e) => e.failure,
            'failure',
            WalletFileFailure.newer,
          ),
        ),
      );
      await expectLater(
        const WalletFileCodec().open(
          password: 'x',
          content: jsonEncode(_with((file) => file['note'] = 1)),
        ),
        throwsA(
          isA<WalletFileException>().having(
            (e) => e.failure,
            'failure',
            WalletFileFailure.damaged,
          ),
        ),
      );
    });

    test('older shapes are legacy and anything else is unrecognized', () {
      final iv = base64Encode(Uint8List(16));
      expect(_kindOf({'0': iv, '1': iv, '2': iv}), WalletFileKind.legacy);
      expect(
        WalletFileInspection.of(base64Encode(Uint8List(48))).kind,
        WalletFileKind.legacy,
      );
      expect(_kindOf({'0': iv, '1': iv}), WalletFileKind.unrecognized);
      expect(_kindOf([1, 2]), WalletFileKind.unrecognized);
      expect(_kindOf({'note': 'something else'}), WalletFileKind.unrecognized);
      expect(
        WalletFileInspection.of('just some notes').kind,
        WalletFileKind.unrecognized,
      );
      expect(WalletFileInspection.of('').kind, WalletFileKind.unrecognized);
      expect(WalletFileInspection.of('{"0":1').recordedType, isNull);
    });
  });
}
