import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web_dex/services/wallet_access/platform/credential_backend.dart';
import 'package:web_dex/services/wallet_access/platform/passkey/passkey_authenticator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

const passkeyRp = 'dex.gleec.com';
const passkeyWalletKey = 'gleec.wallet.entry-1';
const passkeyPassword = 'Generated-Secret-0123456789abcdef';

Uint8List bytesOf(int seed, [int length = 32]) =>
    Uint8List.fromList(List.generate(length, (i) => (seed * 31 + i) & 0xff));

/// A passkey as a provider holds it: the PRF is HMAC over the salt the way
/// WebAuthn maps it onto CTAP hmac-secret, so equal inputs give equal keys.
class FakePasskey {
  FakePasskey(int seed)
    : id = bytesOf(seed, 16),
      userHandle = bytesOf(seed + 100),
      secret = bytesOf(seed + 200);

  final Uint8List id;
  final Uint8List userHandle;
  final Uint8List secret;

  Uint8List prf(Uint8List salt) {
    final mapped = sha256.convert([...utf8.encode('WebAuthn PRF'), 0, ...salt]);
    return Uint8List.fromList(Hmac(sha256, secret).convert(mapped.bytes).bytes);
  }
}

class FakePasskeyAuthenticator implements PasskeyAuthenticator {
  final passkeys = <FakePasskey>[FakePasskey(1)];
  bool supported = true;
  int assertions = 0;
  final requests = <PasskeyAssertionRequest>[];

  /// Which held passkey a discoverable request returns.
  int choose = 0;
  Future<void> Function(PasskeyAssertionRequest request)? beforeReply;
  WalletAccessFailure? failure;
  int flags = 0x05;
  String origin = 'https://$passkeyRp';
  String type = 'webauthn.get';
  String rpIdForHash = passkeyRp;
  int prfLength = 32;
  bool omitUserHandle = false;
  bool wrongChallenge = false;
  Uint8List? lastPrf;
  int cancels = 0;

  /// A provider that answers a request for one named passkey with other
  /// key material than it gave when the user chose it.
  bool unstableWhenNamed = false;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<PasskeyAssertion> getAssertion(PasskeyAssertionRequest request) async {
    assertions++;
    requests.add(request);
    await beforeReply?.call(request);
    if (failure != null) throw WalletAccessException(failure!);
    final FakePasskey passkey;
    if (request.allowCredentials.isEmpty) {
      if (passkeys.isEmpty) {
        throw const WalletAccessException(WalletAccessFailure.passkeyNotFound);
      }
      passkey = passkeys[choose];
    } else {
      passkey = passkeys.firstWhere(
        (held) => request.allowCredentials.any(
          (id) => base64Encode(id) == base64Encode(held.id),
        ),
        orElse: () => throw const WalletAccessException(
          WalletAccessFailure.passkeyNotFound,
        ),
      );
    }
    var prf = passkey.prf(request.salt).sublist(0, prfLength);
    if (unstableWhenNamed && request.allowCredentials.isNotEmpty) {
      prf = Uint8List.fromList([for (final byte in prf) byte ^ 0xff]);
    }
    lastPrf = prf;
    final challenge = wrongChallenge ? bytesOf(99) : request.challenge;
    return PasskeyAssertion(
      credentialId: Uint8List.fromList(passkey.id),
      userHandle: omitUserHandle
          ? null
          : Uint8List.fromList(passkey.userHandle),
      authenticatorData: Uint8List.fromList([
        ...sha256.convert(utf8.encode(rpIdForHash)).bytes,
        flags,
        0,
        0,
        0,
        1,
      ]),
      clientDataJson: Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'type': type,
            'challenge': base64Url.encode(challenge).replaceAll('=', ''),
            'origin': origin,
          }),
        ),
      ),
      signature: bytesOf(7, 70),
      prf: prf,
    );
  }
}

class _Item {
  _Item(this.value, this.protected, this.revision);
  final String value;
  final bool protected;
  final int revision;
}

/// The device vault's observable contract: protected records prompt, a read
/// with purpose `delete` lets the next prepareDelete skip its prompt, and a
/// caller cannot weaken a protected record by passing false.
class FakeDeviceVault extends CredentialBackend {
  final items = <String, _Item>{};
  final deviceEvents = StreamController<void>.broadcast(sync: true);
  int prompts = 0;
  final _readGrants = <String, int>{};
  final _tokens = <String, (String, int)>{};
  WalletAccessFailure? promptFailure;
  WalletAccessFailure? metadataFailure;
  bool deleteReplyLost = false;
  WalletAccessFailure? deleteFailure;

  /// False where device unlock isn't set up, such as a phone without a
  /// passcode.
  bool deviceAuthentication = true;

  /// False for a vault with no protected tier at all, as on Linux.
  bool protectedTier = true;

  String? value(String key) => items[key]?.value;
  bool holds(String key) => items.containsKey(key);

  void _prompt() {
    prompts++;
    final failure = promptFailure;
    if (failure != null) throw WalletAccessException(failure);
  }

  @override
  Stream<void> get deviceLocked => deviceEvents.stream;

  @override
  Future<CredentialCapabilities> capabilities() async => CredentialCapabilities(
    available: true,
    protection: protectedTier
        ? CredentialProtection.authenticationBound
        : CredentialProtection.osAccountProtected,
    deviceAuthentication: protectedTier && deviceAuthentication,
    unattendedReturn: !protectedTier,
  );

  @override
  Future<CredentialRecordInfo?> metadata(String key) async {
    if (metadataFailure case final failure?) {
      throw WalletAccessException(failure);
    }
    final item = items[key];
    if (item == null) return null;
    return CredentialRecordInfo(
      protection: item.protected
          ? CredentialProtection.authenticationBound
          : CredentialProtection.osAccountProtected,
      enrolled: item.protected,
      revision: item.revision,
    );
  }

  @override
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  }) async {
    final item = items[key];
    if (item == null) return null;
    if (requireAuthentication && !item.protected) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    if (item.protected) _prompt();
    if (purpose == 'delete') _readGrants[key] = item.revision;
    return item.value;
  }

  @override
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) async {
    final previous = items[key];
    if (previous != null && previous.protected && !requireAuthentication) {
      throw const WalletAccessException(WalletAccessFailure.invalidated);
    }
    if (requireAuthentication) _prompt();
    items[key] = _Item(
      value,
      requireAuthentication,
      (previous?.revision ?? 0) + 1,
    );
  }

  @override
  Future<String?> prepareDelete(String key, {required String reason}) async {
    final item = items[key];
    if (item == null) return null;
    if (_readGrants.remove(key) != item.revision && item.protected) _prompt();
    final token = 'device-${_tokens.length}';
    _tokens[token] = (key, item.revision);
    return token;
  }

  @override
  Future<void> delete(String key, {String? authorization}) async {
    final item = items[key];
    if (authorization != null) {
      final grant = _tokens.remove(authorization);
      if (grant == null || grant.$1 != key || grant.$2 != item?.revision) {
        throw const WalletAccessException(WalletAccessFailure.invalidated);
      }
    } else if (item?.protected ?? false) {
      _prompt();
    }
    final failure = deleteFailure;
    if (failure != null) throw WalletAccessException(failure);
    items.remove(key);
    if (deleteReplyLost) {
      throw const WalletAccessException(WalletAccessFailure.storageFailed);
    }
  }

  @override
  Future<void> cancel() async {
    _readGrants.clear();
    _tokens.clear();
  }

  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) async => PasswordManagerOutcome.unavailable;
}
