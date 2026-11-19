import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart'
    show Argon2BytesGenerator, Argon2Parameters;
import 'package:web_dex/services/wallet_move/wallet_move_protocol.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

import 'wallet_move_test_support.dart';

part 'wallet_move_refusal_cases.dart';

final _offerShape = RegExp(
  r'^GLEECMOVE1O\.[A-Za-z0-9_-]{44}\.[A-Za-z0-9_-]{22}$',
);
final _replyShape = RegExp(
  r'^GLEECMOVE1R\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{44}\.[A-Za-z0-9_-]+$',
);

String _seal(String offerCode, [WalletTransferSecret? secret]) =>
    WalletMoveProtocolV1().seal(
      offerCode: offerCode,
      secret: secret ?? testSecret(),
    );

void main() {
  group('reply check code', () {
    test('both phones derive the same eight digits from one reply', () async {
      final protocol = WalletMoveProtocolV1();
      final offer = protocol.createOffer();
      final reply = protocol.seal(offerCode: offer.code, secret: testSecret());
      final code = await protocol.checkCode(reply);
      expect(code, matches(RegExp(r'^[0-9]{8}$')));
      // The new phone computes it from the code it scanned.
      expect(await WalletMoveProtocolV1().checkCode(reply), code);
      offer.dispose();
    });

    test(
      'a reply someone else sealed to the same offer shows other digits',
      () async {
        final protocol = WalletMoveProtocolV1();
        final offer = protocol.createOffer();
        final mine = protocol.seal(offerCode: offer.code, secret: testSecret());
        final codes = <String>{await protocol.checkCode(mine)};
        final replies = [
          for (var i = 0; i < 8; i++)
            protocol.seal(
              offerCode: offer.code,
              secret: testSecret(name: 'Main wallet'),
            ),
        ];
        // Their reply opens on the new phone: that is why the digits exist.
        expect(offer.open(replies.first).walletName, 'Main wallet');
        codes.addAll(await Future.wait(replies.map(protocol.checkCode)));
        expect(codes, hasLength(9));
        offer.dispose();
      },
    );

    test('the digits are Argon2id over the reply, not a plain hash', () async {
      final protocol = WalletMoveProtocolV1();
      final offer = protocol.createOffer();
      final reply = protocol.seal(offerCode: offer.code, secret: testSecret());
      final code = await protocol.checkCode(reply);
      // Recomputed here from the reply's fields, independently.
      final fields = reply.split('.');
      final transcript = Uint8List.fromList([
        ...utf8.encode('gleec.wallet.move.v1/check'),
        ...unb64(fields[1]),
        ...unb64(fields[2]),
        ...unb64(fields[3]),
      ]);
      final generator = Argon2BytesGenerator()
        ..init(
          Argon2Parameters(
            Argon2Parameters.ARGON2_id,
            unb64(fields[1]),
            desiredKeyLength: 8,
            iterations: 3,
            memory: 16384,
            lanes: 1,
          ),
        );
      final out = Uint8List(8);
      generator.deriveKey(transcript, 0, out, 0);
      var value = 0;
      for (final byte in out.sublist(0, 5)) {
        value = value * 256 + byte;
      }
      expect(code, (value % 100000000).toString().padLeft(8, '0'));
      offer.dispose();
    });

    test('an offer is checked without sealing anything', () {
      final protocol = WalletMoveProtocolV1();
      final offer = protocol.createOffer();
      protocol.checkOffer(offer.code);
      final reply = protocol.seal(offerCode: offer.code, secret: testSecret());
      expect(
        () => protocol.checkOffer(reply),
        moveFails(WalletMoveFailure.wrongStep),
      );
      expect(
        () => protocol.checkOffer('bitcoin:bc1qexample'),
        moveFails(WalletMoveFailure.notAMoveCode),
      );
      expect(
        () =>
            protocol.checkOffer(offer.code.substring(0, offer.code.length - 2)),
        moveFails(WalletMoveFailure.damaged),
      );
      offer.dispose();
    });

    test('only a well-formed reply has a check code', () {
      final protocol = WalletMoveProtocolV1();
      final offer = protocol.createOffer();
      expect(
        () => protocol.checkCode(offer.code),
        moveFails(WalletMoveFailure.wrongStep),
      );
      expect(
        () => protocol.checkCode('https://example.com'),
        moveFails(WalletMoveFailure.notAMoveCode),
      );
      final reply = protocol.seal(offerCode: offer.code, secret: testSecret());
      // A reply without its sealed part. A shorter but well-formed box gets
      // digits of its own, and then fails to open.
      expect(
        () => protocol.checkCode(reply.substring(0, reply.lastIndexOf('.'))),
        moveFails(WalletMoveFailure.damaged),
      );
      offer.dispose();
    });
  });

  group('wallet move protocol', () {
    test('moves a wallet with two codes and nothing else', () {
      for (final secret in [
        testSecret(),
        testSecret(
          name: 'Old savings',
          type: TransferWalletType.legacy,
          seed: 'my own legacy passphrase',
          phraseConfirmed: false,
        ),
      ]) {
        final offer = WalletMoveProtocolV1().createOffer();
        expect(offer.code, matches(_offerShape));
        final reply = _seal(offer.code, secret);
        expect(reply, matches(_replyShape));
        expectSameSecret(offer.open(reply), secret);
      }
    });

    test('carries the seed exactly as typed', () {
      for (final seed in [
        '  Abandon  abandon\tabout\n',
        'é and é stay distinct',
        'ﬁligree ＷＩＤＥ zero​width',
        '"quoted" \\ back\\slash \u0000 nul',
        'fox 🦊 and a lone \ud800 surrogate',
      ]) {
        final secret = testSecret(seed: seed, type: TransferWalletType.legacy);
        final offer = WalletMoveProtocolV1().createOffer();
        expectSameSecret(offer.open(_seal(offer.code, secret)), secret);
      }
    });

    test('every offer and every reply is new', () {
      final protocol = WalletMoveProtocolV1();
      final first = protocol.createOffer();
      final second = protocol.createOffer();
      final [_, firstKey, firstSession] = first.code.split('.');
      final [_, secondKey, secondSession] = second.code.split('.');
      expect(firstKey, isNot(secondKey));
      expect(firstSession, isNot(secondSession));

      final replies = [_seal(first.code), _seal(first.code)];
      expect(replies.first.split('.')[2], isNot(replies.last.split('.')[2]));
      expect(replies.first.split('.')[3], isNot(replies.last.split('.')[3]));
      expectSameSecret(first.open(replies.last), testSecret());
    });

    test('the largest wallet that fits in a code still moves', () {
      // 356 quotes escape to 712 bytes, so the plaintext is 1,448 bytes,
      // which seals to exactly the longest code.
      final secret = testSecret(
        name: 'w',
        type: TransferWalletType.legacy,
        seed: '${'"' * 356}${'a' * 668}',
        phraseConfirmed: false,
      );
      expect(secret.encode().length, 1448);
      final offer = WalletMoveProtocolV1().createOffer();
      final reply = _seal(offer.code, secret);
      expect(reply.length, WalletMoveProtocolV1.maxCodeLength);
      expectSameSecret(offer.open(reply), secret);
    });

    test('a wallet too large for a code is refused before sealing', () {
      // The secret itself caps its encoding at what one code holds, so
      // sealing never meets an oversized one; it is refused unnamed.
      expect(
        () => testSecret(
          name: 'Big wallet',
          type: TransferWalletType.legacy,
          seed: '${'"' * 357}${'a' * 667}',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'text',
            allOf(
              isNot(contains('Big wallet')),
              isNot(contains('aaaa')),
              isNot(contains('""')),
            ),
          ),
        ),
      );
    });
  });

  group('offer lifetime', () {
    test('lasts ten minutes, in UTC', () {
      var now = DateTime.utc(2026, 11, 18, 9);
      final offer = WalletMoveProtocolV1(clock: () => now).createOffer();
      expect(offer.expiresAt, DateTime.utc(2026, 11, 18, 9, 10));
      expect(offer.expiresAt.isUtc, isTrue);
      final reply = _seal(offer.code);
      now = offer.expiresAt.subtract(const Duration(microseconds: 1));
      expectSameSecret(offer.open(reply), testSecret());
    });

    test('takes a custom lifetime and refuses a non-positive one', () {
      final now = DateTime(2026, 11, 18, 9);
      final offer = WalletMoveProtocolV1(
        clock: () => now,
        offerLifetime: const Duration(minutes: 2),
      ).createOffer();
      expect(
        offer.expiresAt.isAtSameMomentAs(now.add(const Duration(minutes: 2))),
        isTrue,
      );
      expect(
        () => WalletMoveProtocolV1(offerLifetime: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => WalletMoveProtocolV1(offerLifetime: const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });

    test('refuses at and after expiry, and forgets its key for good', () {
      var now = DateTime.utc(2026, 11, 18, 9);
      final offer = WalletMoveProtocolV1(clock: () => now).createOffer();
      final reply = _seal(offer.code);
      now = offer.expiresAt;
      expect(() => offer.open(reply), moveFails(WalletMoveFailure.expired));
      now = DateTime.utc(2026, 11, 18, 9, 1);
      expect(() => offer.open(reply), moveFails(WalletMoveFailure.expired));
    });

    test('a successful open uses the offer up', () {
      final offer = WalletMoveProtocolV1().createOffer();
      final reply = _seal(offer.code);
      offer.open(reply);
      expect(() => offer.open(reply), moveFails(WalletMoveFailure.wrongStep));
      expect(
        () => offer.open(_seal(offer.code)),
        moveFails(WalletMoveFailure.wrongStep),
      );
    });

    test('a refused reply leaves the offer usable', () {
      final offer = WalletMoveProtocolV1().createOffer();
      final other = WalletMoveProtocolV1().createOffer();
      expect(
        () => offer.open(_seal(other.code)),
        moveFails(WalletMoveFailure.notForThisDevice),
      );
      expect(
        () => offer.open('bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'),
        moveFails(WalletMoveFailure.notAMoveCode),
      );
      expectSameSecret(offer.open(_seal(offer.code)), testSecret());
    });

    test('dispose ends the offer but keeps its public code', () {
      final offer = WalletMoveProtocolV1().createOffer();
      final reply = _seal(offer.code);
      offer
        ..dispose()
        ..dispose();
      expect(() => offer.open(reply), moveFails(WalletMoveFailure.expired));
      expect(offer.code, matches(_offerShape));
    });
  });

  group('secrets stay out of text', () {
    test('an offer and a protocol show no key, code or seed', () {
      final scalar = List.generate(32, (i) => 0x10 + i);
      final protocol = WalletMoveProtocolV1(
        random: ScriptedRandom([...scalar, ...List.filled(16, 7)]),
      );
      final offer = protocol.createOffer();
      for (final text in [offer.toString(), protocol.toString()]) {
        expect(text, isNot(contains(hexOf(scalar))));
        expect(text, isNot(contains(b64(scalar))));
        expect(text, isNot(contains(offer.code.split('.')[1])));
      }
      expect(testSecret().toString(), isNot(contains('abandon')));
    });

    test('a refusal reads as its failure and carries no input', () {
      for (final failure in WalletMoveFailure.values) {
        expect(
          WalletMoveException(failure).toString(),
          'WalletMoveException(${failure.name})',
        );
      }
      final offer = WalletMoveProtocolV1().createOffer();
      final reply = _seal(offer.code);
      final fields = reply.split('.');
      final box = unb64(fields[3])..last ^= 1;
      final tampered = [...fields.take(3), b64(box)].join('.');
      for (final input in [tampered, '${offer.code}=', '${reply}x']) {
        try {
          offer.open(input);
          fail('accepted a tampered reply');
        } on WalletMoveException catch (error) {
          expect(error.toString(), isNot(contains(input.split('.').last)));
        }
      }
    });
  });

  _refusalCases();
}
