part of 'passkey_backup_record_test.dart';

/// The fixed vector, computed outside Dart with Node's OpenSSL-backed
/// `crypto` (hkdfSync, aes-256-gcm, sha256 HMAC) from the inputs below.
const _vector =
    '{"kind":"gleec.wallet.passkey-backup","v":1,'
    '"id":"CzBVep_E6Q4zWH2ix-wRNg","rpId":"backup.example.net",'
    '"created":"2026-11-18T22:53:07Z",'
    '"credentialId":"HyAhIiMkJSYnKCkqKywtLg",'
    '"userHandle":"Pj9AQUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVpbXF0",'
    '"backupEligible":true,"backupState":true,'
    '"aaguid":"ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4",'
    '"transports":["hybrid","internal"],'
    '"wrap":"-yBFao-02f4jSG2SiIYZ0rpDN-28vpSi6c2TIRGGpc0CvdoUMR6xhOZoF-OjM4xX'
    'NdZcqyPOjkVkFcTk",'
    '"commit":"YEqJHV0zdCqfxehVnQa0jCUgFuN5tvycBhkQEF_VMxw",'
    '"seed":"t9wBJktwlbrfBClONEXskxXY0rbOcfiPgrIUpQ-RKUWsuwNkB7kWbksntkojNOcu'
    '4m6YSU94v5LVk2e0sLj2lKJqAQyIZ2mrfc56zkfl4HFqDZdBkoyLplm337SJqAHIbx4VtM6Y'
    'PTrh_PsbQte6-76l1DK7lKKwmsW2UsR5r_jWNAlBwTbOgEzJAHKPVVXhHKvFBdpYdcBXWduV'
    'z63cc0i0ESaHE6ZSpUqRZiyUGH2n3yHVSaA7NU7uC5CXKg"}';
const _vectorKek =
    'c43e5c2a2706f678ce5ab9bc0499ccfc246712da2c49b12eda1b788b40b7fac3';

/// The vector's random draws: byte i is (i * 37 + 11) & 0xff, taken as the
/// id, the data key, then the two nonces.
final class _SequenceRandom implements Random {
  int _next = 0;

  static Uint8List bytes(int start, int end) => Uint8List.fromList([
    for (var i = start; i < end; i++) (i * 37 + 11) & 0xff,
  ]);

  @override
  int nextInt(int max) => ((_next++ * 37 + 11) & 0xff) % max;

  @override
  bool nextBool() => nextInt(2) == 1;

  @override
  double nextDouble() => nextInt(256) / 256;
}

