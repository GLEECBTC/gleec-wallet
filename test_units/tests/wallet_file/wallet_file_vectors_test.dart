import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:cryptography/dart.dart' show DartArgon2id;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/key_derivators/api.dart' show Argon2Parameters;
import 'package:pointycastle/key_derivators/argon2.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_file/wallet_file_codec.dart';
import 'package:web_dex/services/wallet_file/wallet_file_format.dart';

void main() => testWalletFileVectors();

const _fixturePassword = 'Fixture-file-password-1';
// Public BIP39 test vector, never a funded wallet.
const _fixturePhrase =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';

// Written once by this codec (2026-11-18). Opening it proves the reader
// still understands every byte the writer produced.
const _fixedV2File = r'''
{
  "format": "gleec-wallet-file",
  "version": 2,
  "wallet": {
    "type": "iguana",
    "derivation": "Iguana"
  },
  "kdf": {
    "algorithm": "argon2id",
    "version": 19,
    "memory_kib": 65536,
    "iterations": 2,
    "parallelism": 1,
    "salt": "tAznk1fNAyiGjV1VHckkoA=="
  },
  "cipher": {
    "algorithm": "aes-256-gcm",
    "nonce": "LNLw78BjgEuKN6TU"
  },
  "ciphertext": "NJ9ygCa9XczZ8pJVxZQE3rpxODKIgUsNdEaqnObP1ORW9Dja4sGHsu9YfN+KkHdOBwm3ONTHYN0p4dgCDwDRmcJaGj0fAAiHHYizZRNgqIsXOTTKb2LSMDsX5MhyMHKP5R8U3qZmqbHEF/uVMyD3dP5BkqJQ4kXNQSgZn0deZJODDXMAt7VAxOpmNySIfx5NKH+31rXOfJIdiSxrdVhuHXiS1a4/tbv5KHasC70SXdSbQ8Oi6YXAv2TKJMR/KSn8OBtb1cykJk+EwP4MLt7PBDYW+2PtcHDSv2VtLn/Veg7XllCJgLRpC7TIzFZu2rY233riQNf6kpNizPMQjTWzIKHoW9OL/07izLknC8bTtOEoYSwAm2M="
}
''';

// Written by the original `EncryptionTool.encryptData`, both layers.
const _fixedV1File =
    '{"0":"CqQk5yINLvkWjSgVTKpdeWHLd5FxR0+GZA/VqaGQJ2Ytb19WBmINsL0PdsSL0SLb'
    'teFhiphaeIM887AipNPAvzgOiFBP38tpJ+cszL6s14UMtYLbmx+EP6EM+52FN10OZBBBAx'
    'ud+7osd1HUC9/mgmsowxWZXFrz18PHkB8IqELN3ZbfP2DFoljK6IGhUItisDc0vF1/c/CI'
    'YZIetKRf2yXT28I0Z7puw3eHGD3xiWchsQHipRUiRxxlGDag/H4KOHJqKshp1ilVptCnHq'
    'mp/qc6W730BvPL9ZQl4K6BrPdn3bN9drG6gwh5Qw7SWmFgW0S/K345/87vimirZDRyn5Ie'
    'Xcy7V4hymMJoU0A/FWkiV9kqc19ra3HgqVjypNsXXt8N7ovS6qUsUyi1ESq+M2y6nbPzrU'
    'qlYh3JwHHHpWu8DHsHXyFOYtz7vFWTei7ntnvzx6tfbZovPeeXZjDrEqXsi/AcArKgXbKb'
    'mbGE2NzuUmkXPNd+pNUtNwRXGQTq8DL7kD/Pm7inlsNqoL4gXw==","1":"Yqvmw2+KZyJ'
    'yJhMwZJq+qw==","2":"+BctCO0xWrxmi5c5OgpEJw=="}';

