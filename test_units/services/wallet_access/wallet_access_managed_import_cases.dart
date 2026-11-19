part of 'wallet_access_service_test.dart';

const _movedSeed =
    'legal winner thank year wave sausage worth useful legal winner thank '
    'yellow';
const _otherSeed =
    'letter advice cage absurd amount doctor acoustic avoid letter advice '
    'cage above';
const _pendingImportKey = 'wallet_access_pending_import_v1';

void _managedImportCases() {
  group('managed import of a moved or restored wallet', () {
    late _Storage storage;
    late _Backend backend;
    late _Auth auth;
    late WalletUnlockCoordinator coordinator;
    late WalletAccessService service;
    setUp(() {
      storage = _Storage();
      backend = _Backend();
      auth = _Auth();
      coordinator = WalletUnlockCoordinator(
        operationGate: WalletOperationGate(),
        monotonicNow: () => Duration.zero,
      );
      service = WalletAccessService(
        sdk: _Sdk(auth),
        storage: storage,
        backend: backend,
        unlockCoordinator: coordinator,
        monotonicNow: () => Duration.zero,
      );
    });
    tearDown(() async {
      await service.dispose();
      await auth.sessions.dispose();
      await backend.deviceEvents.close();
      await backend.protectionEvents.close();
    });

    Future<KdfUser> import({
      String name = 'Moved',
      WalletType type = WalletType.hdwallet,
      String seed = _movedSeed,
    }) => service.importWallet(
      walletName: name,
      walletType: type,
      mnemonic: seed,
      initialMetadata: {'has_backup': true},
    );

    Future<WalletAccessRecord?> recordFor(String id) async {
      final stored = await storage.read(_recordsKey) as Map?;
      final json = stored?[id];
      return json == null
          ? null
          : WalletAccessRecord.fromJson(Map<String, dynamic>.from(json as Map));
    }

    test('opens the moved seed under a generated, stored password', () async {
      final user = await import();
      final registration = auth.registrations.single;
      expect(user.walletId.name, 'Moved');
      expect(registration.name, 'Moved');
      expect(registration.password, hasLength(32));
      expect(auth.seeds[registration.id], _movedSeed);
      expect(
        auth.registeredOptions.single.derivationMethod,
        DerivationMethod.hdWallet,
      );
      final record = await recordFor(registration.id);
      expect(record?.phase, 'ready');
      expect(record?.generated, isTrue);
      expect(backend.values[record!.credentialKey], registration.password);
      expect(await storage.read(_pendingImportKey), isNull);
      expect(await storage.read('wallet_access_pending_v1'), isNull);
    });

    test('a legacy wallet keeps its own derivation', () async {
      await import(type: WalletType.iguana);
      expect(
        auth.registeredOptions.single.derivationMethod,
        DerivationMethod.iguana,
      );
      expect((await recordFor(auth.registrations.single.id))?.isHd, isFalse);
    });

    test('a taken name fails without renaming and leaves nothing', () async {
      auth.collideOnce = true;
      await expectLater(
        import(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.type,
            'type',
            AuthExceptionType.walletAlreadyExists,
          ),
        ),
      );
      expect(auth.registrations.map((e) => e.name), ['Moved']);
      expect(backend.values, isEmpty);
      expect((await storage.read(_recordsKey) as Map?) ?? const {}, isEmpty);
      expect(await storage.read(_pendingImportKey), isNull);
    });

    test('an owned collision keeps the credential it may own', () async {
      auth.ownedCollision = true;
      await expectLater(import(), throwsA(isA<AuthException>()));
      final id = auth.registrations.single.id;
      expect(backend.values, isNotEmpty);
      expect(await recordFor(id), isNotNull);
      expect(await storage.read(_pendingImportKey), isNotNull);
    });

    test('an interrupted import resumes its ID, password and seed', () async {
      auth.failCreationOnce = true;
      await expectLater(import(), throwsStateError);
      final user = await import();
      expect(auth.registrations.map((e) => e.id).toSet(), hasLength(1));
      expect(auth.registrations.map((e) => e.password).toSet(), hasLength(1));
      expect(backend.writes, 1);
      expect(auth.seeds[WalletAccessService.entryId(user)], _movedSeed);
      expect(await storage.read(_pendingImportKey), isNull);
    });

    test('another wallet never adopts an interrupted import', () async {
      auth.failCreationOnce = true;
      await expectLater(import(name: 'First'), throwsStateError);
      final readsBefore = backend.readReasons.length;
      await import(name: 'Second', seed: _otherSeed);
      // The first wallet's credential is never read for the second import.
      expect(
        backend.readReasons.skip(readsBefore),
        isNot(contains('Continue creating your wallet')),
      );
      expect(auth.registrations.map((e) => e.id).toSet(), hasLength(2));
      expect(auth.registrations.last.name, 'Second');
      expect(auth.seeds[auth.registrations.last.id], _otherSeed);
    });

    test('a resumed engine wallet with another seed never opens', () async {
      auth.failCreationAfterCommitOnce = true;
      await expectLater(import(), throwsA(isA<WalletAccessException>()));
      final signOuts = auth.signOuts;
      await expectLater(
        import(seed: _otherSeed),
        throwsA(
          isA<WalletAccessException>().having(
            (e) => e.failure,
            'failure',
            WalletAccessFailure.invalidResponse,
          ),
        ),
      );
      expect(auth.signOuts, greaterThan(signOuts));
      expect(auth.active, isNull);
    });

    test('creation does not resume an interrupted import', () async {
      auth.failCreationOnce = true;
      await expectLater(import(), throwsStateError);
      final created = await service.createWallet(
        walletType: WalletType.hdwallet,
        initialMetadata: {},
      );
      expect(
        auth.seeds[WalletAccessService.entryId(created)],
        'generated '
        '${WalletAccessService.entryId(created)}',
      );
      expect(await storage.read(_pendingImportKey), isNotNull);
    });
  });
}
