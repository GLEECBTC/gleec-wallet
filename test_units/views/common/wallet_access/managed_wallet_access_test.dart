import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/authorize_mode.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/shared/widgets/logout_popup.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_boundary.dart';
import 'package:web_dex/views/common/wallet_access/wallet_setup_card.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_manager_save.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_password_dialog.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_credential_cleanup_notice.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/legal_documents_fixture.dart';

class _Access extends Fake implements WalletAccessService {
  final outcomes = <PasswordManagerOutcome>[];
  bool pendingCleanup = false;
  int cleanupRetries = 0;
  @override
  Future<bool> get hasPendingCredentialCleanup async => pendingCleanup;
  @override
  Future<void> retryCredentialCleanup() async {
    cleanupRetries++;
    pendingCleanup = false;
  }

  final authorized = <WalletId>[];
  final suppliedPasswords = <String?>[];
  Future<void>? authorizationDelay;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  final unlockCoordinator = WalletUnlockCoordinator(
    operationGate: WalletOperationGate(),
  );
  @override
  Future<bool> unlockCurrent({String? password, bool automatic = false}) async {
    final attempt = unlockCoordinator.beginUnlock(automatic: automatic);
    if (attempt == null) return false;
    await authorize(walletId: _user().walletId, password: password);
    return unlockCoordinator.completeUnlock(attempt);
  }

  @override
  Future<WalletAccessStatus> statusForWallet(Wallet wallet) => status();
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      const WalletAccessStatus(
        entryId: 'entry-synthetic',
        protection: CredentialProtection.authenticationBound,
        hasManagedCredential: true,
        requiresAuthentication: true,
        generatedPassword: true,
      );
  @override
  Future<String> authorize({
    required WalletId walletId,
    String? password,
    String reason = 'Unlock your wallet',
  }) async {
    authorized.add(walletId);
    suppliedPasswords.add(password);
    await authorizationDelay;
    return 'synthetic-generated-password';
  }

  @override
  void Function() captureSensitiveOperation(WalletId walletId) {
    final generation = unlockCoordinator.state.generation;
    final authorization = unlockCoordinator.authorizationGeneration;
    final entry = unlockCoordinator.state.walletEntryId;
    final permit = entry == null
        ? null
        : unlockCoordinator.operationGate.capture(expectedWalletEntryId: entry);
    void ensureCurrent() {
      final state = unlockCoordinator.state;
      if (walletId != _user().walletId ||
          state.generation != generation ||
          unlockCoordinator.authorizationGeneration != authorization ||
          state.isLocked ||
          !state.isForeground) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
      permit?.ensureCurrent();
    }

    ensureCurrent();
    return ensureCurrent;
  }

  @override
  Future<SensitiveExportAuthorization> captureSensitiveExport(
    WalletId walletId,
  ) async => _ExportAuthorization(captureSensitiveOperation(walletId));

  @override
  Future<PasswordManagerOutcome> saveToPasswordManager({
    required WalletId walletId,
    String? password,
  }) async => PasswordManagerOutcome.unavailable;
  @override
  Future<void> recordPasswordManagerOutcome({
    required WalletId walletId,
    required PasswordManagerOutcome outcome,
  }) async => outcomes.add(outcome);
}

class _ExportAuthorization extends Fake
    implements SensitiveExportAuthorization {
  _ExportAuthorization(this.ensureCurrent);

  @override
  final void Function() ensureCurrent;

  @override
  Future<String?> Function(Future<String?> Function()) get selectDestination =>
      (select) async {
        ensureCurrent();
        final destination = await select();
        ensureCurrent();
        return destination;
      };
}

