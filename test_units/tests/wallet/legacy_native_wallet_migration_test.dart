import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_framework/komodo_defi_framework.dart';
import 'package:komodo_legacy_wallet_migration/komodo_legacy_wallet_migration.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_password_verifier.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_secure_storage.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_shared_preferences_store.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_wallet_metadata_store.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_wallet_platform.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_sdk/src/assets/asset_manager.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/settings/settings_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';

const _legacySeedPhrase =
    'abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon about';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WalletsRepository legacy migration', () {
    test(
      'getWallets hides linked legacy leftovers and prunes shared-preferences storage',
      () async {
        final storage = _FakeStorage(
          initialData: <String, dynamic>{
            'all-wallets': <Map<String, dynamic>>[
              await _sharedPrefsWalletJson(
                id: 'shared-1',
                name: 'Shared Wallet',
                password: 'Strong1!A',
              ),
              await _sharedPrefsWalletJson(
                id: 'shared-2',
                name: 'Still Legacy',
                password: 'Strong1!A',
              ),
            ],
          },
        );
        final auth = _FakeAuth(
          users: <KdfUser>[
            _buildUser(
              walletName: 'Shared_Wallet',
              derivationMethod: DerivationMethod.iguana,
              metadata: <String, dynamic>{
                legacySourceKindMetadataKey:
                    LegacyWalletSourceKind.sharedPrefs.name,
                legacySourceWalletIdMetadataKey: 'shared-1',
                legacySourceWalletNameMetadataKey: 'Shared Wallet',
                legacyCleanupStatusMetadataKey:
                    LegacyMigrationCleanupStatus.complete.name,
              },
            ),
            _buildUser(
              walletName: 'Native_Wallet_',
              derivationMethod: DerivationMethod.iguana,
              metadata: <String, dynamic>{
                legacySourceKindMetadataKey:
                    LegacyWalletSourceKind.nativeApp.name,
                legacySourceWalletIdMetadataKey: 'native-1',
                legacySourceWalletNameMetadataKey: 'Native Wallet!',
                legacyCleanupStatusMetadataKey:
                    LegacyMigrationCleanupStatus.incomplete.name,
              },
            ),
          ],
        );
        final repository = WalletsRepository(
          _FakeSdk(auth: auth),
          _FakeMm2Api(),
          storage,
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[
              LegacyWalletRecord(
                walletId: 'native-1',
                walletName: 'Native Wallet!',
              ),
              LegacyWalletRecord(
                walletId: 'native-2',
                walletName: 'Still Native',
              ),
            ],
          ),
        );

        final wallets = await repository.getWallets();
        final names = wallets.map((wallet) => wallet.name).toList();

        expect(
          names,
          containsAll(<String>[
            'Shared_Wallet',
            'Native_Wallet_',
            'Still Legacy',
            'Still Native',
          ]),
        );
        expect(names, isNot(contains('Shared Wallet')));
        expect(names, isNot(contains('Native Wallet!')));

        final storedWallets = (await storage.read('all-wallets') as List)
            .cast<Map<String, dynamic>>();
        expect(
          storedWallets.map((wallet) => wallet['id']),
          contains('shared-2'),
        );
        expect(
          storedWallets.map((wallet) => wallet['id']),
          isNot(contains('shared-1')),
        );
      },
    );

    test(
      'prepareLegacyMigration for shared-preferences wallet keeps compatible name and password',
      () async {
        final sourceWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-1',
          name: 'LegacyWallet',
          password: 'Strong1!A',
        );
        final repository = WalletsRepository(
          _FakeSdk(auth: _FakeAuth(users: const <KdfUser>[])),
          _FakeMm2Api(),
          _FakeStorage(
            initialData: <String, dynamic>{
              'all-wallets': <Map<String, dynamic>>[sourceWallet.toJson()],
            },
          ),
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[],
          ),
        );

        final listedWallet = (await repository.getWallets()).single;
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: listedWallet,
          legacyPassword: 'Strong1!A',
        );

        expect(prepared.seedPhrase, _legacySeedPhrase);
        expect(prepared.suggestedTargetWalletName, 'LegacyWallet');
        expect(prepared.requiresNameConfirmation, isFalse);
        expect(prepared.requiresNewKdfPassword, isFalse);
      },
    );

    test('prepareLegacyMigration for shared-preferences wallets includes '
        'legacy ZHTLC state and wallet extras', () async {
      final sourceWallet = await _buildSharedPrefsLegacyWallet(
        id: 'shared-z',
        name: 'LegacyWallet',
        password: 'Strong1!A',
        activatedCoins: const <String>['ARRR'],
      );
      final storage = _FakeStorage(
        initialData: <String, dynamic>{
          'all-wallets': <Map<String, dynamic>>[sourceWallet.toJson()],
          'z-coin-activation-requested-shared-z': <String>['ARRR'],
          'zhtlcSyncType': 'fullSync',
          'switch_pin': true,
          'isCamoEnabled': true,
          'disallowScreenshot': true,
        },
      );
      final repository = WalletsRepository(
        _FakeSdk(
          auth: _FakeAuth(users: const <KdfUser>[]),
          assets: <Asset>{_buildZhtlcAsset('ARRR')},
        ),
        _FakeMm2Api(),
        storage,
        legacyNativeWalletMigration: _createMigration(
          wallets: const <LegacyWalletRecord>[],
        ),
      );

      final listedWallet = (await repository.getWallets()).single;
      final prepared = await repository.prepareLegacyMigration(
        sourceWallet: listedWallet,
        legacyPassword: 'Strong1!A',
      );

      expect(prepared.requestedZhtlcCoinIds, <String>['ARRR']);
      expect(prepared.zhtlcSyncPolicy?.mode, ZhtlcRecurringSyncMode.earliest);
      expect(
        prepared.legacyWalletExtras,
        containsPair('activate_pin_protection', true),
      );
      expect(prepared.legacyWalletExtras, containsPair('enable_camo', true));
      expect(
        prepared.legacyWalletExtras,
        containsPair('disallow_screenshot', true),
      );
    });

    test(
      'prepareLegacyMigration flags incompatible name and weak password',
      () async {
        final sourceWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-1',
          name: 'Legacy Wallet!',
          password: 'weak',
        );
        final repository = WalletsRepository(
          _FakeSdk(auth: _FakeAuth(users: const <KdfUser>[])),
          _FakeMm2Api(),
          _FakeStorage(
            initialData: <String, dynamic>{
              'all-wallets': <Map<String, dynamic>>[sourceWallet.toJson()],
            },
          ),
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[],
          ),
        );

        final listedWallet = (await repository.getWallets()).single;
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: listedWallet,
          legacyPassword: 'weak',
        );

        expect(prepared.seedPhrase, _legacySeedPhrase);
        expect(prepared.suggestedTargetWalletName, 'Legacy_Wallet_');
        expect(prepared.requiresNameConfirmation, isTrue);
        expect(prepared.requiresNewKdfPassword, isTrue);
      },
    );

    test(
      'prepareLegacyMigration does not require new KDF password when weak passwords '
      'are allowed and legacy password is weak',
      () async {
        final sourceWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-1',
          name: 'LegacyWallet',
          password: 'weak',
        );
        final repository = WalletsRepository(
          _FakeSdk(auth: _FakeAuth(users: const <KdfUser>[])),
          _FakeMm2Api(),
          _FakeStorage(
            initialData: <String, dynamic>{
              'all-wallets': <Map<String, dynamic>>[sourceWallet.toJson()],
            },
          ),
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[],
          ),
        );

        final listedWallet = (await repository.getWallets()).single;
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: listedWallet,
          legacyPassword: 'weak',
          allowWeakPassword: true,
        );

        expect(prepared.requiresNewKdfPassword, isFalse);
      },
    );

    test(
      'prepareLegacyMigration for native legacy wallets keeps compatible name and password',
      () async {
        final repository = WalletsRepository(
          _FakeSdk(auth: _FakeAuth(users: const <KdfUser>[])),
          _FakeMm2Api(),
          _FakeStorage(),
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[
              LegacyWalletRecord(
                walletId: 'native-1',
                walletName: 'NativeWallet',
                activatedCoins: <String>['BTC'],
              ),
            ],
            secureValues: const <String, String>{
              'passwordKeyEncryption.SEEDNativeWalletnative-1': 'hash',
              'KeyEncryption.SEEDStrong1!ANativeWalletnative-1':
                  _legacySeedPhrase,
            },
          ),
        );

        final listedWallet = (await repository.getWallets()).single;
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: listedWallet,
          legacyPassword: 'Strong1!A',
        );

        expect(prepared.seedPhrase, _legacySeedPhrase);
        expect(prepared.nativeLegacySecrets, isNotNull);
        expect(prepared.suggestedTargetWalletName, 'NativeWallet');
        expect(prepared.requiresNameConfirmation, isFalse);
        expect(prepared.requiresNewKdfPassword, isFalse);
      },
    );

    test('prepareLegacyMigration for native legacy wallets includes requested '
        'ZHTLC assets, sync policy, and extras', () async {
      final repository = WalletsRepository(
        _FakeSdk(
          auth: _FakeAuth(users: const <KdfUser>[]),
          assets: <Asset>{_buildZhtlcAsset('ARRR')},
        ),
        _FakeMm2Api(),
        _FakeStorage(),
        legacyNativeWalletMigration: _createMigration(
          wallets: const <LegacyWalletRecord>[
            LegacyWalletRecord(
              walletId: 'native-1',
              walletName: 'NativeWallet',
              activatedCoins: <String>['ARRR'],
              walletExtras: <String, dynamic>{'activate_pin_protection': true},
            ),
          ],
          secureValues: const <String, String>{
            'passwordKeyEncryption.SEEDNativeWalletnative-1': 'hash',
            'KeyEncryption.SEEDStrong1!ANativeWalletnative-1':
                _legacySeedPhrase,
          },
          sharedPreferenceValues: const <String, Object?>{
            'z-coin-activation-requested-native-1': <String>['ARRR'],
            'zhtlcSyncType': 'newTransactions',
            'disallowScreenshot': true,
          },
        ),
      );

      final listedWallet = (await repository.getWallets()).single;
      final prepared = await repository.prepareLegacyMigration(
        sourceWallet: listedWallet,
        legacyPassword: 'Strong1!A',
      );

      expect(prepared.requestedZhtlcCoinIds, <String>['ARRR']);
      expect(
        prepared.zhtlcSyncPolicy?.mode,
        ZhtlcRecurringSyncMode.recentTransactions,
      );
      expect(
        prepared.legacyWalletExtras,
        containsPair('activate_pin_protection', true),
      );
      expect(
        prepared.legacyWalletExtras,
        containsPair('disallow_screenshot', true),
      );
    });

    test(
      'prepareLegacyMigration uses the unique sanitized target name without mutating the shared-preferences source wallet',
      () async {
        final sourceWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-1',
          name: 'Legacy Wallet!',
          password: 'Strong1!A',
        );
        final competingLegacyWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-2',
          name: 'Legacy_Wallet_',
          password: 'Strong1!A',
        );
        final storage = _FakeStorage(
          initialData: <String, dynamic>{
            'all-wallets': <Map<String, dynamic>>[
              sourceWallet.toJson(),
              competingLegacyWallet.toJson(),
            ],
          },
        );
        final repository = WalletsRepository(
          _FakeSdk(auth: _FakeAuth(users: const <KdfUser>[])),
          _FakeMm2Api(),
          storage,
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[],
          ),
        );

        final listedWallet = (await repository.getWallets()).firstWhere(
          (wallet) => wallet.name == 'Legacy Wallet!',
        );
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: listedWallet,
          legacyPassword: 'Strong1!A',
        );

        expect(prepared.suggestedTargetWalletName, 'Legacy_Wallet__1');
        expect(prepared.requiresNameConfirmation, isTrue);
        expect(prepared.requiresNewKdfPassword, isFalse);

        final storedWallets = (await storage.read('all-wallets') as List)
            .cast<Map<String, dynamic>>();
        final storedSourceWallet = storedWallets.firstWhere(
          (wallet) => wallet['id'] == 'shared-1',
        );
        expect(storedSourceWallet['name'], 'Legacy Wallet!');
      },
    );

    test(
      'prepareLegacyMigration requires a new KDF password for legacy passwords that exceed the KDF maximum length',
      () async {
        final longPassword = _tooLongLegacyPassword();
        final sourceWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-1',
          name: 'LegacyWallet',
          password: longPassword,
        );
        final repository = WalletsRepository(
          _FakeSdk(auth: _FakeAuth(users: const <KdfUser>[])),
          _FakeMm2Api(),
          _FakeStorage(
            initialData: <String, dynamic>{
              'all-wallets': <Map<String, dynamic>>[sourceWallet.toJson()],
            },
          ),
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[],
          ),
        );

        final listedWallet = (await repository.getWallets()).single;
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: listedWallet,
          legacyPassword: longPassword,
        );

        expect(prepared.seedPhrase, _legacySeedPhrase);
        expect(prepared.requiresNewKdfPassword, isTrue);
        expect(prepared.requiresNameConfirmation, isFalse);

        final preparedAllowWeak = await repository.prepareLegacyMigration(
          sourceWallet: listedWallet,
          legacyPassword: longPassword,
          allowWeakPassword: true,
        );
        expect(preparedAllowWeak.requiresNewKdfPassword, isTrue);
      },
    );

    test(
      'validateLegacyMigrationTargetName allows spaces and hyphens like new wallet names',
      () async {
        final sourceWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-1',
          name: 'Legacy Wallet!',
          password: 'Strong1!A',
        );
        final repository = WalletsRepository(
          _FakeSdk(auth: _FakeAuth(users: const <KdfUser>[])),
          _FakeMm2Api(),
          _FakeStorage(
            initialData: <String, dynamic>{
              'all-wallets': <Map<String, dynamic>>[sourceWallet.toJson()],
            },
          ),
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[],
          ),
        );

        final listedWallet = (await repository.getWallets()).single;
        expect(
          repository.validateLegacyMigrationTargetName(
            name: 'My KDF Wallet',
            sourceWallet: listedWallet,
          ),
          isNull,
        );
        expect(
          repository.validateLegacyMigrationTargetName(
            name: 'My-KDF-Wallet',
            sourceWallet: listedWallet,
          ),
          isNull,
        );
      },
    );

    test(
      'prepareLegacyMigration short-circuits to an already migrated wallet before seed access',
      () async {
        final sourceWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-1',
          name: 'Legacy Wallet!',
          password: 'legacy-pass',
        );
        final storage = _FakeStorage(
          initialData: <String, dynamic>{
            'all-wallets': <Map<String, dynamic>>[sourceWallet.toJson()],
          },
        );
        final repository = WalletsRepository(
          _FakeSdk(
            auth: _FakeAuth(
              users: <KdfUser>[
                _buildUser(
                  walletName: 'Legacy_Wallet_',
                  derivationMethod: DerivationMethod.iguana,
                  metadata: <String, dynamic>{
                    legacySourceKindMetadataKey:
                        LegacyWalletSourceKind.sharedPrefs.name,
                    legacySourceWalletIdMetadataKey: 'shared-1',
                    legacySourceWalletNameMetadataKey: 'Legacy Wallet!',
                    legacyCleanupStatusMetadataKey:
                        LegacyMigrationCleanupStatus.complete.name,
                  },
                ),
              ],
            ),
          ),
          _FakeMm2Api(),
          storage,
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[],
          ),
        );

        await expectLater(
          repository.prepareLegacyMigration(
            sourceWallet: sourceWallet,
            legacyPassword: 'wrong-password',
          ),
          throwsA(
            isA<AuthException>()
                .having(
                  (e) => e.type,
                  'type',
                  AuthExceptionType.legacyWalletAlreadyMigrated,
                )
                .having(
                  (e) => e.details?['migratedWalletName'],
                  'migratedWalletName',
                  'Legacy_Wallet_',
                ),
          ),
        );
      },
    );

    test(
      'prepareLegacyMigration resolves sanitized-name collisions with unrelated SDK wallets instead of reporting already migrated',
      () async {
        final sourceWallet = await _buildSharedPrefsLegacyWallet(
          id: 'shared-1',
          name: 'Legacy Wallet!',
          password: 'weak',
        );
        final storage = _FakeStorage(
          initialData: <String, dynamic>{
            'all-wallets': <Map<String, dynamic>>[sourceWallet.toJson()],
          },
        );
        final repository = WalletsRepository(
          _FakeSdk(
            auth: _FakeAuth(
              users: <KdfUser>[
                _buildUser(
                  walletName: 'Legacy_Wallet_',
                  derivationMethod: DerivationMethod.iguana,
                ),
              ],
            ),
          ),
          _FakeMm2Api(),
          storage,
          legacyNativeWalletMigration: _createMigration(
            wallets: const <LegacyWalletRecord>[],
          ),
        );

        final listedWallet = (await repository.getWallets()).firstWhere(
          (wallet) => wallet.name == 'Legacy Wallet!',
        );
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: listedWallet,
          legacyPassword: 'weak',
        );

        expect(prepared.suggestedTargetWalletName, 'Legacy_Wallet__1');
        expect(prepared.requiresNameConfirmation, isTrue);
        expect(prepared.requiresNewKdfPassword, isTrue);
        expect(prepared.seedPhrase, _legacySeedPhrase);
      },
    );
  });

  group('AuthBloc legacy migration', () {
    test(
      'legacy migration registers with the KDF password and stores migrated metadata',
      () async {
        final auth = _FakeAuth(users: const <KdfUser>[]);
        final metadataStore = _FakeMetadataStore(
          wallets: const <LegacyWalletRecord>[
            LegacyWalletRecord(
              walletId: 'native-1',
              walletName: 'Legacy Wallet!',
              activatedCoins: <String>['BTC'],
            ),
          ],
        );
        final secureStorage = _FakeSecureStorage(
          initialValues: <String, String>{
            'passwordKeyEncryption.SEEDLegacy Wallet!native-1': 'hash',
            'KeyEncryption.SEEDweakLegacy Wallet!native-1': _legacySeedPhrase,
          },
        );
        final repository = WalletsRepository(
          _FakeSdk(auth: auth),
          _FakeMm2Api(),
          _FakeStorage(),
          legacyNativeWalletMigration: KomodoLegacyWalletMigration(
            metadataStore: metadataStore,
            secureStorage: secureStorage,
            sharedPreferencesStore: _FakeSharedPreferencesStore(),
            passwordVerifier: const _AlwaysValidPasswordVerifier(),
            platform: const _FakePlatform(),
          ),
        );
        final bloc = AuthBloc(
          _FakeSdk(auth: auth),
          repository,
          SettingsRepository(storage: _FakeStorage()),
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        final sourceWallet = _nativeLegacyWallet();
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: sourceWallet,
          legacyPassword: 'weak',
        );

        final terminalStateFuture = bloc.stream.firstWhere(
          (state) => state.mode == AuthorizeMode.logIn || state.isError,
        );
        bloc.add(
          AuthLegacyMigrationRequested(
            sourceWallet: sourceWallet,
            legacyPassword: 'weak',
            kdfPassword: 'Strong1!A',
            targetWalletName: prepared.suggestedTargetWalletName,
            seedPhrase: prepared.seedPhrase,
            legacyNativeSecrets: prepared.nativeLegacySecrets,
          ),
        );
        final terminalState = await terminalStateFuture;

        expect(terminalState.isError, isFalse);
        expect(auth.registeredWalletName, 'Legacy_Wallet_');
        expect(auth.registeredPassword, 'Strong1!A');
        expect(secureStorage.readCalls, <String>[
          'KeyEncryption.SEEDweakLegacy Wallet!native-1',
        ]);
        expect(
          terminalState
              .currentUser
              ?.wallet
              .migratedLegacySource
              ?.originalWalletId,
          'native-1',
        );
        expect(
          terminalState.currentUser?.wallet.migratedLegacySource?.cleanupStatus,
          LegacyMigrationCleanupStatus.complete,
        );
        expect(metadataStore.deletedWalletIds, contains('native-1'));
      },
    );

    test(
      'legacy migration uses the confirmed target wallet name instead of the legacy source name',
      () async {
        final auth = _FakeAuth(users: const <KdfUser>[]);
        final bloc = AuthBloc(
          _FakeSdk(auth: auth),
          WalletsRepository(
            _FakeSdk(auth: auth),
            _FakeMm2Api(),
            _FakeStorage(),
          ),
          SettingsRepository(storage: _FakeStorage()),
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        final terminalStateFuture = bloc.stream.firstWhere(
          (state) => state.mode == AuthorizeMode.logIn || state.isError,
        );
        bloc.add(
          AuthLegacyMigrationRequested(
            sourceWallet: _sharedPrefsLegacyWallet(),
            legacyPassword: 'Strong1!A',
            kdfPassword: 'Strong1!A',
            targetWalletName: 'Legacy_Wallet__1',
            seedPhrase: _legacySeedPhrase,
          ),
        );
        final terminalState = await terminalStateFuture;

        expect(terminalState.isError, isFalse);
        expect(auth.registeredWalletName, 'Legacy_Wallet__1');
        expect(
          terminalState
              .currentUser
              ?.wallet
              .migratedLegacySource
              ?.originalWalletName,
          'Legacy Wallet!',
        );
      },
    );

    test(
      'legacy migration signs in to an existing target wallet when the same password can be reused',
      () async {
        final auth = _FakeAuth(
          users: <KdfUser>[
            _buildUser(
              walletName: 'Legacy_Wallet_',
              derivationMethod: DerivationMethod.iguana,
            ),
          ],
        );
        final bloc = AuthBloc(
          _FakeSdk(auth: auth),
          WalletsRepository(
            _FakeSdk(auth: auth),
            _FakeMm2Api(),
            _FakeStorage(),
          ),
          SettingsRepository(storage: _FakeStorage()),
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        final terminalStateFuture = bloc.stream.firstWhere(
          (state) => state.mode == AuthorizeMode.logIn || state.isError,
        );
        bloc.add(
          AuthLegacyMigrationRequested(
            sourceWallet: _sharedPrefsLegacyWallet(),
            legacyPassword: 'Strong1!A',
            kdfPassword: 'Strong1!A',
            targetWalletName: 'Legacy_Wallet_',
            seedPhrase: _legacySeedPhrase,
          ),
        );
        final terminalState = await terminalStateFuture;

        expect(terminalState.isError, isFalse);
        expect(auth.registeredWalletName, isNull);
        expect(auth.signedInWalletName, 'Legacy_Wallet_');
      },
    );

    test(
      'legacy migration refuses to sign in to an existing target wallet with the legacy password when a new KDF password is required',
      () async {
        final auth = _FakeAuth(
          users: <KdfUser>[
            _buildUser(
              walletName: 'Legacy_Wallet_',
              derivationMethod: DerivationMethod.iguana,
            ),
          ],
        );
        final bloc = AuthBloc(
          _FakeSdk(auth: auth),
          WalletsRepository(
            _FakeSdk(auth: auth),
            _FakeMm2Api(),
            _FakeStorage(),
          ),
          SettingsRepository(storage: _FakeStorage()),
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        final terminalStateFuture = bloc.stream.firstWhere(
          (state) => state.mode == AuthorizeMode.logIn || state.isError,
        );
        bloc.add(
          AuthLegacyMigrationRequested(
            sourceWallet: _sharedPrefsLegacyWallet(),
            legacyPassword: 'weak',
            kdfPassword: 'Strong1!A',
            targetWalletName: 'Legacy_Wallet_',
            seedPhrase: _legacySeedPhrase,
          ),
        );
        final terminalState = await terminalStateFuture;

        expect(terminalState.isError, isTrue);
        expect(
          terminalState.authError?.message,
          contains('already been migrated'),
        );
        expect(auth.registeredWalletName, isNull);
        expect(auth.signedInWalletName, isNull);
      },
    );

    test('legacy migration saves ZHTLC activation config and preserved extras '
        'before auto-activation', () async {
      final auth = _FakeAuth(users: const <KdfUser>[]);
      final sdk = _FakeSdk(
        auth: auth,
        assets: <Asset>{_buildZhtlcAsset('ARRR')},
      );
      final storage = _FakeStorage(
        initialData: <String, dynamic>{
          'all-wallets': <Map<String, dynamic>>[
            (await _buildSharedPrefsLegacyWallet(
              id: 'shared-z',
              name: 'LegacyWallet',
              password: 'Strong1!A',
              activatedCoins: const <String>['ARRR'],
            )).toJson(),
          ],
          'z-coin-activation-requested-shared-z': <String>['ARRR'],
          'zhtlcSyncType': 'fullSync',
          'switch_pin': true,
        },
      );
      final repository = WalletsRepository(
        sdk,
        _FakeMm2Api(),
        storage,
        zcashParamsDownloaderFactory: () => _FakeZcashParamsDownloader(
          paramsAvailable: true,
          paramsPath: '/zcash-params',
        ),
      );
      final bloc = AuthBloc(
        sdk,
        repository,
        SettingsRepository(storage: _FakeStorage()),
        _FakeTradingStatusService(),
      );
      addTearDown(bloc.close);

      final sourceWallet = (await repository.getWallets()).single;
      final prepared = await repository.prepareLegacyMigration(
        sourceWallet: sourceWallet,
        legacyPassword: 'Strong1!A',
      );

      final terminalStateFuture = bloc.stream.firstWhere(
        (state) => state.mode == AuthorizeMode.logIn || state.isError,
      );
      bloc.add(
        AuthLegacyMigrationRequested(
          sourceWallet: sourceWallet,
          legacyPassword: 'Strong1!A',
          kdfPassword: 'Strong1!A',
          targetWalletName: prepared.suggestedTargetWalletName,
          seedPhrase: prepared.seedPhrase,
          requestedZhtlcCoinIds: prepared.requestedZhtlcCoinIds,
          zhtlcSyncPolicy: prepared.zhtlcSyncPolicy,
          legacyWalletExtras: prepared.legacyWalletExtras,
        ),
      );
      final terminalState = await terminalStateFuture;
      final savedConfig = await sdk.activationConfigService.getSavedZhtlc(
        _buildZhtlcAsset('ARRR').id,
      );
      final oneShotSync = await sdk.activationConfigService
          .takeOneShotSyncParams(_buildZhtlcAsset('ARRR').id);
      final consumedOneShot = await sdk.activationConfigService
          .takeOneShotSyncParams(_buildZhtlcAsset('ARRR').id);

      expect(terminalState.isError, isFalse);
      expect(savedConfig, isNotNull);
      expect(savedConfig?.zcashParamsPath, '/zcash-params');
      expect(
        savedConfig?.recurringSyncPolicy?.mode,
        ZhtlcRecurringSyncMode.earliest,
      );
      expect(oneShotSync?.isEarliest, isTrue);
      expect(consumedOneShot, isNull);
      expect(
        terminalState.currentUser?.metadata[legacyWalletExtrasMetadataKey],
        containsPair('activate_pin_protection', true),
      );
      expect(
        terminalState.currentUser?.metadata[legacyWalletExtrasMetadataKey],
        containsPair('requested_zhtlc_coin_ids', <String>['ARRR']),
      );
      expect(
        terminalState.currentUser?.metadata['activated_coins'],
        contains('ARRR'),
      );
    });

    test(
      'legacy migration keeps the wallet signed in and records pending ZHTLC '
      'state when params download fails',
      () async {
        final auth = _FakeAuth(users: const <KdfUser>[]);
        final sdk = _FakeSdk(
          auth: auth,
          assets: <Asset>{_buildZhtlcAsset('ARRR')},
        );
        final storage = _FakeStorage(
          initialData: <String, dynamic>{
            'all-wallets': <Map<String, dynamic>>[
              (await _buildSharedPrefsLegacyWallet(
                id: 'shared-z',
                name: 'LegacyWallet',
                password: 'Strong1!A',
                activatedCoins: const <String>['ARRR'],
              )).toJson(),
            ],
            'z-coin-activation-requested-shared-z': <String>['ARRR'],
            'zhtlcSyncType': 'newTransactions',
          },
        );
        final repository = WalletsRepository(
          sdk,
          _FakeMm2Api(),
          storage,
          zcashParamsDownloaderFactory: () =>
              _FakeZcashParamsDownloader(paramsAvailable: false),
        );
        final bloc = AuthBloc(
          sdk,
          repository,
          SettingsRepository(storage: _FakeStorage()),
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        final sourceWallet = (await repository.getWallets()).single;
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: sourceWallet,
          legacyPassword: 'Strong1!A',
        );

        final terminalStateFuture = bloc.stream.firstWhere(
          (state) => state.mode == AuthorizeMode.logIn || state.isError,
        );
        bloc.add(
          AuthLegacyMigrationRequested(
            sourceWallet: sourceWallet,
            legacyPassword: 'Strong1!A',
            kdfPassword: 'Strong1!A',
            targetWalletName: prepared.suggestedTargetWalletName,
            seedPhrase: prepared.seedPhrase,
            requestedZhtlcCoinIds: prepared.requestedZhtlcCoinIds,
            zhtlcSyncPolicy: prepared.zhtlcSyncPolicy,
            legacyWalletExtras: prepared.legacyWalletExtras,
          ),
        );
        final terminalState = await terminalStateFuture;
        final savedConfig = await sdk.activationConfigService.getSavedZhtlc(
          _buildZhtlcAsset('ARRR').id,
        );

        expect(terminalState.isError, isFalse);
        expect(
          terminalState.authenticationState?.message,
          contains('ZHTLC assets still need Zcash parameters'),
        );
        expect(savedConfig, isNull);
        expect(
          terminalState.currentUser?.metadata['activated_coins'],
          isNot(contains('ARRR')),
        );
        expect(
          terminalState.currentUser?.metadata[legacyWalletExtrasMetadataKey],
          containsPair('pending_zhtlc_assets', <String>['ARRR']),
        );
      },
    );

    test(
      'partial native cleanup keeps the migrated wallet logged in, marks cleanup incomplete, and hides the legacy source on reload',
      () async {
        final auth = _FakeAuth(users: const <KdfUser>[]);
        final metadataStore = _FakeMetadataStore(
          wallets: const <LegacyWalletRecord>[
            LegacyWalletRecord(
              walletId: 'native-1',
              walletName: 'Legacy Wallet!',
              activatedCoins: <String>['BTC'],
              isCurrentWallet: true,
            ),
          ],
        );
        final secureStorage = _FakeSecureStorage(
          initialValues: <String, String>{
            'passwordKeyEncryption.SEEDLegacy Wallet!native-1': 'hash',
            'KeyEncryption.SEEDweakLegacy Wallet!native-1': _legacySeedPhrase,
          },
          keysThatFailDeletion: <String>{'passphrase'},
        );
        final sdk = _FakeSdk(auth: auth);
        final repository = WalletsRepository(
          sdk,
          _FakeMm2Api(),
          _FakeStorage(),
          legacyNativeWalletMigration: KomodoLegacyWalletMigration(
            metadataStore: metadataStore,
            secureStorage: secureStorage,
            sharedPreferencesStore: _FakeSharedPreferencesStore(),
            passwordVerifier: const _AlwaysValidPasswordVerifier(),
            platform: const _FakePlatform(),
          ),
        );
        final bloc = AuthBloc(
          sdk,
          repository,
          SettingsRepository(storage: _FakeStorage()),
          _FakeTradingStatusService(),
        );
        addTearDown(bloc.close);

        final sourceWallet = _nativeLegacyWallet();
        final prepared = await repository.prepareLegacyMigration(
          sourceWallet: sourceWallet,
          legacyPassword: 'weak',
        );

        final terminalStateFuture = bloc.stream.firstWhere(
          (state) => state.mode == AuthorizeMode.logIn || state.isError,
        );
        bloc.add(
          AuthLegacyMigrationRequested(
            sourceWallet: sourceWallet,
            legacyPassword: 'weak',
            kdfPassword: 'Strong1!A',
            targetWalletName: prepared.suggestedTargetWalletName,
            seedPhrase: prepared.seedPhrase,
            legacyNativeSecrets: prepared.nativeLegacySecrets,
          ),
        );
        final terminalState = await terminalStateFuture;

        expect(terminalState.isError, isFalse);
        expect(terminalState.authenticationState?.message, isNull);
        expect(
          terminalState.currentUser?.wallet.hasIncompleteNativeLegacyCleanup,
          isTrue,
        );

        final wallets = await repository.getWallets();
        expect(
          wallets.map((wallet) => wallet.name),
          contains('Legacy_Wallet_'),
        );
        expect(
          wallets.map((wallet) => wallet.name),
          isNot(contains('Legacy Wallet!')),
        );
      },
    );
  });
}

Wallet _sharedPrefsLegacyWallet() {
  return Wallet(
    id: 'shared-1',
    name: 'Legacy Wallet!',
    config: WalletConfig(
      seedPhrase: '',
      activatedCoins: const <String>['KMD'],
      hasBackup: false,
      isLegacyWallet: true,
    ),
    legacySource: const LegacyWalletSource(
      kind: LegacyWalletSourceKind.sharedPrefs,
      originalWalletName: 'Legacy Wallet!',
      originalWalletId: 'shared-1',
    ),
  );
}

Wallet _nativeLegacyWallet() {
  return Wallet(
    id: 'native-1',
    name: 'Legacy Wallet!',
    config: WalletConfig(
      seedPhrase: '',
      activatedCoins: const <String>['BTC'],
      hasBackup: false,
      isLegacyWallet: true,
    ),
    legacySource: const LegacyWalletSource(
      kind: LegacyWalletSourceKind.nativeApp,
      originalWalletName: 'Legacy Wallet!',
      originalWalletId: 'native-1',
    ),
  );
}

String _tooLongLegacyPassword() {
  return 'Aa1!${'a' * 125}';
}

Future<Wallet> _buildSharedPrefsLegacyWallet({
  required String id,
  required String name,
  required String password,
  List<String> activatedCoins = const <String>['KMD'],
}) async {
  final encryptedSeed = await EncryptionTool().encryptData(
    password,
    _legacySeedPhrase,
  );
  return Wallet(
    id: id,
    name: name,
    config: WalletConfig(
      seedPhrase: encryptedSeed,
      activatedCoins: activatedCoins,
      hasBackup: false,
      isLegacyWallet: true,
    ),
    legacySource: LegacyWalletSource(
      kind: LegacyWalletSourceKind.sharedPrefs,
      originalWalletName: name,
      originalWalletId: id,
    ),
  );
}

Future<Map<String, dynamic>> _sharedPrefsWalletJson({
  required String id,
  required String name,
  required String password,
  List<String> activatedCoins = const <String>['KMD'],
}) async {
  final wallet = await _buildSharedPrefsLegacyWallet(
    id: id,
    name: name,
    password: password,
    activatedCoins: activatedCoins,
  );
  return wallet.toJson();
}

KomodoLegacyWalletMigration _createMigration({
  required List<LegacyWalletRecord> wallets,
  Map<String, String> secureValues = const <String, String>{},
  Map<String, Object?> sharedPreferenceValues = const <String, Object?>{},
}) {
  return KomodoLegacyWalletMigration(
    metadataStore: _FakeMetadataStore(wallets: wallets),
    secureStorage: _FakeSecureStorage(initialValues: secureValues),
    sharedPreferencesStore: _FakeSharedPreferencesStore(
      initialValues: sharedPreferenceValues,
    ),
    passwordVerifier: const _AlwaysValidPasswordVerifier(),
    platform: const _FakePlatform(),
  );
}

KdfUser _buildUser({
  required String walletName,
  required DerivationMethod derivationMethod,
  Map<String, dynamic> metadata = const <String, dynamic>{},
}) {
  return KdfUser(
    walletId: WalletId.fromName(
      walletName,
      AuthOptions(derivationMethod: derivationMethod),
    ),
    isBip39Seed: derivationMethod == DerivationMethod.hdWallet,
    metadata: <String, dynamic>{'activated_coins': <String>[], ...metadata},
  );
}

class _FakeStorage implements BaseStorage {
  _FakeStorage({Map<String, dynamic>? initialData})
    : _values = initialData ?? <String, dynamic>{};

  final Map<String, dynamic> _values;

  @override
  Future<bool> delete(String key) async {
    _values.remove(key);
    return true;
  }

  @override
  Future<dynamic> read(String key) async => _values[key];

  @override
  Future<bool> write(String key, dynamic data) async {
    _values[key] = data;
    return true;
  }
}

class _FakeMetadataStore implements LegacyWalletMetadataStore {
  _FakeMetadataStore({required List<LegacyWalletRecord> wallets})
    : wallets = List<LegacyWalletRecord>.from(wallets);

  final List<LegacyWalletRecord> wallets;
  final List<String> deletedWalletIds = <String>[];

  @override
  Future<void> deleteWalletData({required String walletId}) async {
    deletedWalletIds.add(walletId);
    wallets.removeWhere((wallet) => wallet.walletId == walletId);
  }

  @override
  Future<List<LegacyWalletRecord>> listWallets() async => wallets;
}

class _FakeSecureStorage implements LegacySecureStorage {
  _FakeSecureStorage({
    Map<String, String>? initialValues,
    Set<String>? keysThatFailDeletion,
  }) : _values = initialValues ?? <String, String>{},
       _keysThatFailDeletion = keysThatFailDeletion ?? <String>{};

  final Map<String, String> _values;
  final Set<String> _keysThatFailDeletion;
  final List<String> readCalls = <String>[];

  @override
  Future<void> delete(String key) async {
    if (_keysThatFailDeletion.contains(key)) {
      throw StateError('delete failed for $key');
    }
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    readCalls.add(key);
    return _values[key];
  }
}

class _AlwaysValidPasswordVerifier implements LegacyPasswordVerifier {
  const _AlwaysValidPasswordVerifier();

  @override
  Future<bool> verifySeedPassword({
    required String password,
    required String encodedHash,
  }) async => true;
}

class _FakePlatform implements LegacyWalletPlatform {
  const _FakePlatform();

  @override
  bool get isSupportedPlatform => true;
}

class _FakeSharedPreferencesStore implements LegacySharedPreferencesStore {
  _FakeSharedPreferencesStore({
    Map<String, Object?>? initialValues,
    Set<String>? keysThatFailDeletion,
  }) : _values = initialValues ?? <String, Object?>{},
       _keysThatFailDeletion = keysThatFailDeletion ?? <String>{};

  final Map<String, Object?> _values;
  final Set<String> _keysThatFailDeletion;

  @override
  Future<void> delete(String key) async {
    if (_keysThatFailDeletion.contains(key)) {
      throw StateError('delete failed for $key');
    }
    _values.remove(key);
  }

  @override
  Future<Object?> read(String key) async => _values[key];
}

class _FakeAuth implements KomodoDefiLocalAuth {
  _FakeAuth({required List<KdfUser> users}) : users = List<KdfUser>.from(users);

  final List<KdfUser> users;
  KdfUser? currentUserValue;
  String? registeredWalletName;
  String? registeredPassword;
  Mnemonic? registeredMnemonic;
  AuthOptions? registeredOptions;
  String? signedInWalletName;
  String? signedInPassword;
  AuthOptions? signedInOptions;

  @override
  Future<KdfUser?> get currentUser async => currentUserValue;

  @override
  Future<List<KdfUser>> getUsers() async => users;

  @override
  Future<KdfUser> register({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
    Mnemonic? mnemonic,
  }) async {
    registeredWalletName = walletName;
    registeredPassword = password;
    registeredMnemonic = mnemonic;
    registeredOptions = options;
    currentUserValue = _buildUser(
      walletName: walletName,
      derivationMethod: options.derivationMethod,
    );
    _upsertCurrentUser(currentUserValue!);
    return currentUserValue!;
  }

  @override
  Future<KdfUser> signIn({
    required String walletName,
    required String password,
    AuthOptions options = const AuthOptions(
      derivationMethod: DerivationMethod.hdWallet,
    ),
  }) async {
    signedInWalletName = walletName;
    signedInPassword = password;
    signedInOptions = options;
    currentUserValue =
        users.where((user) => user.walletId.name == walletName).firstOrNull ??
        _buildUser(
          walletName: walletName,
          derivationMethod: options.derivationMethod,
        );
    _upsertCurrentUser(currentUserValue!);
    return currentUserValue!;
  }

  @override
  Future<void> setOrRemoveActiveUserKeyValue(String key, dynamic value) async {
    final currentUser = currentUserValue;
    if (currentUser == null) {
      throw StateError('No active user');
    }

    final metadata = Map<String, dynamic>.from(currentUser.metadata);
    if (value == null) {
      metadata.remove(key);
    } else {
      metadata[key] = value;
    }

    currentUserValue = currentUser.copyWith(metadata: metadata);
    _upsertCurrentUser(currentUserValue!);
  }

  @override
  Future<void> updateActiveUserKeyValue(
    String key,
    dynamic Function(dynamic currentValue) transform,
  ) async {
    final currentUser = currentUserValue;
    if (currentUser == null) {
      throw StateError('No active user');
    }

    final metadata = Map<String, dynamic>.from(currentUser.metadata);
    final updatedValue = transform(metadata[key]);
    if (updatedValue == null) {
      metadata.remove(key);
    } else {
      metadata[key] = updatedValue;
    }

    currentUserValue = currentUser.copyWith(metadata: metadata);
    _upsertCurrentUser(currentUserValue!);
  }

  void _upsertCurrentUser(KdfUser user) {
    final index = users.indexWhere(
      (candidate) => candidate.walletId.name == user.walletId.name,
    );
    if (index == -1) {
      users.add(user);
    } else {
      users[index] = user;
    }
  }

  @override
  Stream<KdfUser?> watchCurrentUser() => const Stream<KdfUser?>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeAuth missing: ${invocation.memberName}');
}

class _FakeAssetManager implements AssetManager {
  _FakeAssetManager(Set<Asset> assets) : _assets = assets;

  final Set<Asset> _assets;

  @override
  Set<Asset> findAssetsByConfigId(String ticker) =>
      _assets.where((asset) => asset.id.id == ticker).toSet();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_FakeAssetManager missing: ${invocation.memberName}',
  );
}

class _FakeStreamingManager implements KdfEventStreamingService {
  @override
  void connectIfNeeded() {}

  @override
  void disconnect() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_FakeStreamingManager missing: ${invocation.memberName}',
  );
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk({required this.auth, Set<Asset> assets = const <Asset>{}})
    : _assets = _FakeAssetManager(assets),
      activationConfigService = ActivationConfigService(
        JsonActivationConfigRepository(InMemoryKeyValueStore()),
        walletIdResolver: () async => (await auth.currentUser)?.walletId,
      );

  @override
  final KomodoDefiLocalAuth auth;

  @override
  final ActivationConfigService activationConfigService;

  @override
  AssetManager get assets => _assets;
  final AssetManager _assets;

  @override
  KdfEventStreamingService get streaming => _streaming;
  final KdfEventStreamingService _streaming = _FakeStreamingManager();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeSdk missing: ${invocation.memberName}');
}

