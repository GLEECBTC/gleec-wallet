import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_registration_types.dart';

const registrationRp = 'backup.example.net';

/// UP, UV, BE, BS and AT: a synced passkey with its credential data.
const registrationFlags = 0x5d;

/// A minimal CBOR writer (RFC 8949): shortest arguments, definite lengths.
Uint8List cbor(Object? value) => Uint8List.fromList(_write(value));

/// Bytes written as they are, for encodings a reader must refuse.
final class CborRaw {
  const CborRaw(this.bytes);

  final List<int> bytes;
}

List<int> cborHead(int major, int argument) {
  final type = major << 5;
  List<int> be(int length) => [
    for (var shift = (length - 1) * 8; shift >= 0; shift -= 8)
      (argument >> shift) & 0xff,
  ];
  if (argument < 24) return [type | argument];
  if (argument < 0x100) return [type | 24, argument];
  if (argument < 0x10000) return [type | 25, ...be(2)];
  if (argument < 0x100000000) return [type | 26, ...be(4)];
  return [type | 27, ...be(8)];
}

List<int> _write(Object? value) => switch (value) {
  CborRaw(:final bytes) => bytes,
  null => [0xf6],
  false => [0xf4],
  true => [0xf5],
  final int number when number >= 0 => cborHead(0, number),
  final int number => cborHead(1, -1 - number),
  final Uint8List bytes => [...cborHead(2, bytes.length), ...bytes],
  final String text => [
    ...cborHead(3, utf8.encode(text).length),
    ...utf8.encode(text),
  ],
  final List<Object?> items => [
    ...cborHead(4, items.length),
    for (final item in items) ..._write(item),
  ],
  final Map<Object?, Object?> map => [
    ...cborHead(5, map.length),
    for (final MapEntry(:key, :value) in map.entries) ...[
      ..._write(key),
      ..._write(value),
    ],
  ],
  _ => throw ArgumentError('Not writable as CBOR'),
};

/// An ES256 key with made-up coordinates: parsed, never used.
Map<int, Object?> registrationCoseKey() => {
  1: 2,
  3: -7,
  -1: 1,
  -2: Uint8List(32)..fillRange(0, 32, 7),
  -3: Uint8List(32)..fillRange(0, 32, 9),
};

/// Authenticator data with attested credential data (WebAuthn §6.1).
Uint8List registrationAuthData({
  required List<int> credentialId,
  String rpId = registrationRp,
  int flags = registrationFlags,
  List<int>? aaguid,
  Object? key,
  Object? extensions,
  List<int> trailing = const [],
}) => Uint8List.fromList([
  ...sha256.convert(utf8.encode(rpId)).bytes,
  flags,
  0,
  0,
  0,
  0,
  ...aaguid ?? List.filled(16, 0),
  credentialId.length >> 8,
  credentialId.length & 0xff,
  ...credentialId,
  ...cbor(key ?? registrationCoseKey()),
  if (extensions != null) ...cbor(extensions),
  ...trailing,
]);

Uint8List registrationAttestation(
  Uint8List authData, {
  String format = 'none',
  Map<Object?, Object?> statement = const {},
}) => cbor({'fmt': format, 'attStmt': statement, 'authData': authData});

Uint8List registrationClientData(
  Uint8List challenge, {
  String type = 'webauthn.create',
  String origin = 'https://$registrationRp',
  Object? crossOrigin = false,
}) => utf8.encode(
  jsonEncode({
    'type': type,
    'challenge': base64Url.encode(challenge).replaceAll('=', ''),
    'origin': origin,
    if (crossOrigin != null) 'crossOrigin': crossOrigin,
  }),
);

/// What a provider returns for [request]: a synced passkey by default, with
/// [prf] as the PRF output at creation when given. Passes
/// `checkPasskeyRegistration` unless an argument breaks it.
PasskeyRegistration fakeRegistration(
  PasskeyRegistrationRequest request, {
  List<int>? credentialId,
  int flags = registrationFlags,
  List<int>? aaguid,
  Uint8List? prf,
  List<String> transports = const ['hybrid', 'internal'],
}) {
  final id = Uint8List.fromList(
    credentialId ?? List.generate(16, (i) => i + 1),
  );
  return PasskeyRegistration(
    credentialId: id,
    clientDataJson: registrationClientData(
      request.challenge,
      origin: 'https://${request.rpId}',
    ),
    attestationObject: registrationAttestation(
      registrationAuthData(
        credentialId: id,
        rpId: request.rpId,
        flags: flags,
        aaguid: aaguid,
      ),
    ),
    prfOutput: prf,
    transports: transports,
  );
}
