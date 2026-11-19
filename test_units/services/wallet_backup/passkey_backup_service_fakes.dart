part of 'passkey_backup_service_test.dart';

const _rp = 'backup.example.org';
const _config = WalletTransferConfig(
  passkeyBackupEnabled: true,
  backupRpId: _rp,
  googleDriveEnabled: true,
);
const _googleAaguid = 'ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4';

/// Flags: user present, verified, backup eligible, backed up, attested.
const _synced = 0x5D;
const _deviceBound = 0x45;

Matcher _backupFails(PasskeyBackupFailure failure) => throwsA(
  isA<PasskeyBackupException>().having((e) => e.failure, 'failure', failure),
);

Matcher _accessFails(WalletAccessFailure failure) => throwsA(
  isA<WalletAccessException>().having((e) => e.failure, 'failure', failure),
);

WalletTransferSecret _secret({String name = 'Savings'}) => WalletTransferSecret(
  walletName: name,
  type: TransferWalletType.legacy,
  // Legacy seeds are kept byte for byte, spacing included.
  seed: 'Correct  horse battery staple ',
  phraseConfirmed: true,
);

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

bool _wiped(Uint8List bytes) => bytes.every((byte) => byte == 0);

/// A passkey as a provider holds it: the PRF is HMAC over the salt, the way
/// WebAuthn maps it onto CTAP hmac-secret.
class _Passkey {
  _Passkey(int seed, this.userHandle)
    : id = Uint8List.fromList(List.generate(16, (i) => seed * 17 + i)),
      secret = Uint8List.fromList(List.generate(32, (i) => seed * 7 + i));

  final Uint8List id;
  final Uint8List userHandle;
  final Uint8List secret;

  Uint8List prf(Uint8List salt) {
    final mapped = sha256.convert([...utf8.encode('WebAuthn PRF'), 0, ...salt]);
    return Uint8List.fromList(Hmac(sha256, secret).convert(mapped.bytes).bytes);
  }
}

/// The password manager both fakes share. Every PRF buffer it hands out is
/// kept so a test can see that the service wiped it.
class _Provider {
  final passkeys = <_Passkey>[];
  final made = <_Passkey>[];
  final handedOut = <Uint8List>[];

  _Passkey create(Uint8List userHandle) {
    final passkey = _Passkey(made.length + 1, Uint8List.fromList(userHandle));
    passkeys.add(passkey);
    made.add(passkey);
    return passkey;
  }

  _Passkey? find(List<int> id) =>
      passkeys.where((held) => _b64(held.id) == _b64(id)).firstOrNull;

  Uint8List hand(Uint8List prf) {
    handedOut.add(prf);
    return prf;
  }
}

class _FakeRegistrar implements PasskeyRegistrar {
  _FakeRegistrar(this.provider);

  final _Provider provider;
  final requests = <PasskeyRegistrationRequest>[];
  final removed = <Uint8List>[];
  bool supported = true;
  WalletAccessFailure? failure;
  bool prfAtCreation = true;
  Uint8List? creationPrf;
  int flags = _synced;
  List<String> transports = const ['internal', 'hybrid'];
  bool wrongChallenge = false;

  /// Answers with a passkey the provider already holds, as a confused
  /// platform might.
  _Passkey? reuse;
  int cancels = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<PasskeyRegistration> register(
    PasskeyRegistrationRequest request,
  ) async {
    requests.add(request);
    if (failure case final failure?) throw WalletAccessException(failure);
    final passkey = reuse ?? provider.create(request.userId);
    final prf = creationPrf ?? passkey.prf(request.prfSalt);
    return PasskeyRegistration(
      credentialId: Uint8List.fromList(passkey.id),
      clientDataJson: utf8.encode(
        jsonEncode({
          'type': 'webauthn.create',
          'challenge': _b64(wrongChallenge ? [1, 2, 3] : request.challenge),
          'origin': 'https://${request.rpId}',
          'crossOrigin': false,
        }),
      ),
      attestationObject: _attestation(request.rpId, flags, passkey.id),
      prfOutput: prfAtCreation ? provider.hand(prf) : null,
      transports: transports,
    );
  }

