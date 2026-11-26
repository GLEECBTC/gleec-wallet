import 'dart:typed_data';

/// One passkey creation for [rpId]. [userId] is random per passkey: reusing
/// one would replace the earlier passkey on every synced device.
final class PasskeyRegistrationRequest {
  const PasskeyRegistrationRequest({
    required this.rpId,
    required this.challenge,
    required this.userId,
    required this.userName,
    required this.displayName,
    required this.prfSalt,
  });

  final String rpId;
  final Uint8List challenge;
  final Uint8List userId;
  final String userName;
  final String displayName;

  /// Evaluated at creation where the provider supports it, so the key can
  /// be compared with the first sign-in's.
  final Uint8List prfSalt;
}

/// What the platform returned, unchecked.
final class PasskeyRegistration {
  const PasskeyRegistration({
    required this.credentialId,
    required this.clientDataJson,
    required this.attestationObject,
    this.prfOutput,
    this.transports = const [],
  });

  final Uint8List credentialId;
  final Uint8List clientDataJson;
  final Uint8List attestationObject;

  /// The PRF result for the request's salt, when the provider gave one at
  /// creation. Absent is normal; a wrong length is not.
  final Uint8List? prfOutput;
  final List<String> transports;
}

/// A creation that passed every check. The flags come from the signed
/// authenticator data; [aaguid] is an unauthenticated naming hint only.
final class RegisteredPasskey {
  const RegisteredPasskey({
    required this.credentialId,
    required this.backupEligible,
    required this.backupState,
    required this.transports,
    this.aaguid,
    this.prfOutput,
  });

  final Uint8List credentialId;
  final bool backupEligible;
  final bool backupState;
  final List<String> transports;

  /// Canonical lowercase UUID, or null when the provider sent zeros.
  final String? aaguid;
  final Uint8List? prfOutput;

  /// Whether other devices can ever use it: synced, or a portable key.
  bool get reachesOtherDevices =>
      backupEligible ||
      transports.contains('usb') ||
      transports.contains('nfc') ||
      transports.contains('ble');
}

/// Creates passkeys through the OS. Implementations add no checks of their
/// own; `checkPasskeyRegistration` validates every result.
abstract interface class PasskeyRegistrar {
  Future<bool> isSupported();

  /// Throws `WalletAccessException` with the same failures as assertions.
  Future<PasskeyRegistration> register(PasskeyRegistrationRequest request);

  /// Tells the password manager this passkey no longer opens anything, so
  /// it can hide or remove it (iOS/macOS 26, Android 15). Best effort:
  /// never throws, and does nothing where the platform has no such signal.
  Future<void> reportRemoved({
    required String rpId,
    required Uint8List credentialId,
  });

  Future<void> cancel();
}
