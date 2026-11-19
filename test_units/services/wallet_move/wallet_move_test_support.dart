import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show AESEngine, KeyParameter;
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

/// The BIP-39 test phrase: public test data, never a real wallet.
const testPhrase =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon about';

WalletTransferSecret testSecret({
  String name = 'Main wallet',
  TransferWalletType type = TransferWalletType.hd,
  String seed = testPhrase,
  bool phraseConfirmed = true,
}) => WalletTransferSecret(
  walletName: name,
  type: type,
  seed: seed,
  phraseConfirmed: phraseConfirmed,
);

Matcher moveFails(WalletMoveFailure failure) => throwsA(
  isA<WalletMoveException>().having((e) => e.failure, 'failure', failure),
);

void expectSameSecret(WalletTransferSecret actual, WalletTransferSecret want) {
  expect(actual.walletName, want.walletName);
  expect(actual.type, want.type);
  expect(actual.seed.codeUnits, want.seed.codeUnits);
  expect(actual.phraseConfirmed, want.phraseConfirmed);
}

/// Hands out exactly the given bytes, so a test knows every key, session id
/// and nonce the protocol draws, and in which order.
class ScriptedRandom implements Random {
  ScriptedRandom(Iterable<int> bytes) : _bytes = List.of(bytes);

  final List<int> _bytes;
  var _next = 0;

  int get remaining => _bytes.length - _next;

  @override
  int nextInt(int max) {
    if (max != 256) throw UnsupportedError('Only bytes are scripted');
    if (_next == _bytes.length) throw StateError('Script exhausted');
    return _bytes[_next++];
  }

  @override
  bool nextBool() => throw UnsupportedError('Only bytes are scripted');

  @override
  double nextDouble() => throw UnsupportedError('Only bytes are scripted');
}

Uint8List hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List unb64(String text) => base64Url.decode(base64Url.normalize(text));

final moveLabel = utf8.encode('gleec.wallet.move.v1');

typedef RefPoint = (BigInt, BigInt);

/// P-256 in affine coordinates over plain BigInt (FIPS 186-4 D.1.2.3): slow,
/// and sharing no code with pointycastle's curve arithmetic.
abstract final class RefP256 {
  static final p = _int(
    'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
  );
  static final n = _int(
    'ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551',
  );
  static final b = _int(
    '5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b',
  );
  static final RefPoint g = (
    _int('6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296'),
    _int('4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5'),
  );
  static final _three = BigInt.from(3);

  static BigInt _int(String hex) => BigInt.parse(hex, radix: 16);

  static BigInt _inverse(BigInt value) => (value % p).modInverse(p);

  /// Null is the point at infinity.
  static RefPoint? add(RefPoint? s, RefPoint? t) {
    if (s == null) return t;
    if (t == null) return s;
    final (x1, y1) = s;
    final (x2, y2) = t;
    final BigInt slope;
    if (x1 == x2) {
      if ((y1 + y2) % p == BigInt.zero) return null;
      // a = -3, so the tangent's slope is (3x² - 3) / 2y.
      slope = (_three * x1 * x1 - _three) * _inverse(BigInt.two * y1) % p;
    } else {
      slope = (y2 - y1) * _inverse(x2 - x1) % p;
    }
    final x3 = (slope * slope - x1 - x2) % p;
    return (x3, (slope * (x1 - x3) - y1) % p);
  }

  static RefPoint? multiply(BigInt k, RefPoint point) {
    RefPoint? result;
    for (var i = k.bitLength - 1; i >= 0; i--) {
      result = add(result, result);
      if ((k >> i).isOdd) result = add(result, point);
    }
    return result;
  }

  static Uint8List compress(RefPoint point) => Uint8List.fromList([
    point.$2.isOdd ? 3 : 2,
    ...hexBytes(point.$1.toRadixString(16).padLeft(64, '0')),
  ]);

  static RefPoint decompress(List<int> encoded) {
    final x = _int(hexOf(encoded.sublist(1)));
    final rhs = (x * x * x - _three * x + b) % p;
    var y = rhs.modPow((p + BigInt.one) >> 2, p);
    if (y * y % p != rhs) throw ArgumentError('Not on P-256');
    if (y.isOdd != (encoded[0] == 3)) y = p - y;
    return (x, y);
  }

