part of 'auth_bloc_test.dart';

const _enginePassword = 'Synthetic-password-123456!';
const _changedPassword = 'Replacement-Secret-6789!';
const _hdOptions = AuthOptions(derivationMethod: DerivationMethod.hdWallet);

/// Like the SDK, this engine refuses to sign in over a session it already
/// holds and checks the password it is given.
class _Engine implements KomodoDefiLocalAuth {
  final sessions = AuthSessionTracker();
  final users = <KdfUser>[];
  final signInModes = <DerivationMethod>[];
  final _watcher = StreamController<KdfUser?>.broadcast();
  KdfUser? active;
  String password = _enginePassword;
  int signOuts = 0;
  int registrations = 0;

  /// While set, the next sign-in or registration waits inside the engine.
  Completer<void>? reached;
  Completer<void>? release;

  KdfUser add({String name = 'Wallet 1'}) {
    final user = KdfUser(
      walletId: WalletId.withPubkeyHash(name, _hdOptions, 'pubkey-$name'),
      isBip39Seed: true,
      metadata: {'_wallet_entry_id': 'entry-$name', 'type': 'hdwallet'},
    );
    users.add(user);
    return user;
  }

  void hold() {
    reached = Completer<void>();
    release = Completer<void>();
  }

  void _activate(KdfUser? user) {
    active = user;
    sessions.observe(user);
  }

  Future<void> _work() async {
    if (reached?.isCompleted == false) reached!.complete();
    await release?.future;
  }

  void _requireSignedOut() {
    if (active != null) {
      throw AuthException(
        'User is signed in.',
        type: AuthExceptionType.alreadySignedIn,
      );
    }
  }

  @override
  Future<KdfUser?> get currentUser async => active;
  @override
  Future<List<KdfUser>> getUsers() async => List.of(users);
  @override
  void onWalletDeletion(Future<void> Function(WalletId walletId) hook) {}
  @override
  Stream<KdfUser?> watchCurrentUser() => _watcher.stream;
  @override
  Future<bool> ensureKdfHealthy() async => true;

  @override
  Future<AuthSessionContext> captureSessionContext() async {
    sessions.observe(active);
    return sessions.current ?? (throw const AuthSessionChangedException());
  }