  /// The provider drops the passkey, as iOS 26 and Android 15 may.
  @override
  Future<void> reportRemoved({
    required String rpId,
    required Uint8List credentialId,
  }) async {
    removed.add(Uint8List.fromList(credentialId));
    provider.passkeys.removeWhere(
      (held) => _b64(held.id) == _b64(credentialId),
    );
  }

  @override
  Future<void> cancel() async => cancels++;
}

class _FakeAuthenticator implements PasskeyAuthenticator {
  _FakeAuthenticator(this.provider);

  final _Provider provider;
  final requests = <PasskeyAssertionRequest>[];
  bool supported = true;
  int cancels = 0;

  /// A failure for the n-th assertion (from 0), or none.
  WalletAccessFailure? Function(int call)? failOn;

  /// Other key material for the n-th assertion.
  bool Function(int call)? changeKeyOn;
  _Passkey? answerWith;
  Uint8List? userHandle;
  Future<void> Function()? beforeReply;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<PasskeyAssertion> getAssertion(PasskeyAssertionRequest request) async {
    final call = requests.length;
    requests.add(request);
    await beforeReply?.call();
    if (failOn?.call(call) case final failure?) {
      throw WalletAccessException(failure);
    }
    final passkey =
        answerWith ??
        request.allowCredentials
            .map(provider.find)
            .whereType<_Passkey>()
            .firstOrNull;
    if (passkey == null) {
      throw const WalletAccessException(WalletAccessFailure.passkeyNotFound);
    }
    var prf = passkey.prf(request.salt);
    if (changeKeyOn?.call(call) ?? false) {
      prf = Uint8List.fromList([for (final byte in prf) byte ^ 0x5a]);
    }
    return PasskeyAssertion(
      credentialId: Uint8List.fromList(passkey.id),
      userHandle: userHandle ?? Uint8List.fromList(passkey.userHandle),
      authenticatorData: Uint8List.fromList([
        ...sha256.convert(utf8.encode(request.rpId)).bytes,
        0x1D,
        0,
        0,
        0,
        1,
      ]),
      clientDataJson: utf8.encode(
        jsonEncode({
          'type': 'webauthn.get',
          'challenge': _b64(request.challenge),
          'origin': 'https://${request.rpId}',
        }),
      ),
      signature: Uint8List.fromList(List.filled(70, 7)),
      prf: provider.hand(prf),
    );
  }
}

/// A store with a hook for each way one can fail a backup.
class _MemoryStore implements BackupRecordStore {
  _MemoryStore(this.kind);

  @override
  final BackupStoreKind kind;
  final records = <String, String>{};
  final deleted = <String>[];
  bool available = true;
  int lists = 0;
  PasskeyBackupFailure? writeFailure;
  bool writeLandsAnyway = false;
  PasskeyBackupFailure? listFailure;
  bool hideOnList = false;
  String Function(String raw)? tamper;

  @override
  Future<bool> isAvailable() async => available;

  int prepares = 0;
  PasskeyBackupException? prepareFailure;

  @override
  Future<void> prepare() async {
    prepares++;
    if (prepareFailure case final failure?) throw failure;
  }

  @override
  Future<List<StoredBackup>> list() async {
    lists++;
    if (listFailure case final failure?) throw PasskeyBackupException(failure);
    if (hideOnList) return const [];
    return [
      for (final MapEntry(:key, :value) in records.entries)
        StoredBackup(
          id: key,
          store: kind,
          created: DateTime.utc(2000),
          raw: tamper?.call(value) ?? value,
        ),
    ];
  }

  /// Runs as a write starts, to look at what is recorded meanwhile.
  Future<void> Function()? onWrite;

