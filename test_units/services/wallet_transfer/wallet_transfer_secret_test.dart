import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

/// The BIP-39 test phrase: public test data, never a real wallet.
const _phrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about';

WalletTransferSecret _secret({
  String name = 'Main wallet',
  TransferWalletType type = TransferWalletType.hd,
  String seed = _phrase,
  bool phraseConfirmed = true,
}) => WalletTransferSecret(
  walletName: name,
  type: type,
  seed: seed,
  phraseConfirmed: phraseConfirmed,
);

Map<String, Object?> _json() => {
  'v': 1,
  'name': 'Main wallet',
  'type': 'hd',
  'seed': _phrase,
  'phraseConfirmed': true,
};

WalletTransferSecret _decode(Map<String, Object?> json) =>
    WalletTransferSecret.decode(utf8.encode(jsonEncode(json)));

/// Refused, without echoing the phrase or the input.
final _invalid = throwsA(
  isA<FormatException>()
      .having((e) => e.source, 'source', isNull)
      .having((e) => e.toString(), 'text', isNot(contains('abandon'))),
);

bool _containsRun(List<int> haystack, List<int> needle) {
  for (var start = 0; start + needle.length <= haystack.length; start++) {
    var i = 0;
    while (i < needle.length && haystack[start + i] == needle[i]) {
      i++;
    }
    if (i == needle.length) return true;
  }
  return false;
}