  static Uint8List x(RefPoint point) =>
      hexBytes(point.$1.toRadixString(16).padLeft(64, '0'));
}

/// RFC 5869 over package:crypto rather than pointycastle.
Uint8List refHkdf(List<int> ikm, List<int> salt, List<int> info, int length) {
  final prk = Hmac(sha256, salt).convert(ikm).bytes;
  final okm = <int>[];
  var block = <int>[];
  for (var i = 1; okm.length < length; i++) {
    block = Hmac(sha256, prk).convert([...block, ...info, i]).bytes;
    okm.addAll(block);
  }
  return Uint8List.fromList(okm.sublist(0, length));
}

/// AES-GCM from NIST SP 800-38D over a bare AES block, sharing no code with
/// pointycastle's GCM mode. 96-bit IVs only; returns ciphertext ‖ tag.
Uint8List refGcmSeal(
  List<int> key,
  List<int> iv,
  List<int> aad,
  List<int> plaintext,
) {
  final aes = _RefAes(key);
  final j0 = [...iv, 0, 0, 0, 1];
  final ciphertext = _ctr(aes, j0, plaintext);
  final tag = _ghash(aes.block(Uint8List(16)), aad, ciphertext) ^ aes.block(j0);
  return Uint8List.fromList([...ciphertext, ..._block(tag)]);
}

/// Throws when the tag does not match.
Uint8List refGcmOpen(
  List<int> key,
  List<int> iv,
  List<int> aad,
  List<int> sealed,
) {
  final aes = _RefAes(key);
  final ciphertext = sealed.sublist(0, sealed.length - 16);
  final plaintext = _ctr(aes, [...iv, 0, 0, 0, 1], ciphertext);
  if (hexOf(refGcmSeal(key, iv, aad, plaintext)) != hexOf(sealed)) {
    throw StateError('GCM tag mismatch');
  }
  return plaintext;
}

final class _RefAes {
  _RefAes(List<int> key)
    : _engine = AESEngine()..init(true, KeyParameter(Uint8List.fromList(key)));

  final AESEngine _engine;

  BigInt block(List<int> input) {
    final out = Uint8List(16);
    _engine.processBlock(Uint8List.fromList(input), 0, out, 0);
    return _value(out);
  }
}

Uint8List _ctr(_RefAes aes, List<int> j0, List<int> input) {
  final output = <int>[];
  for (var offset = 0; offset < input.length; offset += 16) {
    final count =
        (_value(j0.sublist(12)).toInt() + offset ~/ 16 + 1) & 0xffffffff;
    final counter = [...j0.sublist(0, 12), ..._block(BigInt.from(count), 4)];
    final stream = _block(aes.block(counter));
    for (var i = offset; i < min(offset + 16, input.length); i++) {
      output.add(input[i] ^ stream[i - offset]);
    }
  }
  return Uint8List.fromList(output);
}

BigInt _ghash(BigInt h, List<int> aad, List<int> ciphertext) {
  var y = BigInt.zero;
  for (final data in [aad, ciphertext]) {
    for (var i = 0; i < data.length; i += 16) {
      final chunk = [...data.sublist(i, min(i + 16, data.length))];
      chunk.addAll(List.filled(16 - chunk.length, 0));
      y = _gfMultiply(y ^ _value(chunk), h);
    }
  }
  final lengths =
      BigInt.from(aad.length * 8) << 64 | BigInt.from(ciphertext.length * 8);
  return _gfMultiply(y ^ lengths, h);
}

/// GF(2^128) in GCM's bit order (SP 800-38D, algorithm 1): bit 0 of a block
/// is the most significant bit of its first byte.
BigInt _gfMultiply(BigInt x, BigInt y) {
  final r = BigInt.from(0xe1) << 120;
  var z = BigInt.zero;
  var v = y;
  for (var i = 127; i >= 0; i--) {
    if ((x >> i).isOdd) z ^= v;
    v = v.isOdd ? (v >> 1) ^ r : v >> 1;
  }
  return z;
}

BigInt _value(List<int> bytes) =>
    bytes.fold(BigInt.zero, (value, byte) => value << 8 | BigInt.from(byte));

Uint8List _block(BigInt value, [int length = 16]) =>
    hexBytes(value.toRadixString(16).padLeft(length * 2, '0'));
