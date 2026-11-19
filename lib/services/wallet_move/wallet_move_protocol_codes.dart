part of 'wallet_move_protocol.dart';

const _magic = 'GLEECMOVE';
const _offerStep = 'O';
const _replyStep = 'R';
const _sessionIdLength = 16;
const _publicKeyLength = 33;
const _nonceLength = 12;
const _tagLength = 16;
final _digits = RegExp('[0-9]+');
final _base64Url = RegExp(r'^[A-Za-z0-9_-]+$');

Never _fail(WalletMoveFailure failure) => throw WalletMoveException(failure);

typedef _Offer = ({Uint8List publicKey, ECPoint point, Uint8List sessionId});

typedef _Reply = ({
  Uint8List sessionId,
  Uint8List publicKey,
  ECPoint point,
  Uint8List box,
});

/// `GLEECMOVE1O.<public key>.<session id>`, shown by the new device.
String _offerCode(Uint8List publicKey, Uint8List sessionId) =>
    '${_magic}1$_offerStep.${_text(publicKey)}.${_text(sessionId)}';

/// `GLEECMOVE1R.<session id>.<public key>.<nonce ‖ ciphertext ‖ tag>`, shown
/// by the old device.
String _replyCode(Uint8List sessionId, Uint8List publicKey, Uint8List box) =>
    '${_magic}1$_replyStep.${_text(sessionId)}.${_text(publicKey)}.'
    '${_text(box)}';

_Offer _parseOffer(String code) {
  final fields = _fields(code, _offerStep, 3);
  final publicKey = _bytes(fields[1], _publicKeyLength);
  final sessionId = _bytes(fields[2], _sessionIdLength);
  return (publicKey: publicKey, point: _point(publicKey), sessionId: sessionId);
}

_Reply _parseReply(String code) {
  final fields = _fields(code, _replyStep, 4);
  final sessionId = _bytes(fields[1], _sessionIdLength);
  final publicKey = _bytes(fields[2], _publicKeyLength);
  final box = _bytes(fields[3]);
  if (box.length <= _nonceLength + _tagLength) _fail(WalletMoveFailure.damaged);
  return (
    sessionId: sessionId,
    publicKey: publicKey,
    point: _point(publicKey),
    box: box,
  );
}

/// Names a code by its tag before reading any field, so a code from a newer
/// app or for the other device is called that even where it would not parse.
List<String> _fields(String code, String step, int count) {
  if (!code.startsWith(_magic)) _fail(WalletMoveFailure.notAMoveCode);
  final version = _digits.matchAsPrefix(code, _magic.length)?[0];
  if (version == null) _fail(WalletMoveFailure.notAMoveCode);
  if (version != '1') _fail(WalletMoveFailure.unsupportedVersion);
  final at = _magic.length + version.length;
  final found = code.length > at ? code[at] : '';
  if (found != step && (found == _offerStep || found == _replyStep)) {
    _fail(WalletMoveFailure.wrongStep);
  }
  if (!code.startsWith('$_magic$version$step.') ||
      code.length > WalletMoveProtocolV1.maxCodeLength) {
    _fail(WalletMoveFailure.damaged);
  }
  final fields = code.split('.');
  if (fields.length != count) _fail(WalletMoveFailure.damaged);
  return fields;
}

/// Canonical unpadded base64url: re-encoding must give back the same text,
/// so each set of bytes has exactly one spelling.
Uint8List _bytes(String text, [int? length]) {
  if (text.length % 4 != 1 && _base64Url.hasMatch(text)) {
    try {
      final bytes = base64Url.decode(
        text.padRight((text.length + 3) & ~3, '='),
      );
      if ((length == null || bytes.length == length) && _text(bytes) == text) {
        return bytes;
      }
    } on FormatException {
      // Reported below, without the text.
    }
  }
  _fail(WalletMoveFailure.damaged);
}

String _text(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A compressed point on P-256. The curve's cofactor is one, so every such
/// point but infinity generates the whole group: no small subgroup can trap
/// the shared secret, and no further check is needed.
ECPoint _point(Uint8List encoded) {
  if (encoded[0] == 0x02 || encoded[0] == 0x03) {
    try {
      final point = _curve.curve.decodePoint(encoded);
      if (point != null &&
          !point.isInfinity &&
          passkeyBytesEqual(point.getEncoded(), encoded)) {
        return point;
      }
    } on Object {
      // x is not below the field prime, or no y solves the curve equation.
    }
  }
  _fail(WalletMoveFailure.damaged);
}
