// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member
// ignore_for_file: invalid_use_of_protected_member

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/password_update_page.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_entry.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_main_page.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_page.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/backup_seed_notification.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_confirmation/seed_confirmation.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_show.dart';

import '../../helpers/runtime_auth_fixture.dart';

const _seed = 'synthetic recovery phrase';
const _phones = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.android,
  TargetPlatform.iOS,
});
const _desktops = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
});
const _hiddenNotice = Key('recovery-phrase-hidden-notice');

class _AuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _AuthBloc(super.initialState);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoinsBloc extends Cubit<CoinsState> implements CoinsBloc {
  _CoinsBloc() : super(CoinsState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SeedValidator extends MnemonicValidator {
  @override
  bool validateBip39(String input) => false;
}

class _Auth extends Fake
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {
  _Auth(this.user);
  final KdfUser user;
  @override
  Stream<int> get authGenerationChanges => const Stream.empty();
  @override
  Future<KdfUser?> get currentUser async => user;
  @override
  Future<Mnemonic> getMnemonicPlainText(String password) async =>
      Mnemonic.plaintext(_seed);
}

class _Sdk extends Fake implements KomodoDefiSdk {
  _Sdk(this.auth);
  @override
  final KomodoDefiLocalAuth auth;
  @override
  final MnemonicValidator mnemonicValidator = _SeedValidator();
}

class _Api extends Fake implements Mm2Api {}

class _English extends AssetLoader {
  const _English();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

KdfUser _user() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'recovery wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'recovery-flow-hash',
  ),
  isBip39Seed: true,
  metadata: const {'type': 'hdwallet', 'recovery_evidence': 'none'},
);

/// The Security page on a desktop-sized screen, or [body] in its place.
Future<void> _pump(WidgetTester tester, {Widget? body}) async {
  final user = _user();
  final authBloc = _AuthBloc(AuthBlocState.loggedIn(user));
  final coins = _CoinsBloc();
  final oldSize = Size(screenWidth, screenHeight);
  final previousRouting = routingState;
  routingState = RoutingState();
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: oldSize),
        child: Builder(
          builder: (context) {
            updateScreenType(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    routingState = previousRouting;
    pendingSecuritySettingsEntry.value = null;
    await authBloc.close();
    await coins.close();
  });
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _English(),
      child: Builder(
        builder: (context) => MultiRepositoryProvider(
          providers: [
            RepositoryProvider<KomodoDefiSdk>.value(value: _Sdk(_Auth(user))),
            RepositoryProvider<Mm2Api>.value(value: _Api()),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<CoinsBloc>.value(value: coins),
            ],
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Builder(
                builder: (context) {
                  updateScreenType(context);
                  return Scaffold(
                    body: SingleChildScrollView(
                      child: body ?? SecuritySettingsPage(onBackPressed: () {}),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Answers the authorization prompt, which leads to the words.
Future<void> _authorize(WidgetTester tester) async {
  tester
      .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
      .onSuccess('synthetic password');
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pumpAndSettle();
}

Future<void> _openWords(WidgetTester tester, {bool reveal = true}) async {
  final main = find.byType(SecuritySettingsMainPage);
  tester
      .widget<SecuritySettingsMainPage>(main)
      .onViewSeedPressed(tester.element(main));
  await tester.pumpAndSettle();
  await _authorize(tester);
  expect(find.byType(SeedShow), findsOneWidget);
  if (!reveal) return;
  await tester.tap(find.byKey(const Key('seed-show-switch')));
  await tester.pumpAndSettle();
  expect(_flow(tester).showSeedWords, isTrue);
}

SecuritySettingsState _flow(WidgetTester tester) =>
    BlocProvider.of<SecuritySettingsBloc>(
      tester.element(find.byType(SecuritySettingsEntryRunner)),
    ).state;

Future<void> _lifecycle(
  WidgetTester tester,
  List<AppLifecycleState> states,
) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));

  group('Recovery phrase in Security settings', () {
    testWidgets(
      'on desktop, clicking another window keeps the words on screen',
      (tester) async {
        await _pump(tester);
        await _openWords(tester);
        await _lifecycle(tester, [AppLifecycleState.inactive]);
        expect(find.byType(SeedShow), findsOneWidget);
        expect(_flow(tester).showSeedWords, isTrue);
        await _lifecycle(tester, [AppLifecycleState.resumed]);
        expect(find.byKey(_hiddenNotice), findsNothing);
      },
      variant: _desktops,
    );

    testWidgets(
      'on a phone, inactivity covers the words again and keeps the step',
      (tester) async {
        await _pump(tester);
        await _openWords(tester);
        await _lifecycle(tester, [AppLifecycleState.inactive]);
        expect(find.byType(SeedShow), findsOneWidget);
        expect(_flow(tester).showSeedWords, isFalse);
        await _lifecycle(tester, [AppLifecycleState.resumed]);

        // A quiz in progress is not thrown away either.
        final saved = find.text('seedPhraseShowingSavedPhraseButton'.tr());
        await tester.ensureVisible(saved);
        await tester.tap(saved);
        await tester.pumpAndSettle();
        expect(find.byType(SeedConfirmation), findsOneWidget);
        await _lifecycle(tester, [
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]);
        expect(find.byType(SeedConfirmation), findsOneWidget);
        expect(find.byKey(_hiddenNotice), findsNothing);
      },
      variant: _phones,
    );

    testWidgets(
      'leaving the app ends the flow, and the list says why until it is '
      'started again',
      (tester) async {
        await _pump(tester);
        await _openWords(tester);
        await _lifecycle(tester, [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]);
        expect(find.byType(SeedShow), findsNothing);
        expect(find.byType(SecuritySettingsMainPage), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(_hiddenNotice),
            matching: find.text('authRecoveryHiddenLeftApp'.tr()),
          ),
          findsOneWidget,
        );

        // Starting again answers the notice, before any authorization.
        final main = find.byType(SecuritySettingsMainPage);
        tester
            .widget<SecuritySettingsMainPage>(main)
            .onViewSeedPressed(tester.element(main));
        await tester.pumpAndSettle();
        expect(find.byType(PasswordDialogContent), findsOneWidget);
        expect(find.byKey(_hiddenNotice), findsNothing);
        tester
            .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
            .onCancel();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  });

  group('Opening Security settings for a task', () {
    testWidgets('a backup reminder leads straight to the authorization', (
      tester,
    ) async {
      pendingSecuritySettingsEntry.value = SecuritySettingsEntry.recoveryPhrase;
      await _pump(tester);
      // Asked for before the page existed: no press on the list is needed.
      expect(find.byType(PasswordDialogContent), findsOneWidget);
      expect(pendingSecuritySettingsEntry.value, isNull);
      await _authorize(tester);
      expect(find.byType(SeedShow), findsOneWidget);
    });

    testWidgets('a request made while the page is open is taken at once', (
      tester,
    ) async {
      await _pump(tester);
      openSecuritySettings(entry: SecuritySettingsEntry.walletPassword);
      await tester.pumpAndSettle();
      expect(find.byType(PasswordUpdatePage), findsOneWidget);
      expect(pendingSecuritySettingsEntry.value, isNull);
    });

    testWidgets('a request nobody takes does not wait for a later visit', (
      tester,
    ) async {
      await _pump(tester, body: const SizedBox.shrink());
      openSecuritySettings(entry: SecuritySettingsEntry.recoveryPhrase);
      expect(
        pendingSecuritySettingsEntry.value,
        SecuritySettingsEntry.recoveryPhrase,
      );
      await tester.pumpAndSettle();
      expect(pendingSecuritySettingsEntry.value, isNull);
    });
  });

  group('Backup reminder banner', () {
    tearDown(() => recoveryPhraseFlowOnScreen.value = false);

    testWidgets('has a full-size button that starts the backup', (
      tester,
    ) async {
      await _pump(tester, body: const BackupSeedNotification());
      final button = find.descendant(
        of: find.byType(BackupSeedNotification),
        matching: find.byType(ElevatedButton),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.tap(button);
      expect(
        pendingSecuritySettingsEntry.value,
        SecuritySettingsEntry.recoveryPhrase,
      );
      expect(routingState.settingsState.selectedMenu.name, 'security');
      await tester.pumpAndSettle();
    });

    testWidgets('steps aside while the recovery phrase is on screen', (
      tester,
    ) async {
      await _pump(
        tester,
        body: Column(
          children: [
            const BackupSeedNotification(),
            SecuritySettingsPage(onBackPressed: () {}),
          ],
        ),
      );
      final title = find.descendant(
        of: find.byType(BackupSeedNotification),
        matching: find.text('backupSeedNotificationTitle'.tr()),
      );
      expect(title, findsOneWidget);
      await _openWords(tester, reveal: false);
      expect(title, findsNothing);
      tester
          .element(find.byType(SeedShow))
          .read<SecuritySettingsBloc>()
          .add(const ResetEvent());
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
    });
  });
}
