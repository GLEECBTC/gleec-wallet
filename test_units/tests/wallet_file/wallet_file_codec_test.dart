import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show DerivationMethod;
import 'package:pointycastle/export.dart'
    show AEADParameters, AESEngine, GCMBlockCipher, KeyParameter;
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_file/wallet_file_codec.dart';
import 'package:web_dex/services/wallet_file/wallet_file_format.dart';

void main() => testWalletFileCodec();

// Public BIP39 test vector, never a funded wallet.
const _phrase =
    'legal winner thank year wave sausage worth useful legal winner thank yellow';
const _password = 'Codec-fixture-password-7';
const _codec = WalletFileCodec();

WalletConfig _config({WalletType type = WalletType.hdwallet}) => WalletConfig(
  seedPhrase: '',
  activatedCoins: ['KMD', 'BTC-segwit'],
  hasBackup: true,
  type: type,
  displayName: 'Savings',
);

Future<String> _seal({
  String mnemonic = _phrase,
  WalletType appType = WalletType.hdwallet,
  DerivationMethod derivation = DerivationMethod.hdWallet,
}) => _codec.seal(
  password: _password,
  mnemonic: mnemonic,
  config: _config(type: appType),
  derivation: derivation,
);

Matcher _fails(WalletFileFailure failure) => throwsA(
  isA<WalletFileException>().having((e) => e.failure, 'failure', failure),
);

String _edit(String file, void Function(Map<String, dynamic> json) change) {
  final json = jsonDecode(file) as Map<String, dynamic>;
  change(json);
  return jsonEncode(json);
}

String _flipped(Object? base64Text, int index) {
  final bytes = base64Decode(base64Text! as String);
  bytes[index] ^= 0x01;
  return base64Encode(bytes);
}

Uint8List _gcm(
  bool encrypt,
  Uint8List key,
  WalletFileHeader header,
  Uint8List input,
) =>
    (GCMBlockCipher(AESEngine())..init(
          encrypt,
          AEADParameters(
            KeyParameter(key),
            128,
            header.nonce,
            header.associatedData,
          ),
        ))
        .process(input);

/// A correctly authenticated file around [payload], which this codec's
/// writer would never produce.
Future<String> _sealRaw(String payload) async {
  final random = Random.secure();
  Uint8List bytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => random.nextInt(256)));
  final header = WalletFileHeader(
    walletType: WalletType.hdwallet,
    kdf: WalletFileKdf(bytes(16)),
    nonce: bytes(12),
  );
  final key = await deriveWalletFileKey(_password, header.kdf);
  final ciphertext = _gcm(true, key, header, utf8.encode(payload));
  return WalletFileDocument(header, ciphertext).encode();
}