class _FakeMm2Api implements Mm2Api {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeMm2Api missing: ${invocation.memberName}');
}

class _FakeTradingStatusService implements TradingStatusService {
  @override
  bool isAssetBlocked(AssetId assetId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '_FakeTradingStatusService missing: ${invocation.memberName}',
  );
}

class _FakeZcashParamsDownloader extends ZcashParamsDownloader {
  _FakeZcashParamsDownloader({required this.paramsAvailable, this.paramsPath})
    : super();

  final bool paramsAvailable;
  final String? paramsPath;

  @override
  Future<bool> areParamsAvailable() async => paramsAvailable;

  @override
  Future<bool> cancelDownload() async => true;

  @override
  Future<bool> clearParams() async => true;

  @override
  Future<DownloadResult> downloadParams() async {
    if (paramsPath == null) {
      return const DownloadResult.failure(error: 'download failed');
    }
    return DownloadResult.success(paramsPath: paramsPath!);
  }

  @override
  Stream<DownloadProgress> get downloadProgress =>
      const Stream<DownloadProgress>.empty();

  @override
  void dispose() {}

  @override
  Future<String?> getFileHash(String filePath) async => null;

  @override
  Future<String?> getParamsPath() async => paramsPath;

  @override
  Future<bool> validateFileHash(String filePath, String expectedHash) async =>
      true;

  @override
  Future<bool> validateParams() async => true;
}

Asset _buildZhtlcAsset(String coinId) {
  return Asset.fromJson(<String, dynamic>{
    'coin': coinId,
    'fname': coinId,
    'chain_id': 1,
    'type': 'ZHTLC',
    'light_wallet_d_servers': <Map<String, dynamic>>[],
  });
}
