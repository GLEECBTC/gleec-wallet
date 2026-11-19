// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member
part of 'passkey_registration_test.dart';

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// Decoded, or refused as a [FormatException]: never any other error.
bool _decodes(Uint8List bytes) {
  try {
    passkeyCborDecode(bytes);
    return true;
  } on FormatException {
    return false;
  }
}

void _cborReaderTests() {
  test('decodes the subset registrations use', () {
    final cases = <String, Object?>{
      '00': 0,
      '17': 23,
      '1818': 24,
      '18ff': 255,
      '190100': 256,
      '1a00010000': 65536,
      '1b001fffffffffffff': 0x1fffffffffffff,
      // Longer than needed is still well-formed.
      '1801': 1,
      '20': -1,
      '3863': -100,
      '3b001ffffffffffffe': -0x1fffffffffffff,
      '40': Uint8List(0),
      '4401020304': Uint8List.fromList([1, 2, 3, 4]),
      '60': '',
      '6449455446': 'IETF',
      '62c3bc': 'ü',
      '80': <Object?>[],
      '83010203': [1, 2, 3],
      'a0': <Object, Object?>{},
      'a201020304': {1: 2, 3: 4},
      'a26161016162820203': {
        'a': 1,
        'b': [2, 3],
      },
      'f4': false,
      'f5': true,
      'f6': null,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(passkeyCborDecode(_hex(key)), value, reason: key);
    }
    expect(passkeyCborDecode(cbor(registrationCoseKey())), {
      1: 2,
      3: -7,
      -1: 1,
      -2: Uint8List(32)..fillRange(0, 32, 7),
      -3: Uint8List(32)..fillRange(0, 32, 9),
    });
  });

  test('refuses what registrations never contain', () {
    final cases = <String, String>{
      'no input': '',
      'indefinite bytes': '5f4101ff',
      'indefinite text': '7f6161ff',
      'indefinite array': '9f01ff',
      'indefinite map': 'bf0102ff',
      'a lone break': 'ff',
      'a tag': 'c11a514b67b0',
      'a half float': 'f93c00',
      'a single float': 'fa47c35000',
      'a double float': 'fb3ff199999999999a',
      'undefined': 'f7',
      'a small simple value': 'f0',
      'a one-byte simple value': 'f820',
      'reserved additional info': '1c',
      'reserved bytes info': '5d',
      'an integer past 2^53': '1b0020000000000000',
      'a negative past -2^53': '3b0020000000000000',
      'bytes longer than the input': '5a0001000001',
      'a huge byte count': '5bffffffffffffffff',
      'more elements than bytes': '9a000f424001',
      'more entries than bytes': 'ba7fffffff0102',
      'a cut argument': '1a0001',
      'a bad UTF-8 continuation': '62c328',
      'a stray UTF-8 byte': '61ff',
      'an overlong UTF-8 slash': '62c0af',
      'an encoded surrogate': '63eda080',
      'a repeated integer key': 'a201020103',
      'a repeated text key': 'a2616101616102',
      'a byte-string key': 'a14001',
      'an array key': 'a18001',
      'a boolean key': 'a1f501',
      'a null key': 'a1f601',
      'trailing bytes': '0000',
      'a trailing map': 'a0a0',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(
        () => passkeyCborDecode(_hex(value)),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('nests containers at most eight deep', () {
    Uint8List arrays(int depth) => _hex('${'81' * (depth - 1)}80');
    Uint8List maps(int depth) => _hex('${'a101' * (depth - 1)}a0');
    expect(passkeyCborDecode(arrays(8)), isA<List<Object?>>());
    expect(passkeyCborDecode(maps(8)), isA<Map<Object, Object?>>());
    expect(() => passkeyCborDecode(arrays(9)), throwsFormatException);
    expect(() => passkeyCborDecode(maps(9)), throwsFormatException);
    expect(
      () => passkeyCborDecode(_hex('${'81' * 2000}80')),
      throwsFormatException,
    );
  });

  test('refuses every truncation of a valid item', () {
    final item = cbor({
      'fmt': 'packed',
      'attStmt': {
        'alg': -7,
        'sig': bytesOf(6, 70),
        'x5c': [bytesOf(7, 300)],
      },
      'authData': registrationAuthData(credentialId: _id),
      'n': [0, 23, 24, 255, 256, 65535, 65536, 0xffffffff, 0x100000000, -1],
      'b': [true, false, null],
    });
    expect(_decodes(item), isTrue);
    for (var length = 0; length < item.length; length++) {
      expect(
        _decodes(Uint8List.sublistView(item, 0, length)),
        isFalse,
        reason: 'cut at $length',
      );
    }
  });

  test('random input decodes or fails as malformed, nothing else', () {
    final random = Random(1);
    const heads = [0x9f, 0xbf, 0x5b, 0x7b, 0x9b, 0xbb, 0x84, 0xa4, 0xd8];
    var decoded = 0;
    for (var i = 0; i < 3000; i++) {
      final bytes = Uint8List.fromList([
        if (i.isEven) heads[random.nextInt(heads.length)],
        for (var j = random.nextInt(48); j > 0; j--) random.nextInt(256),
      ]);
      if (_decodes(bytes)) decoded++;
    }
    expect(decoded, greaterThan(0));
  });
}
