import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/shared/seed_backup/seed_backup_policy.dart';
import 'package:web_dex/views/common/seed_backup_gate/seed_backup_gate.dart';

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc(super.initialState);

  final List<AuthBlocEvent> addedEvents = [];

  @override
  void add(AuthBlocEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KdfUser _user({required bool hasBackup, String provenance = 'generated'}) =>
    KdfUser(
      walletId: WalletId.fromName(
        'gate-wallet',
        const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
      ),
      isBip39Seed: true,
      metadata: {
        'type': 'hdwallet',
        'has_backup': hasBackup,
        'wallet_provenance': provenance,
      },
    );

/// Pumps a button that runs the gate and records what it returned.
Future<List<bool>> _pumpGate(
  WidgetTester tester, {
  required _FakeAuthBloc authBloc,
}) async {
  final results = <bool>[];

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _EmptyAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: BlocProvider<AuthBloc>.value(
            value: authBloc,
            child: Scaffold(
              body: Builder(
                builder: (inner) => ElevatedButton(
                  onPressed: () async {
                    results.add(
                      await ensureSeedBackedUp(
                        inner,
                        reason: SeedBackupGateReason.receiveAddress,
                      ),
                    );
                  },
                  child: const Text('reveal'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return results;
}

void testSeedBackupGate() {
  group('seed backup gate', () {
    setUp(resetSeedBackupAcknowledgements);
    tearDown(resetSeedBackupAcknowledgements);

    testWidgets('a backed-up wallet is revealed without any prompt', (
      tester,
    ) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(_user(hasBackup: true)),
      );
      addTearDown(authBloc.close);

      final results = await _pumpGate(tester, authBloc: authBloc);
      await tester.tap(find.text('reveal'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('seed-backup-gate-notice')), findsNothing);
      expect(results, [true]);
    });

    testWidgets('an un-backed-up wallet is stopped by the notice', (
      tester,
    ) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(_user(hasBackup: false)),
      );
      addTearDown(authBloc.close);

      await _pumpGate(tester, authBloc: authBloc);
      await tester.tap(find.text('reveal'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('seed-backup-gate-notice')), findsOneWidget);
    });

    testWidgets(
      'continue-anyway reveals, and does not re-prompt this session',
      (tester) async {
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(_user(hasBackup: false)),
        );
        addTearDown(authBloc.close);

        final results = await _pumpGate(tester, authBloc: authBloc);

        await tester.tap(find.text('reveal'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('seed-backup-gate-continue-button')),
        );
        await tester.pumpAndSettle();
        expect(results, [true]);

        // Second reveal in the same session must go straight through.
        await tester.tap(find.text('reveal'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('seed-backup-gate-notice')), findsNothing);
        expect(results, [true, true]);
      },
    );

    testWidgets('acknowledging never marks the seed as backed up', (
      tester,
    ) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(_user(hasBackup: false)),
      );
      addTearDown(authBloc.close);

      await _pumpGate(tester, authBloc: authBloc);
      await tester.tap(find.text('reveal'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('seed-backup-gate-continue-button')),
      );
      await tester.pumpAndSettle();

      // The banner, the menu indicator and the settings label all read
      // has_backup as proof the user holds their words. Acknowledging is not
      // that proof, so it must not dispatch a backup confirmation.
      expect(
        authBloc.addedEvents.whereType<AuthSeedBackupConfirmed>(),
        isEmpty,
      );
    });

    testWidgets('restore-instead declines the reveal and signs out', (
      tester,
    ) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(_user(hasBackup: false)),
      );
      addTearDown(authBloc.close);

      final results = await _pumpGate(tester, authBloc: authBloc);
      await tester.tap(find.text('reveal'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('seed-backup-gate-import-instead-button')),
      );
      await tester.pumpAndSettle();

      // Declines the address...
      expect(results, [false]);
      // ...and clears the way to actually restore, which is impossible while
      // signed into another wallet.
      expect(
        authBloc.addedEvents.whereType<AuthSignOutRequested>(),
        hasLength(1),
      );
    });

    testWidgets('an imported wallet gets no restore-instead escape hatch', (
      tester,
    ) async {
      // That branch exists to catch someone who meant to restore and was
      // routed into creating. It makes no sense once they did import.
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(_user(hasBackup: false, provenance: 'imported')),
      );
      addTearDown(authBloc.close);

      await _pumpGate(tester, authBloc: authBloc);
      await tester.tap(find.text('reveal'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('seed-backup-gate-notice')), findsOneWidget);
      expect(
        find.byKey(const Key('seed-backup-gate-import-instead-button')),
        findsNothing,
      );
    });
  });
}
