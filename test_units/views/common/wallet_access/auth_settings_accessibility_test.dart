import 'dart:ui' show CheckedState;

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_lock_policy.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/device_protection_section.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

class _ManagerStatusAccess extends AccessibilityAccess {
  _ManagerStatusAccess(
    this.outcome, {
    this.passkey = false,
    this.generated = true,
  });
  final PasswordManagerOutcome outcome;
  final bool passkey;
  final bool generated;
  @override
  Future<WalletAccessStatus> status({walletId}) async {
    final previous = await super.status(walletId: walletId);
    return WalletAccessStatus(
      entryId: previous.entryId,
      protection: passkey ? CredentialProtection.passkey : previous.protection,
      hasManagedCredential: previous.hasManagedCredential,
      requiresAuthentication: previous.requiresAuthentication,
      generatedPassword: generated,
      passwordManager: outcome,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Security settings accessibility release checks', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));
    // Only a password the wallet created and no manager holds is worth a
    // line: the user cannot answer a password prompt from memory.
    for (final outcome in PasswordManagerOutcome.values) {
      for (final generated in [true, false]) {
        testWidgets(
          'password-manager $outcome (generated: $generated) is mentioned '
          'only when informative, with no app save action',
          (tester) async {
            final access = _ManagerStatusAccess(outcome, generated: generated);
            final harness = LegalFormHarness();
            addTearDown(access.unlockCoordinator.dispose);
            // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
            harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
            await harness.pump(
              tester,
              RepositoryProvider<WalletAccessService>.value(
                value: access,
                child: const DeviceProtectionSection(),
              ),
            );
            final informative =
                generated &&
                (outcome == PasswordManagerOutcome.declined ||
                    outcome == PasswordManagerOutcome.failed);
            expect(
              find.text('authGeneratedPasswordNotSaved'.tr()),
              informative ? findsOneWidget : findsNothing,
            );
            for (final retired in [
              'authPasswordManagerAutomatic',
              'authPasswordManagerAccepted',
              'authPasswordManagerDeclined',
              'authPasswordManagerFailed',
              'authPasswordManagerUnavailable',
              'authPasswordManagerUnknown',
            ]) {
              expect(find.text(retired.tr()), findsNothing, reason: retired);
            }
            expect(find.byKey(const Key('save-wallet-password')), findsNothing);
            expect(find.byType(AlertDialog), findsNothing);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
    for (final brightness in Brightness.values) {
      testWidgets(
        'passkey settings $brightness meets text contrast and target guidelines',
        (tester) async {
          final semantics = tester.ensureSemantics();
          final access = _ManagerStatusAccess(
            PasswordManagerOutcome.accepted,
            passkey: true,
          );
          // The kit takes its custom colours from the app-wide theme mode,
          // which the app keeps in step with the Material theme.
          theme.mode = brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light;
          addTearDown(() => theme.mode = ThemeMode.dark);
          final harness = LegalFormHarness();
          addTearDown(access.unlockCoordinator.dispose);
          // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
          harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
          await harness.pump(
            tester,
            RepositoryProvider<WalletAccessService>.value(
              value: access,
              child: const DeviceProtectionSection(),
            ),
            brightness: brightness,
            size: const Size(900, 1600),
            contentWidth: 600,
            disableAnimations: true,
          );
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          semantics.dispose();
        },
      );
      testWidgets(
        'protected settings $brightness announces the selected grace interval',
        (tester) async {
          final harness = LegalFormHarness();
          final access = AccessibilityAccess();
          addTearDown(access.unlockCoordinator.dispose);
          // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
          harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
          final semantics = tester.ensureSemantics();
          await harness.pump(
            tester,
            RepositoryProvider<WalletAccessService>.value(
              value: access,
              child: const DeviceProtectionSection(),
            ),
            brightness: brightness,
            size: const Size(320, 568),
            textScale: 2,
            disableAnimations: true,
          );
          // One radio per offered interval; the default, 30 seconds, is
          // the checked one of a mutually exclusive group.
          final options = find.byType(RadioListTile<int>);
          expect(options, findsNWidgets(walletLockGraceOptions.length));
          for (var i = 0; i < walletLockGraceOptions.length; i++) {
            await tester.ensureVisible(options.at(i));
            await tester.pumpAndSettle();
            final flags = tester
                .getSemantics(options.at(i))
                .getSemanticsData()
                .flagsCollection;
            expect(flags.isInMutuallyExclusiveGroup, isTrue);
            expect(
              flags.isChecked,
              i == 1 ? CheckedState.isTrue : CheckedState.isFalse,
            );
            expect(options.at(i).hitTestable(), findsOneWidget);
            expect(
              tester.getSize(options.at(i)).height,
              greaterThanOrEqualTo(48),
            );
          }
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );

      testWidgets(
        'fresh authorization $brightness supports a named keyboard password fallback',
        (tester) async {
          final harness = LegalFormHarness();
          final access = AccessibilityAccess();
          addTearDown(access.unlockCoordinator.dispose);
          // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
          harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
          await harness.pump(
            tester,
            RepositoryProvider<WalletAccessService>.value(
              value: access,
              child: PasswordDialogContent(
                wallet: accessibilityUser().wallet,
                onSuccess: (_) {},
                onCancel: () {},
              ),
            ),
            brightness: brightness,
            size: const Size(320, 568),
            textScale: 2,
            disableAnimations: true,
          );
          final fallback = find.text('authUsePassword'.tr());
          await tester.ensureVisible(fallback);
          await tester.tap(fallback);
          await tester.pumpAndSettle();
          final fields = find.byType(EditableText, skipOffstage: false);
          final username = fields
              .evaluate()
              .map((element) => element.widget as EditableText)
              .singleWhere(
                (field) =>
                    field.autofillHints?.contains(AutofillHints.username) ??
                    false,
              );
          expect(username.focusNode.canRequestFocus, isFalse);
          final reveal = find.byTooltip('authShowPassword'.tr());
          await tester.ensureVisible(reveal);
          expect(reveal.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