void main() {
  group('wallet transfer secret', () {
    test('encodes to one exact, compact form', () {
      expect(
        utf8.decode(_secret().encode()),
        '{"v":1,"name":"Main wallet","type":"hd","seed":"$_phrase",'
        '"phraseConfirmed":true}',
      );
      expect(
        utf8.decode(
          _secret(
            type: TransferWalletType.legacy,
            phraseConfirmed: false,
          ).encode(),
        ),
        contains('"type":"legacy","seed":"$_phrase","phraseConfirmed":false}'),
      );
    });

    test('round-trips every wallet type and flag', () {
      for (final type in TransferWalletType.values) {
        for (final confirmed in [true, false]) {
          final secret = _secret(type: type, phraseConfirmed: confirmed);
          final decoded = WalletTransferSecret.decode(secret.encode());
          expect(decoded.walletName, secret.walletName);
          expect(decoded.type, type);
          expect(decoded.seed, secret.seed);
          expect(decoded.phraseConfirmed, confirmed);
        }
      }
    });

    test('keeps the seed exactly as typed, byte for byte', () {
      // Nothing here needs JSON escaping, so the seed's own UTF-8 bytes
      // must appear unchanged in the encoding.
      for (final seed in [
        '  Abandon  ABANDON about ',
        'é then é',
        'ﬁligree ＷＩＤＥ zero​width',
        '漢字 🦊 Ünïcödé',
      ]) {
        final secret = _secret(seed: seed, type: TransferWalletType.legacy);
        final encoded = secret.encode();
        expect(_containsRun(encoded, utf8.encode(seed)), isTrue, reason: seed);
        expect(WalletTransferSecret.decode(encoded).seed.codeUnits, [
          ...seed.codeUnits,
        ]);
      }
      // Escaped characters come back as the same code units.
      for (final seed in [
        'tab\tnewline\nreturn\r',
        '"quoted" and back\\slash',
        'nul \u0000 and bell \u0007',
        'a lone \ud800 surrogate',
      ]) {
        final secret = _secret(seed: seed, type: TransferWalletType.legacy);
        expect(WalletTransferSecret.decode(secret.encode()).seed.codeUnits, [
          ...seed.codeUnits,
        ]);
      }
      expect(
        WalletTransferSecret.decode(_secret(seed: 'é').encode()).seed,
        isNot('é'),
      );
    });

    test('maps wallet types, and none for wallets without a seed', () {
      expect(
        TransferWalletType.fromWalletType(WalletType.hdwallet),
        TransferWalletType.hd,
      );
      expect(
        TransferWalletType.fromWalletType(WalletType.iguana),
        TransferWalletType.legacy,
      );
      for (final type in [
        WalletType.trezor,
        WalletType.metamask,
        WalletType.keplr,
      ]) {
        expect(TransferWalletType.fromWalletType(type), isNull);
      }
      for (final type in TransferWalletType.values) {
        expect(TransferWalletType.fromWalletType(type.walletType), type);
      }
    });

    test('refuses extra, missing or renamed keys', () {
      expect(() => _decode({..._json(), 'extra': 1}), _invalid);
      expect(() => _decode({..._json(), 'seed2': _phrase}), _invalid);
      for (final key in _json().keys) {
        expect(() => _decode(_json()..remove(key)), _invalid, reason: key);
        expect(
          () => _decode(
            _json()
              ..remove(key)
              ..['${key}X'] = _json()[key],
          ),
          _invalid,
          reason: key,
        );
      }
    });

    test('refuses another version', () {
      for (final version in [
        0,
        2,
        -1,
        1.5,
        '1',
        null,
        true,
        <int>[1],
      ]) {
        expect(
          () => _decode({..._json(), 'v': version}),
          _invalid,
          reason: '$version',
        );
      }
    });

    test('refuses an unknown wallet type', () {
      for (final type in [
        'HD',
        'Legacy',
        'hdwallet',
        'iguana',
        'trezor',
        '',
        1,
        null,
        true,
      ]) {
        expect(
          () => _decode({..._json(), 'type': type}),
          _invalid,
          reason: '$type',
        );
      }
    });

    test('refuses fields of the wrong type', () {
      for (final field in <Map<String, Object?>>[
        {'name': 1},
        {'name': null},
        {
          'name': <String>['Main wallet'],
        },
        {'seed': 1},
        {'seed': null},
        {
          'seed': <String>[_phrase],
        },
        {'phraseConfirmed': 'true'},
        {'phraseConfirmed': 1},
        {'phraseConfirmed': null},
      ]) {
        expect(
          () => _decode({..._json(), ...field}),
          _invalid,
          reason: '$field',
        );
      }
    });

    test('refuses anything but a JSON object in UTF-8', () {
      for (final bytes in [
        <int>[],
        utf8.encode('[]'),
        utf8.encode('"$_phrase"'),
        utf8.encode('1'),
        utf8.encode('null'),
        utf8.encode('{"v":1,"seed":"$_phrase"'),
        [0xc0, 0xaf],
        [0xff, 0xfe, 0x7b, 0x7d],
      ]) {
        expect(
          () => WalletTransferSecret.decode(bytes),
          _invalid,
          reason: '$bytes',
        );
      }
    });

    test('refuses empty and oversized names and seeds, at the limits', () {
      expect(_secret(name: 'n' * 64).walletName.length, 64);
      expect(_secret(seed: 'a' * 1024).seed.length, 1024);
      // The seed limit counts UTF-8 bytes, not characters: 341 × 3 + 1.
      expect(_secret(seed: '${'€' * 341}a').seed.length, 342);
      for (final build in [
        () => _secret(name: ''),
        () => _secret(name: 'n' * 65),
        () => _secret(seed: ''),
        () => _secret(seed: 'a' * 1025),
        () => _secret(seed: '€' * 342),
      ]) {
        expect(build, _invalid);
      }
      expect(() => _decode({..._json(), 'name': 'n' * 65}), _invalid);
      expect(() => _decode({..._json(), 'name': ''}), _invalid);
      expect(() => _decode({..._json(), 'seed': 'a' * 1025}), _invalid);
      expect(() => _decode({..._json(), 'seed': ''}), _invalid);
    });

    test('refuses a secret too large to seal in one move code', () {
      // 700 quotes are 700 seed bytes but 1,400 once escaped, plus the keys.
      expect(() => _secret(seed: '"' * 700), _invalid);
      expect(
        _secret(seed: '"' * 600).encode().length,
        lessThanOrEqualTo(WalletTransferSecret.maxEncodedBytes),
      );
    });

    test('accepts only the exact encoding it writes', () {
      final canonical = utf8.decode(_secret().encode());
      for (final variant in [
        canonical.replaceFirst('"v":1', '"v":1.0'),
        ' $canonical',
        '$canonical\n',
        '﻿$canonical',
        canonical.replaceFirst('{', '{"name":"Other",'),
        canonical.replaceFirst(',', ', '),
      ]) {
        expect(
          () => WalletTransferSecret.decode(utf8.encode(variant)),
          _invalid,
          reason: variant,
        );
      }
      expect(WalletTransferSecret.decode(utf8.encode(canonical)).seed, _phrase);
    });

    test('never shows its seed or its name', () {
      final secret = _secret();
      expect(secret.toString(), 'WalletTransferSecret(hd, <redacted>)');
      expect(secret.toString(), isNot(contains('abandon')));
      expect(secret.toString(), isNot(contains('Main wallet')));
      expect(
        () => _decode({..._json(), 'extra': _phrase}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'text',
            isNot(contains('Main wallet')),
          ),
        ),
      );
    });
  });
}