// The MD5-key form `EncryptionTool` read before version 1, both layers.
const _fixedMd5File =
    '0KTa/8OBw0ehF+0wCIaU/5bSjLaoChP8B62qUcru/fZ65Z5fb0YHOE3sE+/TLJdibXySR1'
    '5nYkNK8kinwrE1OXt7WkugYpCMjB4ggySljvzeMdr645GF+4kIP/a2pyWi8uHDY+3tFuyY'
    'NBLaqNGwSQLkXmmsw7M1u8Fmk17ZeYMKe+fNrRmPkoS4gwj5WWQQ1Ty+cm8UAGIFiqfQH5'
    'dtVgXnQG9PzFy2D1zKwqBA21OIdCHnU88uzY1Q6J916AlTGt7I3QJMAx3bQMVL3zRytJ71'
    'AX+gTqVq/QJ6gwp2+b8Si8Mc9NRTR1Q6mmfy91f8jyTsu9yqF8wfvor6d9vRiqtncRnsUT'
    'dn1GNUe/sxDu8evQ+gakEQ0NSMpHrdztDilSBJOZulBOJneYxd4jvVKTMghQnmeRUiauyb'
    'kiT8Fn4=';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Matcher _fails(WalletFileFailure failure) => throwsA(
  isA<WalletFileException>().having((e) => e.failure, 'failure', failure),
);

void testWalletFileVectors() {
  group('Wallet file vectors', () {
    test('Argon2id matches RFC 9106 section 5.3', () async {
      final key =
          await const DartArgon2id(
            parallelism: 4,
            memory: 32,
            iterations: 3,
            hashLength: 32,
            maxIsolates: 0,
          ).deriveKey(
            secretKey: SecretKey(List.filled(32, 0x01)),
            nonce: List.filled(16, 0x02),
            optionalSecret: List.filled(8, 0x03),
            associatedData: List.filled(12, 0x04),
          );
      expect(
        _hex(await key.extractBytes()),
        '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
      );
    });

    test('the file key at production parameters is fixed', () async {
      const password = 'correct horse battery staple';
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      const expected =
          'c05ce4c4dd7e0e45ee6011cc59d068ade47df1b01fc0cf9cd4678bdf68a5b7b0';
      final key = await deriveWalletFileKey(password, WalletFileKdf(salt));
      expect(_hex(key), expected);
      // An independent implementation agrees. Its browser build needs about
      // 800 MB for these parameters, which is why it is not the one used.
      if (kIsWeb) return;
      final pointycastle = Argon2BytesGenerator()
        ..init(
          Argon2Parameters(
            Argon2Parameters.ARGON2_id,
            salt,
            desiredKeyLength: 32,
            iterations: 2,
            memory: 65536,
            lanes: 1,
            version: Argon2Parameters.ARGON2_VERSION_13,
          ),
        );
      expect(_hex(pointycastle.process(utf8.encode(password))), expected);
    });

    test('a fixed version 2 file opens with its recorded type', () async {
      final inspection = WalletFileInspection.of(_fixedV2File);
      expect(inspection.kind, WalletFileKind.current);
      expect(inspection.recordedType, WalletType.iguana);
      final opened = await const WalletFileCodec().open(
        password: _fixturePassword,
        content: _fixedV2File,
      );
      expect(opened.recordedType, WalletType.iguana);
      expect(opened.config.type, WalletType.iguana);
      expect(opened.config.seedPhrase, _fixturePhrase);
      expect(opened.config.activatedCoins, ['KMD', 'BTC-segwit']);
    });

    for (final (name, file) in [
      ('version 1', _fixedV1File),
      ('MD5-key', _fixedMd5File),
    ]) {
      test('a fixed $name file still imports, leaving the type open', () async {
        expect(WalletFileInspection.of(file).kind, WalletFileKind.legacy);
        final opened = await const WalletFileCodec().open(
          password: _fixturePassword,
          content: '$file\n',
        );
        expect(opened.recordedType, isNull);
        expect(opened.config.seedPhrase, _fixturePhrase);
        expect(opened.config.activatedCoins, ['KMD', 'BTC-segwit']);
        await expectLater(
          const WalletFileCodec().open(password: 'wrong', content: file),
          _fails(WalletFileFailure.cannotOpen),
        );
      });
    }
  });
}
