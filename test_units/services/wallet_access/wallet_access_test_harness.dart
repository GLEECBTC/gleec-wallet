part of 'wallet_access_service_test.dart';

const _replacement = 'Replacement-Secret-6789!';
const _credentialKey = 'gleec.wallet.$_entry';
const _pendingKey = 'wallet_access_pending_v1';
const _lastKey = 'wallet_access_last_v1';
const _signedOutKey = 'wallet_access_signed_out_v1';

Matcher _fails(WalletAccessFailure failure) => throwsA(
  isA<WalletAccessException>().having((e) => e.failure, 'failure', failure),
);

Matcher _authFails(AuthExceptionType type) =>
    throwsA(isA<AuthException>().having((e) => e.type, 'type', type));

/// One service over in-memory fakes that outlive it, so a case can restart
/// the process around what was persisted.
class _Harness {
  _Harness() {
    _start();
  }

  final storage = _Storage();
  final backend = _Backend();
  final auth = _Auth();
  late final sdk = _Sdk(auth);
  late WalletUnlockCoordinator coordinator;
  late WalletAccessService service;
  Duration monotonic = Duration.zero;

  void _start() {
    coordinator = WalletUnlockCoordinator(
      operationGate: WalletOperationGate(),
      monotonicNow: () => monotonic,
    );
    service = WalletAccessService(
      sdk: sdk,
      storage: storage,
      backend: backend,
      unlockCoordinator: coordinator,
      monotonicNow: () => monotonic,
    );
  }

  Future<void> restart() async {
    await service.dispose();
    auth.active = null;
    auth.sessions.observe(null);
    _start();
    await service.initialize();
  }

  Future<void> dispose() async {
    await service.dispose();
    await auth.sessions.dispose();
    await backend.deviceEvents.close();
    await backend.protectionEvents.close();
  }

  /// A signed-in wallet whose generated password only the vault knows.
  Future<KdfUser> install({bool protected = true}) async {
    final user = _user();
    auth.users.add(user);
    auth.activate(user);
    final record = WalletAccessRecord(
      entryId: _entry,
      walletName: 'Wallet',
      isHd: true,
      pubkeyHash: _hash,
      phase: 'ready',
      protection: protected
          ? CredentialProtection.authenticationBound
          : CredentialProtection.appLocal,
      requiresAuthentication: protected,
    );
    await storage.write(_recordsKey, {_entry: record.toJson()});
    await backend.write(
      record.credentialKey,
      _password,
      requireAuthentication: protected,
    );
    await service.didAuthenticate(user, password: _password);
    return user;
  }

  Map<String, dynamic> get storedRecords =>
      Map<String, dynamic>.from(storage.values[_recordsKey] as Map);

  WalletAccessRecord get record => WalletAccessRecord.fromJson(
    Map<String, dynamic>.from(storedRecords[_entry] as Map),
  );

  /// The journal as a process that died mid-change would leave it: the
  /// former password sealed under [newPassword], the engine not yet known.
  Future<void> journalInterruptedChange({
    String newPassword = _replacement,
  }) async {
    final envelope = await PasswordRotationEnvelope.seal(
      newPassword,
      _password,
      _entry,
    );
    await storage.write(_recordsKey, {
      ...storedRecords,
      _entry: record
          .copyWith(phase: 'rotating', rotationEnvelope: envelope)
          .toJson(),
    });
  }
}
