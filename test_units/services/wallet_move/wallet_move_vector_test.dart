import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show AESEngine, KeyParameter;
import 'package:web_dex/services/wallet_move/wallet_move_protocol.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

import 'wallet_move_test_support.dart';

// The v1 vector's inputs, and what Apple CryptoKit computed from them.
final _newScalar = hexBytes(
  'c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721',
);
final _sessionId = hexBytes('0f1e2d3c4b5a69788796a5b4c3d2e1f0');
final _oldScalar = hexBytes(
  '7d7dc5f71eb29ddaf80d6214632eeae03d9058af1fb6d22ed80badb62bc1a534',
);
final _nonce = hexBytes('cafebabefacedbaddecaf888');
const _shared =
    '61e109425a7adbb9d0137091cff10a55550b708d14ad0137b80fa0ec1328394f';
const _aesKey =
    '81cd2e5e24d89193efda8759903ea0afcafec46c059df8eed05588d9cff211b6';
const _offer =
    'GLEECMOVE1O.A2D-1LolWp0xyWHrdMY1bWjASbiSO2H6bOZpYi5g8p-2.'
    'Dx4tPEtaaXiHlqW0w9Lh8A';
const _reply =
    'GLEECMOVE1R.Dx4tPEtaaXiHlqW0w9Lh8A.'
    'A-rSGFkBGeiHaykUb_icphdwxO27-X04zjhe0oHYprIw.'
    'yv66vvrO263eyviIi_aW_H8mx1Bho46tGKOFUVLlL3VNmKH3i03K2oCp-whcEuYkHkp4qZK'
    'XxusnlLZBixbOBX6a4ttIBlYTd19yrCLkvyNlamOp0WVFBFHlIwJvDTkm9FOlZhAc1XNf70'
    '-6KE4ufP28X3CNj1lA2q37jgQqn3cL-zUFY8Xmx2Dj0Ox0ppVjyScuHVjZaEbUe25ErO_R_'
    'Cy1B37t3c9l74XL3EkaTOZybl8rHKJyGQ4c9CvRmh6BxeY';
const _plaintext =
    '{"v":1,"name":"Main wallet","type":"hd","seed":"$testPhrase",'
    '"phraseConfirmed":true}';

BigInt _scalar(List<int> bytes) => BigInt.parse(hexOf(bytes), radix: 16);

/// The old device's half, built from the protocol description alone.
String _refSeal(String offerCode, BigInt scalar, List<int> nonce, List<int> m) {
  final [tag, pubNText, sessionText] = offerCode.split('.');
  expect(tag, 'GLEECMOVE1O');
  final pubN = unb64(pubNText);
  final sessionId = unb64(sessionText);
  final pubO = RefP256.compress(RefP256.multiply(scalar, RefP256.g)!);
  final point = RefP256.multiply(scalar, RefP256.decompress(pubN))!;
  final key = refHkdf(RefP256.x(point), sessionId, [
    ...moveLabel,
    ...pubN,
    ...pubO,
  ], 32);
  final aad = [...moveLabel, ...sessionId, ...pubN, ...pubO];
  final box = refGcmSeal(key, nonce, aad, m);
  return 'GLEECMOVE1R.${b64(sessionId)}.${b64(pubO)}.${b64([...nonce, ...box])}';
}

/// The new device's half: opens [reply] for the offer of [scalar].
Uint8List _refOpen(String reply, BigInt scalar, List<int> sessionId) {
  final [tag, sessionText, pubOText, boxText] = reply.split('.');
  expect(tag, 'GLEECMOVE1R');
  expect(unb64(sessionText), sessionId);
  final pubN = RefP256.compress(RefP256.multiply(scalar, RefP256.g)!);
  final pubO = unb64(pubOText);
  final point = RefP256.multiply(scalar, RefP256.decompress(pubO))!;
  final key = refHkdf(RefP256.x(point), sessionId, [
    ...moveLabel,
    ...pubN,
    ...pubO,
  ], 32);
  final box = unb64(boxText);
  return refGcmOpen(key, box.sublist(0, 12), [
    ...moveLabel,
    ...sessionId,
    ...pubN,
    ...pubO,
  ], box.sublist(12));
}

