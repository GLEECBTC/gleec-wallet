import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../wallet_access_types.dart';
import 'passkey_authenticator.dart';
import 'passkey_envelope.dart';

/// Checks everything an assertion proves without the passkey's public key.
///
/// A passkey created in a browser leaves its public key in that browser, and
/// an assertion never carries one, so the signature cannot be verified here.
/// The envelope's authenticated decryption is the cryptographic gate: only
/// the passkey that produced the PRF output can open it. These checks keep a
/// malformed, mismatched or unverified response from getting that far.
void checkPasskeyAssertion(
  PasskeyAssertion assertion,
  PasskeyAssertionRequest request, {
  Uint8List? expectedUserHandle,
}) {
  void invalid() =>
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);

  final id = assertion.credentialId;
  if (id.isEmpty || id.length > 1023 || assertion.signature.isEmpty) invalid();
  if (request.allowCredentials.isNotEmpty &&
      !request.allowCredentials.any(
        (allowed) => passkeyBytesEqual(allowed, id),
      )) {
    invalid();
  }
  final handle = assertion.userHandle;
  if (expectedUserHandle != null &&
      handle != null &&
      !passkeyBytesEqual(handle, expectedUserHandle)) {
    invalid();
  }

  final data = assertion.authenticatorData;
  final rpIdHash = sha256.convert(utf8.encode(request.rpId)).bytes;
  // User presence (0x01) and user verification (0x04) are both required:
  // a PRF evaluated without verification uses a different secret.
  if (data.length < 37 ||
      (data[32] & 0x05) != 0x05 ||
      !passkeyBytesEqual(data.sublist(0, 32), rpIdHash)) {
    invalid();
  }

  final raw = assertion.clientDataJson;
  if (raw.length > 16384) invalid();
  Object? client;
  try {
    client = jsonDecode(utf8.decode(raw));
  } on Object {
    invalid();
  }
  if (client is! Map ||
      client['type'] != 'webauthn.get' ||
      client['crossOrigin'] == true ||
      !passkeyOriginAllowed(client['origin'], request.rpId) ||
      !_sameChallenge(client['challenge'], request.challenge)) {
    invalid();
  }

  if (assertion.prf.length != PasskeyEnvelope.prfLength) {
    throw const WalletAccessException(WalletAccessFailure.prfUnavailable);
  }
}

/// Apple platforms and the Windows bridge report the relying party's web
/// origin. Android reports the app signing certificate, which the native
/// bridge checks against the APK after Credential Manager resolves the link.
bool passkeyOriginAllowed(Object? origin, String rpId) =>
    origin is String &&
    (origin == 'https://$rpId' ||
        RegExp(r'^android:apk-key-hash:[A-Za-z0-9_-]{43}$').hasMatch(origin));

bool _sameChallenge(Object? encoded, Uint8List expected) {
  if (encoded is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
    return false;
  }
  try {
    return passkeyBytesEqual(
      base64Url.decode(base64Url.normalize(encoded)),
      expected,
    );
  } on FormatException {
    return false;
  }
}
