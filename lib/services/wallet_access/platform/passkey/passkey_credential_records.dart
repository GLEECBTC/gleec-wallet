part of 'passkey_credential_backend.dart';

typedef _Binding = ({
  Uint8List credentialId,
  Uint8List? userHandle,
  Uint8List aesKey,
});

final class _Slot {
  const _Slot(this.raw, this.envelope);

  final String raw;

  /// Null for a record this build cannot read: damaged, or written by a
  /// later build. It can be removed or replaced, never opened.
  final PasskeyEnvelope? envelope;

  String get fingerprint => sha256.convert(utf8.encode(raw)).toString();
}

final class _Permit {
  const _Permit(this.key, this.fingerprint, this.generation, this.expires);

  final String key;
  final String fingerprint;
  final int generation;
  final Duration expires;

  bool valid(String key, _Slot slot, int generation, Duration now) =>
      this.key == key &&
      fingerprint == slot.fingerprint &&
      this.generation == generation &&
      now < expires;
}

final class _Readback {
  _Readback(this.permit, this.aesKey, {required void Function() onExpiry}) {
    _expiry = Timer(PasskeyCredentialBackend._readbackLifetime, onExpiry);
  }

  final _Permit permit;
  final Uint8List aesKey;
  late final Timer _expiry;

  void wipe() {
    _expiry.cancel();
    aesKey.fillRange(0, aesKey.length, 0);
  }
}