String _hex(List<int> bytes) =>
    [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

Uint8List _unhex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// RFC 5869 over package:crypto, apart from the implementation's HMac.
List<int> _hkdf(List<int> ikm, List<int> salt, List<int> info) {
  final prk = Hmac(sha256, salt).convert(ikm).bytes;
  return Hmac(sha256, prk).convert([...info, 1]).bytes;
}

/// AES-256-GCM from the AES block function alone (NIST SP 800-38D): the
/// counter mode and GHASH are written out here, over big integers.
Uint8List _gcm(List<int> key, List<int> nonce, List<int> aad, List<int> data) {
  final aes = AESEngine()..init(true, KeyParameter(Uint8List.fromList(key)));
  Uint8List block(List<int> input) {
    final out = Uint8List(16);
    aes.processBlock(Uint8List.fromList(input), 0, out, 0);
    return out;
  }

  BigInt number(List<int> bytes) =>
      bytes.fold(BigInt.zero, (value, byte) => value << 8 | BigInt.from(byte));
  final h = number(block(List.filled(16, 0)));
  final r = BigInt.from(0xe1) << 120;
  // Multiplication in GF(2^128) with GCM's reflected bit order.
  BigInt timesH(BigInt x) {
    var z = BigInt.zero;
    var v = h;
    for (var i = 127; i >= 0; i--) {
      if ((x >> i).isOdd) z ^= v;
      v = v.isOdd ? v >> 1 ^ r : v >> 1;
    }
    return z;
  }

  var hash = BigInt.zero;
  void absorb(List<int> bytes) {
    for (var i = 0; i < bytes.length; i += 16) {
      final chunk = bytes.sublist(i, min(i + 16, bytes.length));
      hash = timesH(
        hash ^ number([...chunk, ...List.filled(16 - chunk.length, 0)]),
      );
    }
  }

  List<int> counter(int n) => [...nonce, 0, 0, n >> 8, n & 0xff];
  final out = <int>[];
  for (var i = 0; i < data.length; i += 16) {
    final pad = block(counter(i ~/ 16 + 2));
    for (var j = i; j < min(i + 16, data.length); j++) {
      out.add(data[j] ^ pad[j - i]);
    }
  }
  absorb(aad);
  absorb(out);
  hash = timesH(
    hash ^ (BigInt.from(aad.length * 8) << 64 | BigInt.from(out.length * 8)),
  );
  final tag = number(block(counter(1))) ^ hash;
  return Uint8List.fromList([
    ...nonce,
    ...out,
    for (var shift = 120; shift >= 0; shift -= 8)
      (tag >> shift & BigInt.from(0xff)).toInt(),
  ]);
}

/// The plaintext of nonce ‖ ciphertext ‖ tag, after checking the tag by
/// sealing it again.
Uint8List _gcmOpen(List<int> key, Uint8List sealed, List<int> aad) {
  final nonce = sealed.sublist(0, 12);
  final body = sealed.sublist(12, sealed.length - 16);
  // Counter mode is its own inverse; the tag of this pass is discarded.
  final plain = _gcm(key, nonce, aad, body).sublist(12, 12 + body.length);
  expect(_gcm(key, nonce, aad, plain), sealed, reason: 'GCM tag');
  return plain;
}

const _kekInfo = 'gleec.wallet.passkey-backup.v1/kek';
const _commitLabel = 'gleec.wallet.passkey-backup.v1/commit';

List<int> _header(Map<String, Object?> json) => utf8.encode(
  jsonEncode([
    json['kind'],
    json['v'],
    json['id'],
    json['rpId'],
    json['created'],
    json['credentialId'],
    json['userHandle'],
    json['backupEligible'],
    json['backupState'],
    json['aaguid'] ?? '',
    json['transports'],
  ]),
);

/// A record built by the test's own HKDF, HMAC and GCM from [header] fields
/// and the vector's random draws, around any [plaintext].
String _independentRecord(Map<String, Object?> header, List<int> plaintext) {
  final id = header['id']! as String;
  final aad = _header(header);
  final dek = _SequenceRandom.bytes(16, 48);
  final kek = _hkdf(_prf, utf8.encode(id), utf8.encode(_kekInfo));
  final commit = Hmac(sha256, dek).convert(utf8.encode('$_commitLabel$id'));
  return jsonEncode({
    ...header,
    'wrap': _b64(_gcm(kek, _SequenceRandom.bytes(48, 60), aad, dek)),
    'commit': _b64(commit.bytes),
    'seed': _b64(_gcm(dek, _SequenceRandom.bytes(60, 72), aad, plaintext)),
  });
}

void _vectorTests() {
  test('the test GCM and HKDF match their published vectors', () {
    // GCM specification (McGrew and Viega), test case 16.
    final sealed = _gcm(
      _unhex(
        'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308',
      ),
      _unhex('cafebabefacedbaddecaf888'),
      _unhex('feedfacedeadbeeffeedfacedeadbeefabaddad2'),
      _unhex(
        'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
        '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39',
      ),
    );
    expect(
      _hex(sealed.sublist(12)),
      '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
      '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662'
      '76fc6ece0f4e1768cddf8853bb2d551b',
    );
    // RFC 5869, test case 1, first block.
    expect(
      _hex(
        _hkdf(
          List.filled(22, 0x0b),
          _unhex('000102030405060708090a0b0c'),
          _unhex('f0f1f2f3f4f5f6f7f8f9'),
        ),
      ),
      '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf',
    );
  });

  test('seals the fixed vector exactly', () {
    final record = _seal(
      created: DateTime.utc(2026, 11, 18, 22, 53, 7, 123, 456),
      random: _SequenceRandom(),
    );
    expect(record.encode(), _vector);
    final json = jsonDecode(_vector) as Map<String, Object?>;
    final id = json['id']! as String;
    expect(id, _b64(_SequenceRandom.bytes(0, 16)));
    expect(
      _hex(_hkdf(_prf, utf8.encode(id), utf8.encode(_kekInfo))),
      _vectorKek,
    );
    final header = {...json}
      ..removeWhere((key, _) => _sealedFields.contains(key));
    expect(_independentRecord(header, _secret().encode()), _vector);
  });

  test('opens what an independent sealer made, and only a wallet', () {
    final header = (jsonDecode(_vector) as Map<String, Object?>)
      ..removeWhere((key, _) => _sealedFields.contains(key));
    PasskeyBackupRecord decode(List<int> plaintext) =>
        PasskeyBackupRecord.decode(
          _independentRecord(header, plaintext),
          expectedRpId: _rp,
        );
    expect(decode(_secret().encode()).open(_prf).seed, _phrase);
    for (final plaintext in [
      utf8.encode('{"v":1}'),
      utf8.encode(
        jsonEncode({...jsonDecode(utf8.decode(_secret().encode())), 'v': 2}),
      ),
      utf8.encode(
        jsonEncode({
          ...jsonDecode(utf8.decode(_secret().encode())),
          'name': '',
        }),
      ),
      [0xff, 0xfe],
      [0x20],
    ]) {
      expect(
        () => decode(plaintext).open(_prf),
        _fails(PasskeyBackupFailure.damaged),
        reason: utf8.decode(plaintext, allowMalformed: true),
      );
    }
  });

  test('a record opens with an independent HKDF, HMAC and GCM', () {
    final json = _json(_seal());
    final id = json['id']! as String;
    final aad = _header(json);
    final kek = _hkdf(_prf, utf8.encode(id), utf8.encode(_kekInfo));
    final dek = _gcmOpen(kek, _unb64(json['wrap']), aad);
    expect(
      Hmac(sha256, dek).convert(utf8.encode('$_commitLabel$id')).bytes,
      _unb64(json['commit']),
    );
    expect(_gcmOpen(dek, _unb64(json['seed']), aad), _secret().encode());
  });
}

const _sealedFields = {'wrap', 'commit', 'seed'};
