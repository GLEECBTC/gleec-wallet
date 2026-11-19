part of 'wallet_move_protocol_test.dart';

const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

String _withField(String code, int index, String value) {
  final fields = code.split('.');
  fields[index] = value;
  return fields.join('.');
}

String _withBytes(String code, int index, List<int> bytes) =>
    _withField(code, index, b64(bytes));

/// Sets the lowest bit of the last character, which only carries padding
/// when the field's byte count is not a multiple of three.
String _nonCanonicalLast(String text) {
  final value = _alphabet.indexOf(text[text.length - 1]);
  return text.substring(0, text.length - 1) + _alphabet[value | 1];
}

/// A compressed key whose x has no point on P-256, per the reference curve.
Uint8List _offCurveKey() {
  for (var x = 1; ; x++) {
    final encoded = Uint8List(33)
      ..[0] = 2
      ..[32] = x;
    try {
      RefP256.decompress(encoded);
    } on ArgumentError {
      return encoded;
    }
  }
}

void _refusalCases() {
  group('refuses', () {
    late WalletMoveOffer offer;
    late String reply;

    setUp(() {
      offer = WalletMoveProtocolV1().createOffer();
      reply = _seal(offer.code);
    });

    tearDown(() => offer.dispose());

    void sealFails(String code, WalletMoveFailure failure) =>
        expect(() => _seal(code), moveFails(failure), reason: code);

    void openFails(String code, WalletMoveFailure failure) =>
        expect(() => offer.open(code), moveFails(failure), reason: code);

    test('anything that is not a move code', () {
      for (final code in [
        '',
        'G',
        'GLEECMOVE',
        'GLEECMOVEO.AAAA',
        'GLEECMOVE٣O.AAAA',
        'gleecmove1o.${offer.code.substring(12)}',
        ' ${offer.code}',
        'bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq',
        'https://dex.gleec.com/',
      ]) {
        sealFails(code, WalletMoveFailure.notAMoveCode);
        openFails(code, WalletMoveFailure.notAMoveCode);
      }
    });

    test('a code from another version, before its size or fields', () {
      for (final code in [
        offer.code.replaceFirst('MOVE1', 'MOVE2'),
        reply.replaceFirst('MOVE1', 'MOVE2'),
        'GLEECMOVE0O.AAAA',
        'GLEECMOVE01O.AAAA',
        'GLEECMOVE10R.AAAA',
        'GLEECMOVE2',
        'GLEECMOVE2X.${'A' * 5000}',
      ]) {
        sealFails(code, WalletMoveFailure.unsupportedVersion);
        openFails(code, WalletMoveFailure.unsupportedVersion);
      }
    });

    test('a code meant for the other device', () {
      sealFails(reply, WalletMoveFailure.wrongStep);
      sealFails('GLEECMOVE1R', WalletMoveFailure.wrongStep);
      openFails(offer.code, WalletMoveFailure.wrongStep);
      openFails(
        WalletMoveProtocolV1().createOffer().code,
        WalletMoveFailure.wrongStep,
      );
      openFails('GLEECMOVE1O', WalletMoveFailure.wrongStep);
    });

    test('an offer with a damaged shape', () {
      final [_, key, session] = offer.code.split('.');
      for (final code in [
        'GLEECMOVE1',
        'GLEECMOVE1O',
        'GLEECMOVE1X.$key.$session',
        'GLEECMOVE1o.$key.$session',
        'GLEECMOVE1O$key.$session',
        'GLEECMOVE1O.$key',
        'GLEECMOVE1O.$key.$session.AAAA',
        'GLEECMOVE1O.$key.$session.',
        'GLEECMOVE1O..$session',
        'GLEECMOVE1O.$session.$key',
        'GLEECMOVE1O.$key.$session=',
        'GLEECMOVE1O.+${key.substring(1)}.$session',
        'GLEECMOVE1O.$key./${session.substring(1)}',
        'GLEECMOVE1O.$key .$session',
        '${offer.code}\n',
        'GLEECMOVE1O.$key.${_nonCanonicalLast(session)}',
        'GLEECMOVE1O.$key.${session.substring(1)}',
        'GLEECMOVE1O.$key.${session}AA',
        'GLEECMOVE1O.${key.substring(1)}.$session',
        'GLEECMOVE1O.${key}AAAA.$session',
        '${offer.code}${'A' * (2049 - offer.code.length)}',
      ]) {
        sealFails(code, WalletMoveFailure.damaged);
      }
    });

    test('a reply with a damaged shape', () {
      final [_, session, key, boxText] = reply.split('.');
      final box = unb64(boxText);
      expect(box.length % 3, isNot(0), reason: 'the last character pads');
      for (final code in [
        'GLEECMOVE1R',
        'GLEECMOVE1R.$session.$key',
        '$reply.AAAA',
        '$reply.',
        'GLEECMOVE1R.$session..$boxText',
        'GLEECMOVE1R.$key.$session.$boxText',
        '$reply=',
        '$reply\n',
        'GLEECMOVE1R.${_nonCanonicalLast(session)}.$key.$boxText',
        'GLEECMOVE1R.$session.$key.${_nonCanonicalLast(boxText)}',
        _withBytes(reply, 3, box.sublist(0, 28)),
        _withBytes(reply, 3, box.sublist(0, 12)),
        '$reply${'A' * (2049 - reply.length)}',
      ]) {
        openFails(code, WalletMoveFailure.damaged);
      }
    });

    test('a public key that is not a point on P-256', () {
      final x = unb64(offer.code.split('.')[1]).sublist(1);
      final prime = hexBytes(
        'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
      );
      for (final key in [
        [0x04, ...x],
        [0x00, ...x],
        [0x01, ...x],
        [0x05, ...x],
        [0x02, ...prime],
        [0x03, ...List.filled(32, 0xff)],
        _offCurveKey(),
      ]) {
        sealFails(_withBytes(offer.code, 1, key), WalletMoveFailure.damaged);
        openFails(_withBytes(reply, 2, key), WalletMoveFailure.damaged);
      }
    });

    test('a reply sealed for any other offer', () {
      final other = WalletMoveProtocolV1().createOffer();
      final [_, ourKey, ourSession] = offer.code.split('.');
      final [_, otherKey, otherSession] = other.code.split('.');
      final otherReply = _seal(other.code);
      for (final code in [
        otherReply,
        _withField(otherReply, 1, ourSession),
        _seal('GLEECMOVE1O.$ourKey.$otherSession'),
        _seal('GLEECMOVE1O.$otherKey.$ourSession'),
        _withBytes(reply, 3, unb64(reply.split('.')[3]).sublist(0, 29)),
      ]) {
        openFails(code, WalletMoveFailure.notForThisDevice);
      }
      expectSameSecret(offer.open(reply), testSecret());
    });

    test('the other point with the same x, on either side', () {
      // Negating a key keeps the ECDH x-coordinate; only the binding of
      // both keys into the key and the tag tells them apart.
      final pubO = unb64(reply.split('.')[2])..[0] ^= 1;
      openFails(_withBytes(reply, 2, pubO), WalletMoveFailure.notForThisDevice);
      final pubN = unb64(offer.code.split('.')[1])..[0] ^= 1;
      openFails(
        _seal(_withBytes(offer.code, 1, pubN)),
        WalletMoveFailure.notForThisDevice,
      );
      expectSameSecret(offer.open(reply), testSecret());
    });

    test('a changed byte anywhere in a reply', () {
      final fields = reply.split('.');
      for (var field = 1; field < fields.length; field++) {
        final bytes = unb64(fields[field]);
        for (var i = 0; i < bytes.length; i++) {
          final altered = Uint8List.fromList(bytes)..[i] ^= 0x01;
          expect(
            () => offer.open(_withBytes(reply, field, altered)),
            throwsA(
              isA<WalletMoveException>().having(
                (e) => e.failure,
                'failure',
                field == 2
                    ? anyOf(
                        WalletMoveFailure.damaged,
                        WalletMoveFailure.notForThisDevice,
                      )
                    : WalletMoveFailure.notForThisDevice,
              ),
            ),
            reason: 'field $field, byte $i',
          );
        }
      }
      expectSameSecret(offer.open(reply), testSecret());
    });

    test(
      'a changed byte anywhere in an offer never reaches the new device',
      () {
        final fields = offer.code.split('.');
        for (var field = 1; field < fields.length; field++) {
          final bytes = unb64(fields[field]);
          for (var i = 0; i < bytes.length; i++) {
            final altered = Uint8List.fromList(bytes)..[i] ^= 0x01;
            final String sealed;
            try {
              sealed = _seal(_withBytes(offer.code, field, altered));
            } on WalletMoveException catch (error) {
              // Only a key moved off the curve is caught this early.
              expect(error.failure, WalletMoveFailure.damaged);
              expect(field, 1);
              continue;
            }
            openFails(sealed, WalletMoveFailure.notForThisDevice);
          }
        }
        expectSameSecret(offer.open(reply), testSecret());
      },
    );

    test('a changed tag or separator', () {
      for (final code in [offer.code, reply]) {
        final positions = [
          for (var i = 0; i < code.length; i++)
            if (i < 12 || code[i] == '.') i,
        ];
        for (final i in positions) {
          for (final replacement in ['.', 'A', '1', '2', 'O', 'R', ' ']) {
            if (code[i] == replacement) continue;
            final altered = code.replaceRange(i, i + 1, replacement);
            expect(
              () => offer.open(altered),
              throwsA(isA<WalletMoveException>()),
              reason: altered,
            );
            expect(
              () => _seal(altered),
              throwsA(isA<WalletMoveException>()),
              reason: altered,
            );
          }
        }
      }
    });

    test('only a WalletMoveException ever escapes', () {
      final random = Random(3);
      const chars = '$_alphabet.=+/% \n';
      for (var round = 0; round < 200; round++) {
        final base = (round.isEven ? offer.code : reply).split('');
        for (var edits = random.nextInt(4); edits >= 0; edits--) {
          base[random.nextInt(base.length)] =
              chars[random.nextInt(chars.length)];
        }
        final cut = random.nextInt(4) == 0
            ? random.nextInt(base.length)
            : base.length;
        final text = base.take(cut).join();
        for (final attempt in [() => offer.open(text), () => _seal(text)]) {
          try {
            attempt();
          } on WalletMoveException {
            // Refused, as it should be.
          }
        }
      }
    });
  });
}