void main() {
  group('reference primitives against published vectors', () {
    test('P-256 ECDH: NIST CAVS KAS ECC CDH, COUNT 0', () {
      final d = _scalar(
        hexBytes(
          '7d7dc5f71eb29ddaf80d6214632eeae03d9058af1fb6d22ed80badb62bc1a534',
        ),
      );
      final public = RefP256.multiply(d, RefP256.g)!;
      expect(
        hexOf(RefP256.x(public)),
        'ead218590119e8876b29146ff89ca61770c4edbbf97d38ce385ed281d8a6b230',
      );
      expect(
        public.$2.toRadixString(16),
        '28af61281fd35e2fa7002523acc85a429cb06ee6648325389f59edfce1405141',
      );
      final peer = RefP256.decompress(
        hexBytes(
          '02700c48f77f56584c5cc632ca65640db91b6bacce3a4df6b42ce7cc838833d287',
        ),
      );
      expect(
        peer.$2.toRadixString(16),
        'db71e509e3fd9b060ddb20ba5c51dcc5948d46fbf640dfe0441782cab85fa4ac',
      );
      expect(
        hexOf(RefP256.x(RefP256.multiply(d, peer)!)),
        '46fc62106420ff012e54a434fbdd2d25ccc5852060561e68040dd7778997bd7b',
      );
    });

    test('HKDF-SHA256: RFC 5869 A.1', () {
      final okm = refHkdf(
        hexBytes('0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b'),
        hexBytes('000102030405060708090a0b0c'),
        hexBytes('f0f1f2f3f4f5f6f7f8f9'),
        42,
      );
      expect(
        hexOf(okm),
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });

    test('AES-256 block (FIPS-197 C.3) and GCM (spec test case 16)', () {
      final aes = AESEngine()
        ..init(
          true,
          KeyParameter(
            hexBytes(
              '000102030405060708090a0b0c0d0e0f'
              '101112131415161718191a1b1c1d1e1f',
            ),
          ),
        );
      final block = Uint8List(16);
      aes.processBlock(
        hexBytes('00112233445566778899aabbccddeeff'),
        0,
        block,
        0,
      );
      expect(hexOf(block), '8ea2b7ca516745bfeafc49904b496089');

      final key = hexBytes(
        'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308',
      );
      final iv = hexBytes('cafebabefacedbaddecaf888');
      final aad = hexBytes('feedfacedeadbeeffeedfacedeadbeefabaddad2');
      final plaintext = hexBytes(
        'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
        '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
      );
      final sealed = refGcmSeal(key, iv, aad, plaintext);
      expect(
        hexOf(sealed),
        '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
        '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662'
        '76fc6ece0f4e1768cddf8853bb2d551b',
      );
      expect(refGcmOpen(key, iv, aad, sealed), plaintext);
      sealed[sealed.length - 1] ^= 1;
      expect(() => refGcmOpen(key, iv, aad, sealed), throwsStateError);
    });
  });

  group('wallet move v1 vector', () {
    test('both devices produce the CryptoKit vector byte for byte', () {
      final newRandom = ScriptedRandom([..._newScalar, ..._sessionId]);
      final offer = WalletMoveProtocolV1(random: newRandom).createOffer();
      expect(offer.code, _offer);
      expect(newRandom.remaining, 0);

      final oldRandom = ScriptedRandom([..._oldScalar, ..._nonce]);
      final reply = WalletMoveProtocolV1(random: oldRandom)
          .seal(offerCode: offer.code, secret: testSecret());
      expect(reply, _reply);
      expect(oldRandom.remaining, 0);
      expectSameSecret(offer.open(reply), testSecret());
    });

    test('recomputes independently: ECDH, HKDF and GCM', () {
      expect(utf8.decode(testSecret().encode()), _plaintext);
      final pubN = RefP256.compress(
        RefP256.multiply(_scalar(_newScalar), RefP256.g)!,
      );
      final pubO = RefP256.compress(
        RefP256.multiply(_scalar(_oldScalar), RefP256.g)!,
      );
      expect(_offer, 'GLEECMOVE1O.${b64(pubN)}.${b64(_sessionId)}');

      final fromOld = RefP256.multiply(
        _scalar(_oldScalar),
        RefP256.decompress(pubN),
      )!;
      final fromNew = RefP256.multiply(
        _scalar(_newScalar),
        RefP256.decompress(pubO),
      )!;
      expect(hexOf(RefP256.x(fromOld)), _shared);
      expect(hexOf(RefP256.x(fromNew)), _shared);
      final key = refHkdf(hexBytes(_shared), _sessionId, [
        ...moveLabel,
        ...pubN,
        ...pubO,
      ], 32);
      expect(hexOf(key), _aesKey);

      final plaintext = utf8.encode(_plaintext);
      expect(_refSeal(_offer, _scalar(_oldScalar), _nonce, plaintext), _reply);
      expect(_refOpen(_reply, _scalar(_newScalar), _sessionId), plaintext);
    });

    test('a production new device opens a reply the reference sealed', () {
      final secret = testSecret(
        name: 'Ünïcode wallet 🦊',
        type: TransferWalletType.legacy,
        seed: '  My Legacy\tSeed  é ',
        phraseConfirmed: false,
      );
      for (var round = 0; round < 3; round++) {
        final offer = WalletMoveProtocolV1().createOffer();
        final random = Random(round);
        final scalar =
            _scalar(List.generate(32, (_) => random.nextInt(256))) %
                (RefP256.n - BigInt.one) +
            BigInt.one;
        final nonce = List.generate(12, (_) => random.nextInt(256));
        final reply = _refSeal(offer.code, scalar, nonce, secret.encode());
        expectSameSecret(offer.open(reply), secret);
      }
    });

    test('the reference new device opens a production reply', () {
      final secret = testSecret(seed: '$testPhrase ');
      final sessionId = hexBytes('00112233445566778899aabbccddeeff');
      for (final hex in [
        '38f65d6dce47676044d58ce5139582d568f64bb16098d179dbab07741dd5caf5',
        '0000000000000000000000000000000000000000000000000000000000000001',
      ]) {
        final scalar = _scalar(hexBytes(hex));
        final pubN = RefP256.compress(RefP256.multiply(scalar, RefP256.g)!);
        final reply = WalletMoveProtocolV1().seal(
          offerCode: 'GLEECMOVE1O.${b64(pubN)}.${b64(sessionId)}',
          secret: secret,
        );
        expect(_refOpen(reply, scalar, sessionId), secret.encode());
      }
    });

    test('a seeded random gives the same codes every time', () {
      String run(int seed) {
        final offer = WalletMoveProtocolV1(random: Random(seed)).createOffer();
        final reply = WalletMoveProtocolV1(random: Random(seed + 1))
            .seal(offerCode: offer.code, secret: testSecret());
        return '${offer.code} $reply';
      }

      expect(run(7), run(7));
      expect(run(7), isNot(run(9)));
    });

    test('a scalar outside [1, n - 1] is drawn again', () {
      final n = hexBytes(
        'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',
      );
      for (final rejected in [List.filled(32, 0xff), List.filled(32, 0), n]) {
        final random = ScriptedRandom([
          ...rejected,
          ..._newScalar,
          ..._sessionId,
        ]);
        expect(WalletMoveProtocolV1(random: random).createOffer().code, _offer);
        expect(random.remaining, 0);
      }

      // n - 1 is the largest scalar allowed: its public key is -G.
      final top = [...n]..last -= 1;
      final minusG = (RefP256.g.$1, RefP256.p - RefP256.g.$2);
      expect(
        WalletMoveProtocolV1(random: ScriptedRandom([...top, ..._sessionId]))
            .createOffer()
            .code,
        'GLEECMOVE1O.${b64(RefP256.compress(minusG))}.${b64(_sessionId)}',
      );

      // A source that only ever yields zero is broken; it must not hang.
      expect(
        () =>
            WalletMoveProtocolV1(random: ScriptedRandom(List.filled(32 * 8, 0)))
                .createOffer(),
        throwsStateError,
      );
    });
  });
}
