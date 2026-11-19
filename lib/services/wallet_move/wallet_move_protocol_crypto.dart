part of 'wallet_move_protocol.dart';

final _curve = ECCurve_secp256r1();
final _label = utf8.encode('gleec.wallet.move.v1');
final _byteMask = BigInt.from(0xff);

/// What both sides bind into the key and the tag. Every part has a fixed
/// length, so plain concatenation is unambiguous.
final class _Binding {
  _Binding(this.sessionId, this.offerKey, this.replyKey);

  final Uint8List sessionId;
  final Uint8List offerKey;
  final Uint8List replyKey;

  Uint8List get info =>
      Uint8List.fromList([..._label, ...offerKey, ...replyKey]);

  Uint8List get aad =>
      Uint8List.fromList([..._label, ...sessionId, ...offerKey, ...replyKey]);
}

/// A one-time P-256 key. Only the scalar's bytes are kept, so [wipe] can
/// clear them; the BigInt each use builds cannot be cleared and is dropped.
/// pointycastle's arithmetic is not constant-time, but a key lives for one
/// offer of minutes and is only reached by camera scans: no usable oracle.
final class _MoveKey {
  _MoveKey._(this._scalar, this.publicKey);

  /// Rejection sampling keeps the scalar uniform in [1, n - 1]. A source
  /// that keeps failing is broken, not unlucky.
  factory _MoveKey.generate(Random random) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final scalar = _randomBytes(32, random);
      final d = _unsigned(scalar);
      if (d > BigInt.zero && d < _curve.n) {
        return _MoveKey._(scalar, (_curve.G * d)!.getEncoded());
      }
      scalar.fillRange(0, scalar.length, 0);
    }
    throw StateError('No usable random key');
  }

  final Uint8List _scalar;

  /// The 33-byte compressed point.
  final Uint8List publicKey;
  bool _wiped = false;

  bool get isWiped => _wiped;

  /// ECDH with [peer], then HKDF-SHA256 over the shared x-coordinate.
  Uint8List sessionKey(ECPoint peer, _Binding binding) {
    if (_wiped) throw StateError('Move key already wiped');
    final agreement = ECDHBasicAgreement()
      ..init(ECPrivateKey(_unsigned(_scalar), _curve));
    final shared = _fixed(
      agreement.calculateAgreement(ECPublicKey(peer, _curve)),
    );
    try {
      return _hkdf(shared, binding.sessionId, binding.info);
    } finally {
      shared.fillRange(0, shared.length, 0);
    }
  }

  void wipe() {
    _scalar.fillRange(0, _scalar.length, 0);
    _wiped = true;
  }

  @override
  String toString() => '_MoveKey(<redacted>)';
}

/// Returns nonce ‖ ciphertext ‖ tag. The caller wipes [plaintext].
Uint8List _sealBox(
  _MoveKey own,
  ECPoint peer,
  _Binding binding,
  Uint8List nonce,
  Uint8List plaintext,
) {
  final key = own.sessionKey(peer, binding);
  try {
    return Uint8List.fromList([
      ...nonce,
      ..._gcm(true, key, nonce, binding.aad, plaintext),
    ]);
  } finally {
    key.fillRange(0, key.length, 0);
  }
}

/// Any failure means the box was not sealed for this offer, or was altered
/// after sealing; the two cannot be told apart.
Uint8List _openBox(
  _MoveKey own,
  ECPoint peer,
  _Binding binding,
  Uint8List box,
) {
  try {
    final key = own.sessionKey(peer, binding);
    try {
      return _gcm(
        false,
        key,
        Uint8List.sublistView(box, 0, _nonceLength),
        binding.aad,
        Uint8List.sublistView(box, _nonceLength),
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  } on Object {
    _fail(WalletMoveFailure.notForThisDevice);
  }
}

/// AES-256-GCM into a buffer this code owns: pointycastle writes the
/// plaintext out before it checks the tag, and a failed check must not leave
/// it behind.
Uint8List _gcm(
  bool encrypt,
  Uint8List key,
  Uint8List nonce,
  Uint8List aad,
  Uint8List input,
) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      encrypt,
      AEADParameters(KeyParameter(key), _tagLength * 8, nonce, aad),
    );
  final output = Uint8List(input.length + (encrypt ? _tagLength : -_tagLength));
  try {
    final written = cipher.processBytes(input, 0, input.length, output, 0);
    cipher.doFinal(output, written);
    return output;
  } on Object {
    output.fillRange(0, output.length, 0);
    rethrow;
  }
}

/// HKDF-SHA256 (RFC 5869); a single expand block gives the 32-byte key.
Uint8List _hkdf(Uint8List ikm, Uint8List salt, Uint8List info) {
  final prk = (HMac(SHA256Digest(), 64)..init(KeyParameter(salt))).process(ikm);
  try {
    final expand = HMac(SHA256Digest(), 64)..init(KeyParameter(prk));
    return expand.process(Uint8List.fromList([...info, 1]));
  } finally {
    prk.fillRange(0, prk.length, 0);
  }
}

Uint8List _randomBytes(int length, Random random) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

BigInt _unsigned(Uint8List bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

/// 32 big-endian bytes, left-padded: the x-coordinate is below the prime.
Uint8List _fixed(BigInt value) {
  final bytes = Uint8List(32);
  var rest = value;
  for (var i = bytes.length - 1; i >= 0; i--) {
    bytes[i] = (rest & _byteMask).toInt();
    rest >>= 8;
  }
  return bytes;
}