  @override
  Future<void> write(String id, String raw) async {
    await onWrite?.call();
    if (writeFailure case final failure?) {
      if (writeLandsAnyway) records[id] = raw;
      throw PasskeyBackupException(failure);
    }
    records[id] = raw;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    records.remove(id);
  }
}

/// Round-trips through JSON text, as the app's preferences storage does.
class _JsonStorage implements BaseStorage {
  final values = <String, String>{};
  bool refuseWrites = false;

  /// Reports success without keeping anything.
  bool dropWrites = false;

  @override
  Future<dynamic> read(String key) async {
    final value = values[key];
    return value == null ? null : jsonDecode(value);
  }

  @override
  Future<bool> write(String key, dynamic data) async {
    if (refuseWrites) return false;
    if (!dropWrites) values[key] = jsonEncode(data);
    return true;
  }

  @override
  Future<bool> delete(String key) async => values.remove(key) != null;
}

class _Rig {
  _Rig({WalletTransferConfig config = _config, this.platformSupported = true}) {
    service = PasskeyBackupService(
      config: config,
      registrar: registrar,
      authenticator: authenticator,
      stores: {
        BackupStoreKind.iCloudKeychain: keychain,
        BackupStoreKind.googleDrive: drive,
      },
      index: index,
      clock: () => now,
      random: Random(7),
      isAppleOrAndroidPlatform: () => platformSupported,
    );
  }

  final provider = _Provider();
  late final registrar = _FakeRegistrar(provider);
  late final authenticator = _FakeAuthenticator(provider);
  final keychain = _MemoryStore(BackupStoreKind.iCloudKeychain);
  final drive = _MemoryStore(BackupStoreKind.googleDrive);
  final storage = _JsonStorage();
  late final index = PasskeyBackupIndex(storage: storage);
  bool platformSupported;
  DateTime now = DateTime.utc(2026, 11, 18, 12, 30, 15, 250);
  late final PasskeyBackupService service;

  Future<PasskeyBackupEntry> create({
    BackupStoreKind store = BackupStoreKind.iCloudKeychain,
    String walletKey = 'wallet-1',
  }) => service.create(walletKey: walletKey, secret: _secret(), store: store);
}

// A minimal CBOR writer for the attestation object a platform returns.
List<int> _head(int major, int value) => value < 24
    ? [major << 5 | value]
    : value < 256
    ? [major << 5 | 24, value]
    : [major << 5 | 25, value >> 8, value & 0xff];

List<int> _int(int value) =>
    value >= 0 ? _head(0, value) : _head(1, -1 - value);

List<int> _text(String value) {
  final bytes = utf8.encode(value);
  return [..._head(3, bytes.length), ...bytes];
}

List<int> _bstr(List<int> bytes) => [..._head(2, bytes.length), ...bytes];

Uint8List _attestation(String rpId, int flags, List<int> credentialId) {
  final aaguid = [
    for (var i = 0; i < 32; i += 2)
      int.parse(
        _googleAaguid.replaceAll('-', '').substring(i, i + 2),
        radix: 16,
      ),
  ];
  final coseKey = [
    ..._head(5, 5),
    ..._int(1), ..._int(2), // kty: EC2
    ..._int(3), ..._int(-7), // alg: ES256
    ..._int(-1), ..._int(1), // crv: P-256
    ..._int(-2), ..._bstr(List.filled(32, 1)),
    ..._int(-3), ..._bstr(List.filled(32, 2)),
  ];
  final authData = [
    ...sha256.convert(utf8.encode(rpId)).bytes,
    flags,
    0, 0, 0, 0, // sign count
    ...aaguid,
    credentialId.length >> 8,
    credentialId.length & 0xff,
    ...credentialId,
    ...coseKey,
  ];
  return Uint8List.fromList([
    ..._head(5, 3),
    ..._text('fmt'),
    ..._text('none'),
    ..._text('attStmt'),
    ..._head(5, 0),
    ..._text('authData'),
    ..._bstr(authData),
  ]);
}
