import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_envelope.dart'
    show passkeyBytesEqual;
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';

part 'wallet_move_protocol_codes.dart';
part 'wallet_move_protocol_crypto.dart';

/// Version 1 of the move: a one-time P-256 key on each device, ECDH,
/// HKDF-SHA256 and AES-256-GCM. The session id and both public keys are
/// bound into the key and the tag, so no part of either code can be swapped.
final class WalletMoveProtocolV1 implements WalletMoveProtocol {
  WalletMoveProtocolV1({
    Random? random,
    DateTime Function()? clock,
    this.offerLifetime = const Duration(minutes: 10),
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now {
    if (offerLifetime <= Duration.zero) {
      throw ArgumentError.value(offerLifetime, 'offerLifetime');
    }
  }

  /// The longest code either side reads or writes. Denser QR codes do not
  /// scan reliably off another phone's screen.
  static const maxCodeLength = 2048;

  final Random _random;
  final DateTime Function() _clock;
  final Duration offerLifetime;

  @override
  WalletMoveOffer createOffer() {
    final key = _MoveKey.generate(_random);
    return _WalletMoveOfferV1(
      key,
      _randomBytes(_sessionIdLength, _random),
      _clock().toUtc().add(offerLifetime),
      _clock,
    );
  }

  @override
  void checkOffer(String offerCode) => _parseOffer(offerCode);

  /// Also throws [FormatException] for a wallet whose sealed form would not
  /// fit in [maxCodeLength]; only a seed dense with characters that JSON
  /// escapes gets that large.
  @override
  String seal({
    required String offerCode,
    required WalletTransferSecret secret,
  }) {
    final offer = _parseOffer(offerCode);
    final key = _MoveKey.generate(_random);
    final plaintext = secret.encode();
    try {
      final binding = _Binding(offer.sessionId, offer.publicKey, key.publicKey);
      final nonce = _randomBytes(_nonceLength, _random);
      final box = _sealBox(key, offer.point, binding, nonce, plaintext);
      final reply = _replyCode(offer.sessionId, key.publicKey, box);
      if (reply.length > maxCodeLength) {
        throw const FormatException('Too large for a move code');
      }
      return reply;
    } finally {
      key.wipe();
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  /// Eight digits over every field of the reply, through Argon2id. Someone
  /// filming the old phone sees the real digits, and to pass them off they
  /// would have to seal replies until one matches: about 10^8 attempts, each
  /// costing 16 MiB and three passes, which no attacker finishes in the
  /// seconds before the user scans.
  @override
  Future<String> checkCode(String replyCode) {
    final reply = _parseReply(replyCode);
    final transcript = Uint8List.fromList([
      ...utf8.encode('gleec.wallet.move.v1/check'),
      ...reply.sessionId,
      ...reply.publicKey,
      ...reply.box,
    ]);
    final salt = Uint8List.fromList(reply.sessionId);
    return Isolate.run(() => _checkDigits(transcript, salt));
  }
}

String _checkDigits(Uint8List transcript, Uint8List salt) {
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: 8,
        iterations: 3,
        memory: 16384,
        lanes: 1,
      ),
    );
  final out = Uint8List(8);
  generator.deriveKey(transcript, 0, out, 0);
  // 40 bits keep the remainder's bias far below one in a thousand.
  var value = 0;
  for (final byte in out.sublist(0, 5)) {
    value = value * 256 + byte;
  }
  return (value % 100000000).toString().padLeft(8, '0');
}

final class _WalletMoveOfferV1 implements WalletMoveOffer {
  _WalletMoveOfferV1(this._key, this._sessionId, this.expiresAt, this._clock)
    : code = _offerCode(_key.publicKey, _sessionId);

  final _MoveKey _key;
  final Uint8List _sessionId;
  final DateTime Function() _clock;
  bool _opened = false;

  @override
  final String code;

  @override
  final DateTime expiresAt;

  /// A refused reply leaves the offer usable, so a bad scan can be retried;
  /// only success, expiry or [dispose] ends it.
  @override
  WalletTransferSecret open(String replyCode) {
    final reply = _parseReply(replyCode);
    if (_opened) _fail(WalletMoveFailure.wrongStep);
    if (_key.isWiped || !_clock().isBefore(expiresAt)) {
      dispose();
      _fail(WalletMoveFailure.expired);
    }
    if (!passkeyBytesEqual(reply.sessionId, _sessionId)) {
      _fail(WalletMoveFailure.notForThisDevice);
    }
    final binding = _Binding(_sessionId, _key.publicKey, reply.publicKey);
    final plaintext = _openBox(_key, reply.point, binding, reply.box);
    try {
      final secret = WalletTransferSecret.decode(plaintext);
      _opened = true;
      dispose();
      return secret;
    } on FormatException {
      // Authentic, yet not a secret this version reads.
      _fail(WalletMoveFailure.damaged);
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  @override
  void dispose() => _key.wipe();

  @override
  String toString() => 'WalletMoveOffer(<redacted>)';
}