void testWalletFileCodec() {
  group('Wallet file codec', () {
    late String hdFile;

    setUpAll(() async => hdFile = await _seal());

    test('a round trip restores the phrase, config and HD type', () async {
      final opened = await _codec.open(password: _password, content: hdFile);
      expect(opened.recordedType, WalletType.hdwallet);
      expect(opened.config.type, WalletType.hdwallet);
      expect(opened.config.seedPhrase, _phrase);
      expect(opened.config.activatedCoins, ['KMD', 'BTC-segwit']);
      expect(opened.config.displayName, 'Savings');
    });

    test('the engine derivation decides the recorded type', () async {
      // The app's label says HD; the engine derives iguana addresses.
      const custom = 'my own words, not a BIP39 phrase';
      final file = await _seal(
        mnemonic: custom,
        derivation: DerivationMethod.iguana,
      );
      expect(WalletFileInspection.of(file).recordedType, WalletType.iguana);
      final opened = await _codec.open(password: _password, content: file);
      expect(opened.recordedType, WalletType.iguana);
      expect(opened.config.type, WalletType.iguana);
      expect(opened.config.seedPhrase, custom);
    });

    test('only the header holds the type, and nothing leaks', () async {
      final json = jsonDecode(hdFile) as Map<String, dynamic>;
      expect(json['wallet'], {'type': 'hdwallet', 'derivation': 'HDWallet'});
      expect(json['kdf'], containsPair('memory_kib', 65536));
      expect(json['kdf'], containsPair('iterations', 2));
      expect(json['kdf'], containsPair('parallelism', 1));
      for (final secret in [_password, 'legal winner', 'KMD', 'Savings']) {
        expect(hdFile.contains(secret), isFalse, reason: secret);
      }
      final document = WalletFileInspection.of(hdFile).document!;
      final key = await deriveWalletFileKey(_password, document.header.kdf);
      final payload = jsonDecode(
        utf8.decode(_gcm(false, key, document.header, document.ciphertext)),
      ) as Map<String, dynamic>;
      expect(payload.containsKey('type'), isFalse);
      expect(payload['seed_phrase'], _phrase);
    });

    test('every file gets its own salt and nonce', () async {
      final first = WalletFileInspection.of(hdFile).document!;
      final second = WalletFileInspection.of(await _seal()).document!;
      expect(second.header.kdf.salt, isNot(first.header.kdf.salt));
      expect(second.header.nonce, isNot(first.header.nonce));
      expect(second.ciphertext, isNot(first.ciphertext));
    });

    test('a wrong password cannot open it', () async {
      for (final password in ['${_password}x', '', _password.toLowerCase()]) {
        await expectLater(
          _codec.open(password: password, content: hdFile),
          _fails(WalletFileFailure.cannotOpen),
        );
      }
    });

    test('a changed byte in the ciphertext or its tag is detected', () async {
      final length = base64Decode(
        (jsonDecode(hdFile) as Map<String, dynamic>)['ciphertext'] as String,
      ).length;
      for (final index in [0, length ~/ 2, length - 1]) {
        final tampered = _edit(
          hdFile,
          (json) => json['ciphertext'] = _flipped(json['ciphertext'], index),
        );
        await expectLater(
          _codec.open(password: _password, content: tampered),
          _fails(WalletFileFailure.cannotOpen),
          reason: 'byte $index',
        );
      }
    });

    test('every header field is bound to the ciphertext', () async {
      final changes = <String, void Function(Map<String, dynamic>)>{
        'wallet type': (json) =>
            json['wallet'] = {'type': 'iguana', 'derivation': 'Iguana'},
        'salt': (json) =>
            json['kdf']['salt'] = _flipped(json['kdf']['salt'], 0),
        'nonce': (json) =>
            json['cipher']['nonce'] = _flipped(json['cipher']['nonce'], 11),
      };
      for (final MapEntry(key: field, value: change) in changes.entries) {
        final tampered = _edit(hdFile, change);
        expect(
          WalletFileInspection.of(tampered).kind,
          WalletFileKind.current,
          reason: '$field still parses',
        );
        await expectLater(
          _codec.open(password: _password, content: tampered),
          _fails(WalletFileFailure.cannotOpen),
          reason: field,
        );
      }
    });

    test('other Argon2id parameters are refused before any work', () async {
      for (final (key, value) in [
        ('memory_kib', 262144),
        ('iterations', 8),
        ('parallelism', 4),
      ]) {
        await expectLater(
          _codec.open(
            password: _password,
            content: _edit(hdFile, (json) => json['kdf'][key] = value),
          ),
          _fails(WalletFileFailure.damaged),
          reason: key,
        );
      }
    });

    test('a reformatted file still opens', () async {
      final json = jsonDecode(hdFile) as Map<String, dynamic>;
      final reordered = Map.fromEntries(json.entries.toList().reversed);
      final opened = await _codec.open(
        password: _password,
        content: '\uFEFF${jsonEncode(reordered)}\n',
      );
      expect(opened.config.seedPhrase, _phrase);
    });

    test('sealing refuses an empty phrase', () async {
      await expectLater(_seal(mnemonic: ''), throwsArgumentError);
    });

    test('an authenticated payload that is no wallet is damaged', () async {
      for (final payload in ['[1, 2, 3]', '{"seed_phrase": ""}', 'not json']) {
        await expectLater(
          _codec.open(password: _password, content: await _sealRaw(payload)),
          _fails(WalletFileFailure.damaged),
          reason: payload,
        );
      }
    });
  });
}
