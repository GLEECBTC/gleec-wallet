import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_access_actions.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';

import '../../../support/legal_onboarding_harness.dart';

WalletAccessStatus _lost({
  bool generated = true,
  PasswordManagerOutcome manager = PasswordManagerOutcome.unknown,
}) => WalletAccessStatus(
  entryId: 'entry-restored',
  protection: CredentialProtection.password,
  hasManagedCredential: false,
  requiresAuthentication: true,
  generatedPassword: generated,
  passwordManager: manager,
  lostProtection: CredentialProtection.authenticationBound,
);

WalletAccessStatus _managed({bool generated = true}) => WalletAccessStatus(
  entryId: 'entry-restored',
  protection: CredentialProtection.authenticationBound,
  hasManagedCredential: true,
  requiresAuthentication: true,
  generatedPassword: generated,
);

class _Access extends Fake implements WalletAccessService {
  _Access(this.answer);
  final WalletAccessStatus answer;
  int lookups = 0;

  @override
  Future<WalletAccessStatus> statusForWallet(Wallet wallet) async {
    lookups++;
    return answer;
  }
}

/// What the bloc reports when a stored unlock did not open the wallet.
AuthException _failed(String message, WalletAccessFailure failure) =>
    AuthException(
      message.tr(),
      type: AuthExceptionType.generalAuthError,
      details: {'walletAccessFailure': failure.name},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Sign-in sheet for a wallet without its stored unlock', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    late int recoveries;
    setUp(() => recoveries = 0);

    Future<LegalFormHarness> pumpSheet(
      WidgetTester tester,
      _Access access, {
      bool recover = true,
      bool remembered = false,
    }) async {
      final harness = LegalFormHarness();
      await harness.pump(
        tester,
        RepositoryProvider<WalletAccessService>.value(
          value: access,
          child: WalletLogIn(
            wallet: legalTestWallet(),
            initialQuickLogin: remembered,
            onLogin: (_, _, _) {},
            onCancel: () {},
            onSwitchWallet: () {},
            onRecover: recover ? () => recoveries++ : null,
          ),
        ),
      );
      return harness;
    }

    Future<void> failManagedUnlock(
      WidgetTester tester,
      LegalFormHarness harness,
      AuthException failure,
    ) async {
      await tester.tap(find.byKey(const Key('managed-wallet-unlock')));
      await tester.pumpAndSettle();
      // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
      harness.auth.emit(AuthBlocState.error(failure));
      await tester.pumpAndSettle();
    }

    testWidgets('a generated password leads with the recovery phrase', (
      tester,
    ) async {
      final harness = await pumpSheet(
        tester,
        _Access(_lost()),
        remembered: true,
      );

      expect(find.text('authDeviceUnlockLost'.tr()), findsOneWidget);
      expect(find.text('authUnlockLostGeneratedHint'.tr()), findsOneWidget);
      expect(find.byKey(const Key('create-password-field')), findsNothing);
      // Recovery leads, so it is not repeated among the exits.
      expect(find.text('authRecoverWallet'.tr()), findsNothing);
      expect(find.text('authSwitchWallet'.tr()), findsOneWidget);
      expect(
        harness.auth.events.whereType<AuthManagedSignInRequested>(),
        isEmpty,
      );

      await tester.tap(find.byKey(const Key('wallet-unlock-lost-recover')));
      await tester.pumpAndSettle();
      expect(recoveries, 1);
    });

    testWidgets('a password the manager may hold opens the password form', (
      tester,
    ) async {
      await pumpSheet(tester, _Access(_lost()));

      await tester.tap(find.text('authUseSavedPassword'.tr()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('create-password-field')), findsOneWidget);
      expect(find.byKey(const Key('wallet-unlock-lost')), findsOneWidget);
      expect(find.text('authGeneratedPasswordHint'.tr()), findsOneWidget);
      await tester.tap(find.text('authRecoverWallet'.tr()));
      expect(recoveries, 1);
    });

    for (final (outcome, saved) in [
      (PasswordManagerOutcome.accepted, true),
      (PasswordManagerOutcome.unknown, true),
      (PasswordManagerOutcome.unavailable, false),
      (PasswordManagerOutcome.declined, false),
      (PasswordManagerOutcome.failed, false),
    ]) {
      testWidgets('a password save that ${outcome.name} '
          '${saved ? 'offers the saved password' : 'keeps a plain route'}', (
        tester,
      ) async {
        await pumpSheet(tester, _Access(_lost(manager: outcome)));

        expect(
          find.text('authUseSavedPassword'.tr()),
          saved ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('authUsePassword'.tr()),
          saved ? findsNothing : findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('wallet-unlock-lost-password')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('create-password-field')), findsOneWidget);
      });
    }

    testWidgets('a chosen password keeps the password form', (tester) async {
      await pumpSheet(tester, _Access(_lost(generated: false)));

      expect(find.byKey(const Key('create-password-field')), findsOneWidget);
      expect(find.text('authDeviceUnlockLost'.tr()), findsOneWidget);
      expect(find.byKey(const Key('wallet-unlock-lost-hint')), findsOneWidget);
      expect(find.text('authUnlockLostPasswordHint'.tr()), findsOneWidget);
      expect(find.text('authUseRecoveryPhrase'.tr()), findsNothing);
      expect(find.byKey(const Key('wallet-password-unlock')), findsOneWidget);
      expect(find.text('authRecoverWallet'.tr()), findsOneWidget);
    });

    testWidgets('without a recovery route the password form explains', (
      tester,
    ) async {
      await pumpSheet(tester, _Access(_lost()), recover: false);

      expect(find.byKey(const Key('wallet-unlock-lost-recover')), findsNothing);
      expect(find.byKey(const Key('create-password-field')), findsOneWidget);
      expect(find.text('authDeviceUnlockLost'.tr()), findsOneWidget);
    });

    testWidgets('an unlock that turns out gone leads to the recovery phrase', (
      tester,
    ) async {
      final access = _Access(_managed());
      final harness = await pumpSheet(tester, access);

      await failManagedUnlock(
        tester,
        harness,
        _failed(
          'authManagedUnlockGoneGenerated',
          WalletAccessFailure.invalidated,
        ),
      );

      final request = harness.auth.events
          .whereType<AuthManagedSignInRequested>()
          .single;
      expect(request.generatedPassword, isTrue);
      expect(
        find.byKey(const Key('wallet-unlock-lost-recover')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('managed-wallet-unlock')), findsNothing);
      expect(access.lookups, 1);
    });

    testWidgets('a chosen password form explains the loss once', (
      tester,
    ) async {
      final harness = await pumpSheet(
        tester,
        _Access(_managed(generated: false)),
      );

      await failManagedUnlock(
        tester,
        harness,
        _failed('authManagedUnlockGone', WalletAccessFailure.missingCredential),
      );

      expect(find.byKey(const Key('create-password-field')), findsOneWidget);
      expect(find.text('authDeviceUnlockLost'.tr()), findsOneWidget);
      // The notice says it; the failure's own message would only repeat it.
      expect(find.text('authManagedUnlockGone'.tr()), findsNothing);
      // Device unlock is not offered back.
      expect(find.text('authUnlockWithDevice'.tr()), findsNothing);
    });

    testWidgets('a failure that leaves the unlock in place stays on screen', (
      tester,
    ) async {
      final harness = await pumpSheet(tester, _Access(_managed()));

      await failManagedUnlock(
        tester,
        harness,
        _failed(
          'authManagedUnlockFailedGenerated',
          WalletAccessFailure.storageFailed,
        ),
      );

      expect(find.byKey(const Key('managed-wallet-unlock')), findsOneWidget);
      expect(
        find.text('authManagedUnlockFailedGenerated'.tr()),
        findsOneWidget,
      );
    });

    testWidgets('other password prompts read the loss from the status', (
      tester,
    ) async {
      await LegalFormHarness().pump(
        tester,
        WalletPasswordGuidance.of(
          AsyncSnapshot.withData(ConnectionState.done, _lost(generated: false)),
        ),
      );

      expect(find.byKey(const Key('wallet-unlock-lost')), findsOneWidget);
      expect(find.byKey(const Key('wallet-unlock-lost-hint')), findsOneWidget);
    });

    testWidgets('the loss is announced and the recovery action named', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpSheet(tester, _Access(_lost()));

      final notice = tester
          .getSemantics(find.byKey(const Key('wallet-unlock-lost')))
          .getSemanticsData();
      expect(notice.flagsCollection.isLiveRegion, isTrue);
      expect(
        find.bySemanticsLabel('authUseRecoveryPhrase'.tr()),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}