  @override
  bool isSessionContextCurrent(AuthSessionContext context) =>
      sessions.isCurrent(context);

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!sessions.isCurrent(context)) throw const AuthSessionChangedException();
  }

  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    AuthOptions options = _hdOptions,
  }) async {
    _requireSignedOut();
    final index = users.indexWhere((user) => user.walletId.name == walletName);
    if (index < 0) throw AuthException.notFound();
    signInModes.add(options.derivationMethod);
    await _work();
    if (password != this.password) {
      throw AuthException(
        'Incorrect password',
        type: AuthExceptionType.incorrectPassword,
      );
    }
    // Every sign-in stores the derivation mode it used.
    final user = users[index] = users[index].copyWith(
      walletId: users[index].walletId.copyWith(authOptions: options),
    );
    _activate(user);
    return user;
  }

  @override
  Future<KdfUser> register({
    required String walletName,
    required String password,
    AuthOptions options = _hdOptions,
    Mnemonic? mnemonic,
    Map<String, dynamic> initialMetadata = const {},
    String? provisioningId,
  }) async {
    _requireSignedOut();
    if (users.any((user) => user.walletId.name == walletName)) {
      throw AuthException(
        'Wallet already exists',
        type: AuthExceptionType.walletAlreadyExists,
      );
    }
    registrations++;
    await _work();
    final user = KdfUser(
      walletId: WalletId.withPubkeyHash(
        walletName,
        options,
        'pubkey-$walletName',
      ),
      isBip39Seed: true,
      metadata: {'_wallet_entry_id': 'entry-$walletName', ...initialMetadata},
    );
    users.add(user);
    this.password = password;
    _activate(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    _activate(null);
  }

  @override
  Future<void> verifyPassword({
    required String password,
    required WalletId expectedWalletId,
    AuthSessionContext? expectedSession,
  }) async {
    if (expectedSession != null) ensureSessionContextCurrent(expectedSession);
    if (active?.walletId != expectedWalletId) {
      throw const AuthSessionChangedException();
    }
    if (password != this.password) {
      throw AuthException(
        'Incorrect password',
        type: AuthExceptionType.incorrectPassword,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Vault extends CredentialBackend {
  final values = <String, String>{};

  /// Reads end as a browser does when no unlock prompt could be completed.
  bool cancelReads = false;
  WalletAccessFailure? readFailure;
  @override
  Future<CredentialCapabilities> capabilities() async =>
      const CredentialCapabilities(
        available: true,
        protection: CredentialProtection.authenticationBound,
        deviceAuthentication: true,
      );
  @override
  Future<CredentialRecordInfo?> metadata(String key) async =>
      values.containsKey(key)
      ? const CredentialRecordInfo(
          protection: CredentialProtection.authenticationBound,
          enrolled: true,
        )
      : null;
  @override
  Future<void> write(
    String key,
    String value, {
    required bool requireAuthentication,
  }) async => values[key] = value;
  @override
  Future<String?> read(
    String key, {
    required String reason,
    bool requireAuthentication = false,
    bool automatic = false,
    String? purpose,
  }) async {
    if (cancelReads) {
      throw const WalletAccessException(WalletAccessFailure.canceled);
    }
    if (readFailure != null) throw WalletAccessException(readFailure!);
    return values[key];
  }

  @override
  Future<void> delete(String key, {String? authorization}) async =>
      values.remove(key);
  @override
  Future<void> cancel() async {}
  @override
  Future<PasswordManagerOutcome> savePassword({
    required String username,
    required String password,
    required String title,
  }) async => PasswordManagerOutcome.unknown;
}

class _AccessStorage extends BaseStorage {
  final values = <String, dynamic>{};
  String? failWrite;
  @override
  Future<dynamic> read(String key) async => values[key];
  @override
  Future<bool> write(String key, dynamic data) async {
    if (failWrite == key) return false;
    values[key] = data;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    values.remove(key);
    return true;
  }
}

/// The bloc over the real access service, so that what the engine holds and
/// what the app shows are checked against each other.
class _Session {
  final engine = _Engine();
  final storage = _AccessStorage();
  final vault = _Vault();
  late final coordinator = WalletUnlockCoordinator(
    operationGate: WalletOperationGate(),
  );
  late final access = WalletAccessService(
    sdk: _FakeSdk(engine),
    storage: storage,
    backend: vault,
    unlockCoordinator: coordinator,
  );
  late final bloc = AuthBloc(
    _FakeSdk(engine),
    _FakeWalletsRepository(),
    _FakeSettingsRepository(),
    _FakeTradingStatusService(),
    walletAccessService: access,
  );

  Future<void> dispose() async {
    await bloc.close();
    await access.dispose();
    await engine.sessions.dispose();
  }

  /// A device-protected wallet whose password only the vault holds.
  Future<KdfUser> installManaged() async {
    final user = engine.add();
    final entry = WalletAccessService.entryId(user);
    final record = WalletAccessRecord(
      entryId: entry,
      walletName: user.walletId.name,
      isHd: true,
      pubkeyHash: user.walletId.pubkeyHash,
      phase: 'ready',
      protection: CredentialProtection.authenticationBound,
      requiresAuthentication: true,
    );
    storage.values['wallet_access_records_v1'] = {entry: record.toJson()};
    vault.values[record.credentialKey] = _enginePassword;
    return user;
  }

  Future<AuthBlocState> outcomeOf(AuthBlocEvent event) {
    final settled = bloc.stream
        .firstWhere((state) => !state.isLoading)
        .timeout(const Duration(seconds: 10));
    bloc.add(event);
    return settled;
  }

  /// The app is left while the engine is still opening the wallet.
  Future<AuthBlocState> outcomeAfterFocusLoss(AuthBlocEvent event) async {
    engine.hold();
    final settled = outcomeOf(event);
    await engine.reached!.future;
    coordinator.inactive();
    engine.release!.complete();
    final state = await settled;
    coordinator.resume();
    return state;
  }

  void expectCovered(KdfUser? user) {
    expect(engine.active, isNotNull);
    expect(bloc.state.currentUser, engine.active);
    expect(user, engine.active);
    expect(coordinator.state.hasWallet, isTrue);
    expect(coordinator.state.isLocked, isTrue);
    expect(coordinator.operationGate.allowsOperations, isFalse);
  }
}

void _engineSessionCases() {
  group('AuthBloc keeps the engine session and the app in step', () {
    late _Session s;
    setUp(() {
      s = _Session();
      WalletLoadTimeline.instance.reset();
    });
    tearDown(() => s.dispose());

    test('password sign-in can switch the derivation mode', () async {
      s.engine.add();
      final iguana = _wallet().copyWith(
        config: _wallet().config.copyWith(type: WalletType.iguana),
      );
      final state = await s.outcomeOf(
        AuthSignInRequested(wallet: iguana, password: _enginePassword),
      );
      expect(state.authError, isNull);
      expect(state.currentUser?.walletId.isHd, isFalse);
      expect(s.engine.signInModes, [DerivationMethod.iguana]);
      expect(s.coordinator.operationGate.allowsOperations, isTrue);
    });

    test(
      'a wallet with a record switches mode and keeps device unlock',
      () async {
        await s.installManaged();
        final iguana = _wallet().copyWith(
          config: _wallet().config.copyWith(type: WalletType.iguana),
        );
        final state = await s.outcomeOf(
          AuthSignInRequested(wallet: iguana, password: _enginePassword),
        );
        expect(state.authError, isNull);
        expect(state.currentUser?.walletId.isHd, isFalse);
        final status = await s.access.status();
        expect(status.hasManagedCredential, isTrue);
        expect(s.coordinator.operationGate.allowsOperations, isTrue);
      },
    );

    test('a recovered password change does not sign in twice', () async {
      final user = await s.installManaged();
      final entry = WalletAccessService.entryId(user);
      final records = s.storage.values['wallet_access_records_v1'] as Map;
      records[entry] =
          WalletAccessRecord.fromJson(
                Map<String, dynamic>.from(records[entry] as Map),
              )
              .copyWith(
                phase: 'rotating',
                rotationEnvelope: await PasswordRotationEnvelope.seal(
                  _changedPassword,
                  _enginePassword,
                  entry,
                ),
              )
              .toJson();
      // The engine completed the change before the process died.
      s.engine.password = _changedPassword;
      final state = await s.outcomeOf(
        AuthSignInRequested(wallet: _wallet(), password: _changedPassword),
      );
      expect(state.authError, isNull);
      expect(state.currentUser, s.engine.active);
      expect(s.engine.signInModes, hasLength(1));
      expect(s.vault.values['gleec.wallet.$entry'], _changedPassword);
      expect(s.coordinator.operationGate.allowsOperations, isTrue);
    });

    test('a sign-in finished after focus was lost is shown covered', () async {
      s.engine.add();
      final state = await s.outcomeAfterFocusLoss(
        AuthSignInRequested(wallet: _wallet(), password: _enginePassword),
      );
      expect(state.authError, isNull);
      expect(state.mode, AuthorizeMode.logIn);
      s.expectCovered(state.currentUser);
      // The lock that focus loss calls for is still the user's to open.
      expect(await s.access.unlockCurrent(password: _enginePassword), isTrue);
      expect(s.coordinator.operationGate.allowsOperations, isTrue);
      expect(s.engine.signOuts, 0);
    });

    test(
      'a managed sign-in finished after focus was lost is covered',
      () async {
        final user = await s.installManaged();
        final state = await s.outcomeAfterFocusLoss(
          AuthManagedSignInRequested(wallet: user.wallet),
        );
        expect(state.authError, isNull);
        s.expectCovered(state.currentUser);
        expect(await s.access.unlockCurrent(), isTrue);
      },
    );

    for (final flow in ['restore', 'import', 'register']) {
      test('a $flow finished after focus was lost is shown covered', () async {
        final state = await s.outcomeAfterFocusLoss(switch (flow) {
          'restore' => AuthRestoreRequested(
            wallet: _wallet(),
            password: _enginePassword,
            seed: 'a b c',
          ),
          'import' => AuthImportRequested(
            wallet: _wallet(),
            password: _enginePassword,
            seed: 'a b c',
          ),
          _ => AuthRegisterRequested(
            wallet: _wallet(),
            password: _enginePassword,
          ),
        });
        // The wallet exists: reporting a failed creation would be false, and
        // a retry would be refused as already signed in.
        expect(state.authError, isNull);
        expect(s.engine.registrations, 1);
        s.expectCovered(state.currentUser);
        expect(await s.access.unlockCurrent(password: _enginePassword), isTrue);
      });
    }

    test('a sign-in that cannot be completed closes its session', () async {
      s.engine.add();
      s.storage.failWrite = 'wallet_access_last_v1';
      final failed = await s.outcomeOf(
        AuthSignInRequested(wallet: _wallet(), password: _enginePassword),
      );
      expect(failed.authError?.type, AuthExceptionType.generalAuthError);
      expect(failed.currentUser, isNull);
      expect(s.engine.active, isNull);
      expect(s.coordinator.state.hasWallet, isFalse);
      s.storage.failWrite = null;
      final retried = await s.outcomeOf(
        AuthSignInRequested(wallet: _wallet(), password: _enginePassword),
      );
      expect(retried.authError, isNull);
      expect(retried.currentUser, s.engine.active);
      expect(s.coordinator.operationGate.allowsOperations, isTrue);
    });

    test('a wrong password still reports what the engine said', () async {
      s.engine.add();
      final state = await s.outcomeOf(
        AuthSignInRequested(wallet: _wallet(), password: 'Wrong-password-0!'),
      );
      expect(state.authError?.type, AuthExceptionType.incorrectPassword);
      expect(s.engine.active, isNull);
    });

    test('a migrated legacy wallet opens unlocked and is remembered', () async {
      final state = await s.outcomeOf(
        AuthLegacyMigrationRequested(
          sourceWallet: _wallet(isLegacy: true),
          legacyPassword: 'Legacy-password-1!',
          kdfPassword: _enginePassword,
          targetWalletName: 'Migrated wallet',
          seedPhrase: 'a b c',
        ),
      );
      expect(state.authError, isNull);
      expect(state.currentUser?.walletId.name, 'Migrated wallet');
      // The password just set must not be asked for again straight away.
      expect(s.coordinator.state.hasWallet, isTrue);
      expect(s.coordinator.state.isLocked, isFalse);
      expect(s.coordinator.operationGate.allowsOperations, isTrue);
      expect((await s.access.lastWallet())?.name, 'Migrated wallet');
      expect(await s.access.automaticEntrySuppressed, isFalse);
    });

    test('a failed managed unlock is reported through localisation', () async {
      final user = await s.installManaged();
      s.vault.values.clear();
      final state = await s.outcomeOf(
        AuthManagedSignInRequested(wallet: user.wallet),
      );
      expect(state.authError?.message, 'authManagedUnlockGone');
      expect(s.engine.active, isNull);
    });

    test('a failed managed unlock logs its cause', () async {
      final user = await s.installManaged();
      s.vault.values.clear();
      final logged = Logger.root.onRecord.firstWhere(
        (record) =>
            record.loggerName == 'AuthBloc' &&
            record.message.startsWith('Managed explicit sign-in failed'),
      );
      await s.outcomeOf(AuthManagedSignInRequested(wallet: user.wallet));
      final record = await logged.timeout(const Duration(seconds: 2));
      expect(record.level, Level.SHOUT);
      expect(record.error, isNull);
      expect(
        record.message,
        contains(WalletAccessFailure.missingCredential.name),
      );
      expect(record.stackTrace, isNotNull);
    });

    test('an engine that refuses a managed unlock is logged', () async {
      final user = await s.installManaged();
      s.engine.password = 'Different-password-0!';
      final logged = Logger.root.onRecord.firstWhere(
        (record) =>
            record.loggerName == 'AuthBloc' &&
            record.message.startsWith('Managed explicit sign-in failed'),
      );
      final state = await s.outcomeOf(
        AuthManagedSignInRequested(wallet: user.wallet),
      );
      expect(state.authError?.message, 'authManagedUnlockFailed');
      final record = await logged.timeout(const Duration(seconds: 2));
      expect(record.message, contains('incorrectPassword'));
      expect(record.error, isNull);
      expect(record.stackTrace, isNotNull);
    });
  });
}
