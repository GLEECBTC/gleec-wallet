import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// Reset translations after this test loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/wallet_move/read_wallet_transfer_secret.dart';

import '../../helpers/runtime_auth_fixture.dart';
import 'transfer_fakes.dart';

const _seed = 'synthetic recovery phrase';

class _Auth extends Fake
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {
  _Auth(this.activeUser);

  KdfUser activeUser;
  Future<void>? beforeDispatch;
  Future<void>? beforeResult;
  int mnemonicCalls = 0;
  int mnemonicDispatches = 0;

  void replace(KdfUser user) {
    activeUser = user;
    runtimeSessions.observe(user);
  }

  @override
  Stream<int> get authGenerationChanges => const Stream.empty();

  @override
  Future<KdfUser?> get currentUser async => activeUser;

  @override
  Future<Mnemonic> getMnemonicPlainText(String password) async {
    mnemonicCalls++;
    await beforeDispatch;
    RpcDispatchGuard.ensureCurrent('get_mnemonic');
    mnemonicDispatches++;
    await beforeResult;
    return Mnemonic.plaintext(_seed);
  }
}

class _Sdk extends Fake implements KomodoDefiSdk {
  _Sdk(this.auth);

  @override
  final KomodoDefiLocalAuth auth;

  @override
  final MnemonicValidator mnemonicValidator = MnemonicValidator();
}

class _Access extends Fake implements WalletAccessService {
  _Access(this.walletId) {
    unlockCoordinator.attachWallet(
      'entry-1',
      requiresAuthentication: true,
      authenticated: true,
    );
  }

  final WalletId walletId;
  int captures = 0;

  @override
  final unlockCoordinator = WalletUnlockCoordinator(
    operationGate: WalletOperationGate(),
  );
  @override
  bool get isPasswordManagerPending => false;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      const WalletAccessStatus(
        entryId: 'entry-1',
        protection: CredentialProtection.authenticationBound,
        hasManagedCredential: true,
        requiresAuthentication: true,
      );
  @override
  Future<WalletAccessStatus> statusForWallet(Wallet wallet) => status();
  @override
  Future<CredentialCapabilities> capabilities() async =>
      const CredentialCapabilities(
        available: true,
        protection: CredentialProtection.authenticationBound,
      );
  @override
  void Function() captureSensitiveOperation(WalletId walletId) {
    expectSync(walletId, this.walletId);
    captures++;
    return unlockCoordinator.operationGate.capture().ensureCurrent;
  }
}

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

typedef _Reading = ({
  _Auth auth,
  TransferAuth bloc,
  _Access access,
  List<WalletSecretRead> results,
});

