import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_state.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/seed_backup/seed_backup_policy.dart';
import 'package:web_dex/views/common/seed_backup_gate/seed_backup_gate.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_show.dart';

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    LocaleKeys.seedPhraseShowingShowPhrase: 'Show my seed phrase',
    LocaleKeys.seedPhraseShowingCopySeed: 'Copy seed',
  };
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc(super.initialState);

  final List<AuthBlocEvent> addedEvents = [];

  void updateUser(KdfUser user) => emit(AuthBlocState.loggedIn(user));

  @override
  void add(AuthBlocEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAnalyticsBloc extends Cubit<AnalyticsState>
    implements AnalyticsBloc {
  _FakeAnalyticsBloc() : super(AnalyticsState.initial());

  @override
  void add(AnalyticsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements KomodoDefiLocalAuth {
  @override
  Future<Mnemonic> getMnemonicPlainText(String password) async =>
      Mnemonic.plaintext('single-token-test-seed');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CustomSeedValidator extends MnemonicValidator {
  @override
  bool validateBip39(String input) => false;
}

class _FakeSdk implements KomodoDefiSdk {
  @override
  final KomodoDefiLocalAuth auth = _FakeAuth();

  @override
  final MnemonicValidator mnemonicValidator = _CustomSeedValidator();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KdfUser _user({
  required bool hasBackup,
  String provenance = 'generated',
  String pubkeyHash = 'first-wallet-pubkey-hash',
}) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'gate-wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    pubkeyHash,
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
  final previousScreenSize = Size(screenWidth, screenHeight);
  final results = <bool>[];
  final analyticsBloc = _FakeAnalyticsBloc();
  addTearDown(analyticsBloc.close);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _EmptyAssetLoader(),
      child: Builder(
        builder: (context) => RepositoryProvider<KomodoDefiSdk>.value(
          value: _FakeSdk(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<AnalyticsBloc>.value(value: analyticsBloc),
            ],
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Scaffold(
                body: Builder(
                  builder: (inner) {
                    updateScreenType(inner);
                    return ElevatedButton(
                      onPressed: () async {
                        results.add(
                          await ensureSeedBackedUp(
                            inner,
                            reason: SeedBackupGateReason.receiveAddress,
                          ),
                        );
                      },
                      child: const Text('reveal'),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: previousScreenSize),
        child: Builder(
          builder: (context) {
            updateScreenType(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
  return results;
}

void testSeedBackupGate() {
  group('seed backup gate', () {
    // The analyzer only recognizes test/, not this CI test_units/ suite.
    // ignore: invalid_use_of_visible_for_testing_member
    setUp(resetSeedBackupAcknowledgements);
    // ignore: invalid_use_of_visible_for_testing_member
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

    testWidgets(
      'a new wallet with the same name needs its own acknowledgement',
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

        authBloc.updateUser(
          _user(hasBackup: false, pubkeyHash: 'replacement-wallet-pubkey-hash'),
        );
        await tester.pump();
        await tester.tap(find.text('reveal'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('seed-backup-gate-notice')),
          findsOneWidget,
        );
        expect(results, [true]);
      },
    );

    testWidgets(
      'a wallet change while the notice is open declines the reveal',
      (tester) async {
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(_user(hasBackup: false)),
        );
        addTearDown(authBloc.close);
        final results = await _pumpGate(tester, authBloc: authBloc);

        await tester.tap(find.text('reveal'));
        await tester.pumpAndSettle();
        authBloc.updateUser(
          _user(hasBackup: false, pubkeyHash: 'replacement-wallet-pubkey-hash'),
        );
        await tester.pumpAndSettle();

        expect(results, [false]);
        expect(find.byKey(const Key('seed-backup-gate-notice')), findsNothing);
        await tester.tap(find.text('reveal'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('seed-backup-gate-notice')),
          findsOneWidget,
        );
      },
    );

    testWidgets('a wallet change closes an in-progress seed backup', (
      tester,
    ) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(_user(hasBackup: false)),
      );
      addTearDown(authBloc.close);
      final results = await _pumpGate(tester, authBloc: authBloc);

      await tester.tap(find.text('reveal'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('seed-backup-gate-backup-button')));
      await tester.pumpAndSettle();
      tester
          .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
          .onSuccess('test-password');
      await tester.pumpAndSettle();
      expect(find.byType(SeedShow), findsOneWidget);

      authBloc.updateUser(
        _user(hasBackup: false, pubkeyHash: 'replacement-wallet-pubkey-hash'),
      );
      await tester.pumpAndSettle();

      expect(results, [false]);
      expect(find.byType(SeedShow), findsNothing);
      expect(
        authBloc.addedEvents.whereType<AuthSeedBackupConfirmed>(),
        isEmpty,
      );
    });

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

    testWidgets(
      'mobile custom-seed backup can exit without revealing an address',
      (tester) async {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(
            _user(hasBackup: false, provenance: 'imported'),
          ),
        );
        addTearDown(authBloc.close);

        final results = await _pumpGate(tester, authBloc: authBloc);
        await tester.tap(find.text('reveal'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const Key('seed-backup-gate-backup-button')),
        );
        await tester.pumpAndSettle();

        // Password verification is outside this navigation regression.
        tester
            .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
            .onSuccess('test-password');
        await tester.pumpAndSettle();

        expect(isMobile, isTrue);
        expect(find.byType(SeedShow), findsOneWidget);
        expect(find.text('Show my seed phrase'), findsOneWidget);
        expect(find.text('Copy seed'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('back-button')), findsOneWidget);
        await tester.tap(find.byKey(const Key('back-button')));
        await tester.pumpAndSettle();

        expect(results, [false]);
        expect(find.byType(SeedShow), findsNothing);
        expect(
          authBloc.addedEvents.whereType<AuthSeedBackupConfirmed>(),
          isEmpty,
        );

        await tester.tap(find.text('reveal'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('seed-backup-gate-notice')),
          findsOneWidget,
        );
      },
    );
  });
}
