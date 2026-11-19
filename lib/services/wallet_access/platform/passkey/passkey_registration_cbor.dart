part of 'passkey_registration.dart';

/// Decodes one CBOR item that fills [bytes] exactly.
@visibleForTesting
Object? passkeyCborDecode(Uint8List bytes) => _CborReader.decode(bytes);

/// The CBOR that WebAuthn registrations use (RFC 8949): unsigned and
/// negative integers, byte and text strings, arrays, maps keyed by integers
/// or text, booleans and null. Indefinite lengths, tags, floats and repeated
/// keys are refused, containers nest at most [_maxDepth] deep, and every
/// count is checked against the bytes left before anything is read. Every
/// failure is the same [FormatException], carrying none of the input.
final class _CborReader {
  _CborReader(this._bytes, this._offset);

  static const _maxDepth = 8;

  /// 2^53 - 1: integers stay exact on every platform, the web included.
  static const _maxInteger = 0x1fffffffffffff;
  static const _maxBeforeShift = (_maxInteger - 255) ~/ 256;

  final Uint8List _bytes;
  int _offset;

  int get remaining => _bytes.length - _offset;

  static Object? decode(Uint8List bytes) {
    final reader = _CborReader(bytes, 0);
    final value = reader.read();
    if (reader.remaining != 0) _malformed();
    return value;
  }

  Object? read([int depth = 0]) {
    final initial = _byte();
    final info = initial & 0x1f;
    switch (initial >> 5) {
      case 0:
        return _argument(info);
      case 1:
        return -1 - _argument(info);
      case 2:
        return _take(_argument(info));
      case 3:
        try {
          return utf8.decode(_take(_argument(info)));
        } on FormatException {
          _malformed();
        }
      case 4:
        final count = _argument(info);
        // Each element takes at least one byte.
        if (depth >= _maxDepth || count > remaining) _malformed();
        return List<Object?>.generate(count, (_) => read(depth + 1));
      case 5:
        final count = _argument(info);
        if (depth >= _maxDepth || count > remaining ~/ 2) _malformed();
        final map = <Object, Object?>{};
        for (var i = 0; i < count; i++) {
          final Object key = switch (read(depth + 1)) {
            final int label => label,
            final String label => label,
            _ => _malformed(),
          };
          if (map.containsKey(key)) _malformed();
          map[key] = read(depth + 1);
        }
        return map;
      case 7:
        return switch (info) {
          20 => false,
          21 => true,
          22 => null,
          _ => _malformed(),
        };
      default:
        _malformed();
    }
  }

  int _argument(int info) => switch (info) {
    < 24 => info,
    24 => _unsigned(1),
    25 => _unsigned(2),
    26 => _unsigned(4),
    27 => _unsigned(8),
    _ => _malformed(),
  };

  /// Big-endian, by multiplication: shifts truncate to 32 bits on the web.
  int _unsigned(int length) {
    if (length > remaining) _malformed();
    var value = 0;
    for (var i = 0; i < length; i++) {
      if (value > _maxBeforeShift) _malformed();
      value = value * 256 + _bytes[_offset++];
    }
    return value;
  }

  Uint8List _take(int length) {
    if (length > remaining) _malformed();
    final start = _offset;
    _offset += length;
    return _bytes.sublist(start, _offset);
  }

  int _byte() {
    if (remaining < 1) _malformed();
    return _bytes[_offset++];
  }
}

Never _malformed() => throw const FormatException('Malformed CBOR');