void main() {
  group('readWalletTransferSecret', () {
    setUpAll(() async {
      // The analyzer does not recognize the test_units directory as test code.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    Future<_Reading> pumpReader(WidgetTester tester, KdfUser user) async {
      final auth = _Auth(user);
      final bloc = TransferAuth(AuthBlocState.loggedIn(user));
      final access = _Access(user.walletId);
      final results = <WalletSecretRead>[];
      addTearDown(bloc.close);
      addTearDown(access.unlockCoordinator.dispose);
      final oldSize = Size(screenWidth, screenHeight);
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(() async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
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
        tester.view.reset();
      });
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          startLocale: const Locale('en'),
          saveLocale: false,
          path: 'assets/translations',
          assetLoader: const _Translations(),
          child: Builder(
            builder: (context) => MultiRepositoryProvider(
              providers: [
                RepositoryProvider<KomodoDefiSdk>.value(value: _Sdk(auth)),
                RepositoryProvider<WalletAccessService>.value(value: access),
              ],
              child: BlocProvider<AuthBloc>.value(
                value: bloc,
                child: MaterialApp(
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  home: Builder(
                    builder: (context) {
                      updateScreenType(context);
                      return Scaffold(
                        body: TextButton(
                          onPressed: () async => results.add(
                            await readWalletTransferSecretResult(context),
                          ),
                          child: const Text('read'),
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
      return (auth: auth, bloc: bloc, access: access, results: results);
    }

    Future<void> startRead(WidgetTester tester) async {
      await tester.tap(find.text('read'));
      await tester.pumpAndSettle();
    }

    Future<void> authorize(WidgetTester tester) async {
      tester
          .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
          .onSuccess('synthetic password');
      // The dialog helper polls for its close every 100 ms.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
    }

    for (final (type, evidence, expectedType, confirmed) in [
      ('hdwallet', 'phraseConfirmed', TransferWalletType.hd, true),
      ('iguana', 'none', TransferWalletType.legacy, false),
    ]) {
      testWidgets('reads a $type wallet as the reveal does', (tester) async {
        final reading = await pumpReader(
          tester,
          transferUser(type: type, evidence: evidence),
        );
        await startRead(tester);
        await authorize(tester);
        expect(reading.auth.mnemonicDispatches, 1);
        expect(reading.access.captures, 1);
        final secret = (reading.results.single as WalletSecretReady).secret;
        expect(secret.walletName, 'Savings');
        expect(secret.type, expectedType);
        expect(secret.seed, _seed);
        expect(secret.phraseConfirmed, confirmed);
        // Nothing about the result names the seed.
        expect('${reading.results.single}', isNot(contains('synthetic')));
        expect('$secret', isNot(contains('synthetic')));
      });
    }

    testWidgets('a hardware wallet is refused before any password', (
      tester,
    ) async {
      final reading = await pumpReader(tester, transferUser(type: 'trezor'));
      await startRead(tester);
      expect(find.byType(PasswordDialogContent), findsNothing);
      expect(reading.auth.mnemonicCalls, 0);
      expect(
        (reading.results.single as WalletSecretNotRead).reason,
        WalletSecretUnread.unsupported,
      );
    });

    testWidgets('closing the authorization reads nothing', (tester) async {
      final reading = await pumpReader(tester, transferUser());
      await startRead(tester);
      tester
          .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
          .onCancel();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(reading.auth.mnemonicCalls, 0);
      expect(
        (reading.results.single as WalletSecretNotRead).reason,
        WalletSecretUnread.canceled,
      );
    });

    testWidgets(
      'an app left while the password dialog was open reads nothing',
      (tester) async {
        final reading = await pumpReader(tester, transferUser());
        await startRead(tester);
        // Left before the read starts watching: only its own check sees it.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await authorize(tester);
        await tester.pumpAndSettle();
        expect(reading.auth.mnemonicDispatches, 0);
        expect(
          (reading.results.single as WalletSecretNotRead).reason,
          WalletSecretUnread.interrupted,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );

    for (final interruption in ['lock', 'pause', 'wallet switch']) {
      for (final boundary in ['before dispatch', 'late result']) {
        testWidgets('a $interruption at the mnemonic $boundary returns no '
            'seed', (tester) async {
          final user = transferUser();
          final reading = await pumpReader(tester, user);
          final delay = Completer<void>();
          if (boundary == 'before dispatch') {
            reading.auth.beforeDispatch = delay.future;
          } else {
            reading.auth.beforeResult = delay.future;
          }
          await startRead(tester);
          await authorize(tester);
          expect(reading.auth.mnemonicCalls, 1);
          final coordinator = reading.access.unlockCoordinator;
          if (interruption == 'lock') {
            coordinator.lock();
          } else if (interruption == 'pause') {
            coordinator.background();
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
          } else {
            final replacement = transferUser(name: 'Other', hash: 'other');
            reading.auth.replace(replacement);
            reading.bloc.push(AuthBlocState.loggedIn(replacement));
            coordinator.attachWallet(
              'replacement',
              requiresAuthentication: true,
              authenticated: true,
            );
          }
          delay.complete();
          await tester.pumpAndSettle();
          expect(
            reading.auth.mnemonicDispatches,
            boundary == 'before dispatch' ? 0 : 1,
          );
          expect(
            (reading.results.single as WalletSecretNotRead).reason,
            WalletSecretUnread.interrupted,
          );
        });
      }
    }
  });
}
