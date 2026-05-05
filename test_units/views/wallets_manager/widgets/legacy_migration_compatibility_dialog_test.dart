// ignore_for_file: use_build_context_synchronously

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_legacy_wallet_migration/komodo_legacy_wallet_migration.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_secure_storage.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_wallet_metadata_store.dart';
import 'package:komodo_legacy_wallet_migration/src/adapters/legacy_wallet_platform.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_event.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/prepared_legacy_migration.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/views/wallets_manager/widgets/legacy_migration_compatibility_dialog.dart';

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      <String, dynamic>{};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LegacyMigrationCompatibilityContent', () {
    testWidgets(
      'shows only the target-name field when only name confirmation is required',
      (tester) async {
        final repository = await _createRepository();
        final settingsBloc = _FakeSettingsBloc();
        addTearDown(settingsBloc.close);

        await _pumpContent(
          tester,
          settingsBloc: settingsBloc,
          child: LegacyMigrationCompatibilityContent(
            walletsRepository: repository,
            migration: PreparedLegacyMigration(
              sourceWallet: _legacySourceWallet(name: 'Legacy Wallet!'),
              seedPhrase: 'seed',
              suggestedTargetWalletName: 'Legacy_Wallet_',
              requiresNameConfirmation: true,
              requiresNewKdfPassword: false,
            ),
          ),
        );

        expect(
          find.byKey(const Key('legacy-migration-wallet-name-field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('legacy-migration-password-fields')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'strict password validation ignores the weak-password setting',
      (tester) async {
        final repository = await _createRepository();
        final settingsBloc = _FakeSettingsBloc(weakPasswordsAllowed: true);
        addTearDown(settingsBloc.close);

        await _pumpContent(
          tester,
          settingsBloc: settingsBloc,
          child: LegacyMigrationCompatibilityContent(
            walletsRepository: repository,
            migration: PreparedLegacyMigration(
              sourceWallet: _legacySourceWallet(name: 'LegacyWallet'),
              seedPhrase: 'seed',
              suggestedTargetWalletName: 'LegacyWallet',
              requiresNameConfirmation: false,
              requiresNewKdfPassword: true,
            ),
          ),
        );

        expect(
          find.byKey(const Key('legacy-migration-wallet-name-field')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('legacy-migration-password-fields')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('create-password-field')),
          'weak',
        );
        await tester.enterText(
          find.byKey(const Key('create-password-field-confirm')),
          'weak',
        );
        await tester.pump();

        expect(_continueButton(tester).onPressed, isNull);

        await tester.enterText(
          find.byKey(const Key('create-password-field')),
          'Strong1!A',
        );
        await tester.enterText(
          find.byKey(const Key('create-password-field-confirm')),
          'Strong1!A',
        );
        await tester.pump();

        expect(_continueButton(tester).onPressed, isNotNull);
      },
    );

    testWidgets(
      'cancel dismisses the compatibility dialog without returning a migration result',
      (tester) async {
        final repository = await _createRepository();
        final settingsBloc = _FakeSettingsBloc();
        addTearDown(settingsBloc.close);

        await _pumpContent(
          tester,
          settingsBloc: settingsBloc,
          child: const SizedBox.shrink(),
        );

        final BuildContext context = tester.element(find.byType(Scaffold));
        final resultFuture = legacyMigrationCompatibilityDialog(
          context,
          walletsRepository: repository,
          migration: PreparedLegacyMigration(
            sourceWallet: _legacySourceWallet(name: 'Legacy Wallet!'),
            seedPhrase: 'seed',
            suggestedTargetWalletName: 'Legacy_Wallet_',
            requiresNameConfirmation: true,
            requiresNewKdfPassword: false,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(await resultFuture, isNull);
      },
    );
  });
}

Future<void> _pumpContent(
  WidgetTester tester, {
  required _FakeSettingsBloc settingsBloc,
  required Widget child,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const <Locale>[Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _EmptyAssetLoader(),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: BlocProvider<SettingsBloc>.value(
              value: settingsBloc,
              child: Scaffold(body: child),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

Future<WalletsRepository> _createRepository() async {
  final repository = WalletsRepository(
    _FakeSdk(),
    _FakeMm2Api(),
    _FakeStorage(),
    legacyNativeWalletMigration: KomodoLegacyWalletMigration(
      metadataStore: _EmptyMetadataStore(),
      secureStorage: _EmptySecureStorage(),
      platform: const _UnsupportedPlatform(),
    ),
  );
  await repository.getWallets();
  return repository;
}

Wallet _legacySourceWallet({required String name}) {
  return Wallet(
    id: 'legacy-1',
    name: name,
    config: WalletConfig(
      seedPhrase: '',
      activatedCoins: const <String>['KMD'],
      hasBackup: false,
      isLegacyWallet: true,
    ),
    legacySource: LegacyWalletSource(
      kind: LegacyWalletSourceKind.sharedPrefs,
      originalWalletName: name,
      originalWalletId: 'legacy-1',
    ),
  );
}

UiPrimaryButton _continueButton(WidgetTester tester) {
  return tester.widget<UiPrimaryButton>(find.byType(UiPrimaryButton));
}

class _FakeSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _FakeSettingsBloc({bool weakPasswordsAllowed = false})
    : super(
        SettingsState.fromStored(
          StoredSettings.initial().copyWith(
            weakPasswordsAllowed: weakPasswordsAllowed,
          ),
        ),
      );

  @override
  void add(SettingsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStorage implements BaseStorage {
  @override
  Future<bool> delete(String key) async => true;

  @override
  Future<dynamic> read(String key) async => null;

  @override
  Future<bool> write(String key, dynamic data) async => true;
}

class _FakeAuth implements KomodoDefiLocalAuth {
  @override
  Future<KdfUser?> get currentUser async => null;

  @override
  Future<List<KdfUser>> getUsers() async => const <KdfUser>[];

  @override
  Stream<KdfUser?> watchCurrentUser() => const Stream<KdfUser?>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeAuth missing: ${invocation.memberName}');
}

class _FakeSdk implements KomodoDefiSdk {
  @override
  KomodoDefiLocalAuth get auth => _auth;
  final KomodoDefiLocalAuth _auth = _FakeAuth();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeSdk missing: ${invocation.memberName}');
}

class _FakeMm2Api implements Mm2Api {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeMm2Api missing: ${invocation.memberName}');
}

class _EmptyMetadataStore implements LegacyWalletMetadataStore {
  @override
  Future<void> deleteWalletData({required String walletId}) async {}

  @override
  Future<List<LegacyWalletRecord>> listWallets() async =>
      const <LegacyWalletRecord>[];
}

class _EmptySecureStorage implements LegacySecureStorage {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;
}

class _UnsupportedPlatform implements LegacyWalletPlatform {
  const _UnsupportedPlatform();

  @override
  bool get isSupportedPlatform => false;
}