class _Trading extends Cubit<TradingStatusState> implements TradingStatusBloc {
  _Trading() : super(TradingStatusInitial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DelayedLegal extends Cubit<LegalAgreementState>
    implements LegalAgreementBloc {
  _DelayedLegal()
    : super(
        LegalAgreementState(
          LegalAgreementStatus.initial,
          legalFixtureSnapshot(),
        ),
      );
  void finishAcceptanceLookup() =>
      emit(LegalAgreementState(LegalAgreementStatus.current, state.snapshot));
  @override
  bool get canComplete => true;
  @override
  bool get canSubmit => true;
  @override
  void add(LegalAgreementEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KdfUser _user() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'My wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'synthetic-wallet-hash',
  ),
  isBip39Seed: true,
  metadata: const {'type': 'hdwallet'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Managed wallet access UI', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    testWidgets(
      'credential cleanup remains available without a signed-in wallet',
      (tester) async {
        final harness = LegalFormHarness();
        final access = _Access()..pendingCleanup = true;
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: const WalletCredentialCleanupNotice(),
          ),
        );
        expect(harness.auth.state.currentUser, isNull);
        expect(
          find.byKey(const Key('wallet-credential-cleanup-notice')),
          findsOneWidget,
        );
        await tester.tap(find.text('authRetryCredentialCleanup'.tr()));
        await tester.pumpAndSettle();
        expect(access.cleanupRetries, 1);
        expect(
          find.byKey(const Key('wallet-credential-cleanup-notice')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'application cover supports automatic return and manual password unlock',
      (tester) async {
        final harness = LegalFormHarness();
        final access = _Access();
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(_user()));
        access.unlockCoordinator.attachWallet(
          'entry-synthetic',
          requiresAuthentication: true,
        );
        addTearDown(access.unlockCoordinator.dispose);
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: const SizedBox(
              height: 650,
              child: WalletAccessBoundary(child: Text('Wallet contents')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(access.authorized, hasLength(1));
        expect(access.unlockCoordinator.state.isLocked, isFalse);
        access.unlockCoordinator.lock();
        await tester.pumpAndSettle();
        expect(access.authorized, hasLength(1));
        expect(find.byKey(const Key('wallet-lock-screen')), findsOneWidget);
        await tester.tap(find.byKey(const Key('wallet-lock-use-password')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('wallet-lock-password')),
          'synthetic-personal-password',
        );
        await tester.tap(find.byKey(const Key('wallet-lock-password-submit')));
        await tester.pumpAndSettle();
        expect(access.suppliedPasswords, [null, 'synthetic-personal-password']);
        expect(access.unlockCoordinator.state.isLocked, isFalse);
        expect(find.byKey(const Key('wallet-lock-screen')), findsNothing);
      },
    );

    testWidgets(
      'failed signout leaves a usable locked cover and supports another attempt',
      (tester) async {
        final harness = LegalFormHarness();
        final access = _Access();
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(_user()));
        access.unlockCoordinator.attachWallet(
          'entry-synthetic',
          requiresAuthentication: true,
          authenticated: true,
        );
        access.unlockCoordinator.lock();
        addTearDown(access.unlockCoordinator.dispose);
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: BlocProvider<TradingStatusBloc>(
              create: (_) => _Trading(),
              child: const SizedBox(
                height: 650,
                child: WalletAccessBoundary(child: Text('Wallet contents')),
              ),
            ),
          ),
        );
        for (var attempt = 0; attempt < 2; attempt++) {
          await tester.tap(find.byKey(const Key('wallet-lock-switch-wallet')));
          await tester.pumpAndSettle();
          // Exercise the host's pending transition; engine signout is tested by
          // AuthBloc, while this fixture controls its asynchronous result.
          tester.widget<LogOutPopup>(find.byType(LogOutPopup)).onConfirm();
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
          harness.auth.emit(
            AuthBlocState(
              mode: AuthorizeMode.logIn,
              currentUser: _user(),
              authError: AuthException(
                'synthetic signout failure $attempt',
                type: AuthExceptionType.generalAuthError,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('authSignOutFailed'.tr()), findsOneWidget);
          expect(access.unlockCoordinator.state.isLocked, isTrue);
        }
      },
    );

    testWidgets('automatic return waits for slow legal acceptance lookup', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      final legal = _DelayedLegal();
      addTearDown(legal.close);
      await harness.pump(
        tester,
        RepositoryProvider<WalletAccessService>.value(
          value: _Access(),
          child: BlocProvider<LegalAgreementBloc>.value(
            value: legal,
            child: WalletLogIn(
              wallet: legalTestWallet(),
              initialQuickLogin: true,
              onLogin: (_, _, _) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      expect(
        harness.auth.events.whereType<AuthManagedSignInRequested>(),
        isEmpty,
      );
      legal.finishAcceptanceLookup();
      await tester.pumpAndSettle();
      expect(
        harness.auth.events.whereType<AuthManagedSignInRequested>(),
        hasLength(1),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        harness.auth.events.whereType<AuthManagedSignInRequested>(),
        hasLength(1),
      );
    });

    testWidgets(
      'automatic entry runs once and cancellation keeps all alternatives',
      (tester) async {
        final harness = LegalFormHarness();
        final access = _Access();
        await harness.repository.recordAcceptance(surface: 'test');
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: WalletLogIn(
              wallet: legalTestWallet(),
              initialQuickLogin: true,
              onLogin: (_, _, _) {},
              onCancel: () {},
              onSwitchWallet: () {},
              onRecover: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          harness.auth.events.whereType<AuthManagedSignInRequested>(),
          hasLength(1),
        );
        expect(find.byKey(const Key('create-password-field')), findsNothing);
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(
          AuthBlocState.error(
            AuthException('Canceled', type: AuthExceptionType.generalAuthError),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(
          harness.auth.events.whereType<AuthManagedSignInRequested>(),
          hasLength(1),
        );
        expect(find.byKey(const Key('managed-wallet-unlock')), findsOneWidget);
        expect(find.text('authUsePassword'.tr()), findsOneWidget);
        expect(find.text('authSwitchWallet'.tr()), findsOneWidget);
        expect(find.text('authRecoverWallet'.tr()), findsOneWidget);
        await tester.tap(find.text('authUsePassword'.tr()));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('create-password-field')), findsOneWidget);
      },
    );

    testWidgets('automatic entry never accepts changed legal terms', (
      tester,
    ) async {
      final harness = LegalFormHarness(updated: true);
      await harness.pump(
        tester,
        RepositoryProvider<WalletAccessService>.value(
          value: _Access(),
          child: WalletLogIn(
            wallet: legalTestWallet(),
            initialQuickLogin: true,
            onLogin: (_, _, _) {},
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        harness.auth.events.whereType<AuthManagedSignInRequested>(),
        isEmpty,
      );
      expect((await harness.repository.readAcceptance())!.surface, 'old-form');
      await tester.tap(find.byKey(const Key('managed-wallet-unlock')));
      await tester.pumpAndSettle();
      expect(
        harness.auth.events.whereType<AuthManagedSignInRequested>(),
        hasLength(1),
      );
      expect(
        (await harness.repository.readAcceptance())!.surface,
        'wallet-login',
      );
    });

    testWidgets(
      'generated-password export uses fresh device authorization without typing',
      (tester) async {
        final harness = LegalFormHarness();
        final access = _Access();
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(_user()));
        var submitted = 0;
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: PrivateKeyExportPasswordDialog(
              walletName: 'My wallet',
              isLoading: false,
              onSubmit: (credential) {
                expect(credential.value, 'synthetic-generated-password');
                submitted++;
              },
              onCancel: () {},
            ),
          ),
        );
        expect(
          find.byKey(const Key('private-key-export-password')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const Key('private-key-export-password-submit')),
        );
        await tester.pump();
        expect(submitted, 1);
        expect(access.authorized, [_user().walletId]);
        expect(
          harness.auth.state.toString(),
          isNot(contains('synthetic-generated-password')),
        );
      },
    );

    testWidgets(
      'autofill save is optional and reports unknown rather than accepted',
      (tester) async {
        final harness = LegalFormHarness();
        final access = _Access();
        PasswordManagerOutcome? result;
        await harness.pump(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await saveWalletPassword(
                  context,
                  access: access,
                  walletId: _user().walletId,
                );
              },
              child: const Text('Offer save'),
            ),
          ),
        );
        await tester.tap(find.text('Offer save'));
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(
          find.byKey(const Key('password-manager-save-credential')),
        );
        expect(field.obscureText, isTrue);
        expect(field.enableInteractiveSelection, isFalse);
        expect(access.authorized, [_user().walletId]);
        expect(result, isNull);
        await tester.tap(find.byKey(const Key('password-manager-save-submit')));
        await tester.pumpAndSettle();
        expect(result, PasswordManagerOutcome.unknown);
        expect(access.outcomes, [PasswordManagerOutcome.unknown]);
      },
    );

    testWidgets('barrier dismissal revokes authorization during exit animation', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      final authorization = Completer<void>();
      final access = _Access()..authorizationDelay = authorization.future;
      addTearDown(access.unlockCoordinator.dispose);
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      harness.auth.emit(AuthBlocState.loggedIn(_user()));
      var callbacks = 0;
      var cancellations = 0;
      final completions = <bool>[];
      await harness.pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => RepositoryProvider<WalletAccessService>.value(
                value: access,
                child: BlocProvider<AuthBloc>.value(
                  value: harness.auth,
                  child: Dialog(
                    child: PasswordDialogContentWithLoading(
                      onPasswordValidated: (_) async {
                        callbacks++;
                        return true;
                      },
                      onComplete: completions.add,
                      onCancel: () => cancellations++,
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Open authorization'),
          ),
        ),
      );
      await tester.tap(find.text('Open authorization'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('continueText'.tr()));
      await tester.pump();
      await tester.tapAt(const Offset(1, 1));
      // Do not settle the closing transition: the widget remains mounted.
      authorization.complete();
      await tester.pump();
      expect(callbacks, 0);
      expect(completions, isEmpty);
      expect(cancellations, 0, reason: 'Dismissal must not pop another route');
      await tester.pumpAndSettle();
      expect(find.text('Open authorization'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cancel revokes a pending authorization before route disposal', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      final authorization = Completer<void>();
      final access = _Access()..authorizationDelay = authorization.future;
      addTearDown(access.unlockCoordinator.dispose);
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      harness.auth.emit(AuthBlocState.loggedIn(_user()));
      var callbacks = 0;
      var cancellations = 0;
      final completions = <bool>[];
      await harness.pump(
        tester,
        RepositoryProvider<WalletAccessService>.value(
          value: access,
          child: PasswordDialogContentWithLoading(
            onPasswordValidated: (_) async {
              callbacks++;
              return true;
            },
            onComplete: completions.add,
            // Keep the widget mounted to exercise the gap before route removal.
            onCancel: () => cancellations++,
          ),
        ),
      );
      await tester.tap(find.text('continueText'.tr()));
      await tester.pump();
      await tester.tap(find.text('cancel'.tr()));
      authorization.complete();
      await tester.pumpAndSettle();
      expect(callbacks, 0);
      expect(completions, isEmpty);
      expect(cancellations, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a lock during fresh authorization prevents the sensitive callback',
      (tester) async {
        final harness = LegalFormHarness();
        final authorization = Completer<void>();
        final access = _Access()..authorizationDelay = authorization.future;
        access.unlockCoordinator.attachWallet(
          'entry-synthetic',
          requiresAuthentication: true,
          authenticated: true,
        );
        addTearDown(access.unlockCoordinator.dispose);
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(_user()));
        var callbacks = 0;
        var cancellations = 0;
        final completions = <bool>[];
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: PasswordDialogContentWithLoading(
              onPasswordValidated: (_) async {
                callbacks++;
                return true;
              },
              onComplete: completions.add,
              onCancel: () => cancellations++,
            ),
          ),
        );
        await tester.tap(find.text('continueText'.tr()));
        await tester.pump();
        expect(access.authorized, [_user().walletId]);
        expect(callbacks, 0);

        access.unlockCoordinator.lock();
        authorization.complete();
        await tester.pumpAndSettle();

        expect(callbacks, 0);
        expect(completions, isEmpty);
        expect(cancellations, 1);
        expect(tester.takeException(), isNull);
      },
    );

    for (final switchWallet in [false, true]) {
      testWidgets(
        'sensitive result cannot complete after ${switchWallet ? 'wallet switch' : 'lock'}',
        (tester) async {
          final harness = LegalFormHarness();
          final result = Completer<bool>();
          final access = _Access();
          access.unlockCoordinator.attachWallet(
            'entry-synthetic',
            requiresAuthentication: true,
            authenticated: true,
          );
          addTearDown(access.unlockCoordinator.dispose);
          // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
          harness.auth.emit(AuthBlocState.loggedIn(_user()));
          var callbacks = 0;
          var cancellations = 0;
          final completions = <bool>[];
          await harness.pump(
            tester,
            RepositoryProvider<WalletAccessService>.value(
              value: access,
              child: PasswordDialogContentWithLoading(
                onPasswordValidated: (_) {
                  callbacks++;
                  return result.future;
                },
                onComplete: completions.add,
                onCancel: () => cancellations++,
              ),
            ),
          );
          await tester.tap(find.text('continueText'.tr()));
          await tester.pump();
          expect(callbacks, 1);

          if (switchWallet) {
            final nextUser = _user().copyWith(
              walletId: _user().walletId.copyWith(name: 'Other wallet'),
            );
            // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
            harness.auth.emit(AuthBlocState.loggedIn(nextUser));
            access.unlockCoordinator.attachWallet(
              'entry-other',
              requiresAuthentication: true,
              authenticated: true,
            );
          } else {
            access.unlockCoordinator.lock();
          }
          result.complete(true);
          await tester.pumpAndSettle();

          expect(callbacks, 1);
          expect(completions, isEmpty);
          if (!switchWallet) expect(cancellations, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final method in [
      'get_mnemonic',
      'show_priv_key',
      'get_private_keys',
    ]) {
      testWidgets('lock rejects delayed $method before transport dispatch', (
        tester,
      ) async {
        final harness = LegalFormHarness();
        final prepared = Completer<void>();
        final access = _Access();
        access.unlockCoordinator.attachWallet(
          'entry-synthetic',
          requiresAuthentication: true,
          authenticated: true,
        );
        addTearDown(access.unlockCoordinator.dispose);
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(_user()));
        var callbacks = 0;
        var dispatched = 0;
        var cancellations = 0;
        final completions = <bool>[];
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: PasswordDialogContentWithLoading(
              onPasswordValidated: (_) async {
                callbacks++;
                await prepared.future;
                // Mirrors the transport's last check after asynchronous RPC
                // preparation, without sending any real request or secret.
                RpcDispatchGuard.ensureCurrent(method);
                dispatched++;
                return true;
              },
              onComplete: completions.add,
              onCancel: () => cancellations++,
            ),
          ),
        );
        await tester.tap(find.text('continueText'.tr()));
        await tester.pump();
        expect(callbacks, 1);

        access.unlockCoordinator.lock();
        prepared.complete();
        await tester.pumpAndSettle();

        expect(dispatched, 0);
        expect(completions, isEmpty);
        expect(cancellations, 1);
        expect(find.text('passwordNotAccepted'.tr()), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('password-manager offer closes without authorizing or saving', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      final access = _Access();
      addTearDown(access.unlockCoordinator.dispose);
      await harness.pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => offerWalletPasswordSave(
              context,
              access: access,
              walletId: _user().walletId,
            ),
            child: const Text('Offer password-manager save'),
          ),
        ),
      );
      await tester.tap(find.text('Offer password-manager save'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(access.outcomes, [PasswordManagerOutcome.offered]);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(access.authorized, isEmpty);
      expect(access.outcomes, [PasswordManagerOutcome.offered]);
      expect(tester.takeException(), isNull);
    });

    for (final recovery in [false, true]) {
      for (final protected in [false, true]) {
        testWidgets(
          'recovery=$recovery and protection=$protected stay independent',
          (tester) async {
            final harness = LegalFormHarness();
            await harness.pump(
              tester,
              WalletSetupCard(
                hasRecoveryPhrase: recovery,
                hasDeviceProtection: protected,
                onBackup: () {},
                onProtect: () {},
              ),
              size: const Size(360, 900),
              textScale: 2,
            );
            expect(
              find.byKey(const Key('wallet-setup-backup')),
              recovery ? findsNothing : findsOneWidget,
            );
            expect(
              find.byKey(const Key('wallet-setup-protect')),
              protected ? findsNothing : findsOneWidget,
            );
            expect(
              find.byKey(const Key('wallet-setup-card')),
              recovery && protected ? findsNothing : findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
