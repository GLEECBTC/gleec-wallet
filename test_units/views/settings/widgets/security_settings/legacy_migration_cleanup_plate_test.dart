import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/settings/widgets/security_settings/legacy_migration_cleanup_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      <String, dynamic>{};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LegacyMigrationCleanupPlate', () {
    testWidgets(
      'shows the cleanup warning only for wallets with incomplete native legacy cleanup',
      (tester) async {
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(
            _buildUserWithLegacyCleanupStatus(
              LegacyWalletSourceKind.nativeApp,
              LegacyMigrationCleanupStatus.incomplete,
            ),
          ),
        );
        addTearDown(authBloc.close);

        await _pumpPlate(tester, authBloc: authBloc);

        expect(find.byType(SecurityActionPlate), findsOneWidget);
      },
    );

    testWidgets('stays hidden for non-native migrated wallets', (tester) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(
          _buildUserWithLegacyCleanupStatus(
            LegacyWalletSourceKind.sharedPrefs,
            LegacyMigrationCleanupStatus.incomplete,
          ),
        ),
      );
      addTearDown(authBloc.close);

      await _pumpPlate(tester, authBloc: authBloc);

      expect(find.byType(SecurityActionPlate), findsNothing);
    });

    testWidgets('stays hidden when native legacy cleanup is complete', (
      tester,
    ) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(
          _buildUserWithLegacyCleanupStatus(
            LegacyWalletSourceKind.nativeApp,
            LegacyMigrationCleanupStatus.complete,
          ),
        ),
      );
      addTearDown(authBloc.close);

      await _pumpPlate(tester, authBloc: authBloc);

      expect(find.byType(SecurityActionPlate), findsNothing);
    });
  });
}

Future<void> _pumpPlate(
  WidgetTester tester, {
  required _FakeAuthBloc authBloc,
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
            home: BlocProvider<AuthBloc>.value(
              value: authBloc,
              child: const Scaffold(body: LegacyMigrationCleanupPlate()),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

KdfUser _buildUserWithLegacyCleanupStatus(
  LegacyWalletSourceKind kind,
  LegacyMigrationCleanupStatus cleanupStatus,
) {
  return KdfUser(
    walletId: WalletId.fromName(
      'MigratedWallet',
      const AuthOptions(derivationMethod: DerivationMethod.iguana),
    ),
    isBip39Seed: false,
    metadata: <String, dynamic>{
      'activated_coins': <String>[],
      legacySourceKindMetadataKey: kind.name,
      legacySourceWalletIdMetadataKey: 'legacy-1',
      legacySourceWalletNameMetadataKey: 'Legacy Wallet!',
      legacyCleanupStatusMetadataKey: cleanupStatus.name,
    },
  );
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc(super.initialState);

  @override
  void add(AuthBlocEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
