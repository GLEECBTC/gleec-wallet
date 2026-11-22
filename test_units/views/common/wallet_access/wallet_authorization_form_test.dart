// The two authorization dialogs share one form; the sign-in sheet shares its
// buttons and wording.
// ignore_for_file: invalid_use_of_visible_for_testing_member
// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/widgets/quick_login_switch.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_password_dialog.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

class _Access extends AccessibilityAccess {
  _Access({this.protection = CredentialProtection.authenticationBound});
  final CredentialProtection protection;
  Object? statusError;
  Object? authorizeError;
  Completer<void>? authorizeGate;
  bool managed = true;

  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async {
    if (statusError != null) throw statusError!;
    return WalletAccessStatus(
      entryId: 'accessibility-entry',
      protection: protection,
      hasManagedCredential: managed,
      requiresAuthentication: true,
      generatedPassword: true,
    );
  }

  @override
  Future<String> authorize({
    required WalletId walletId,
    String? password,
    String reason = 'Unlock your wallet',
  }) async {
    authorized.add(password);
    await authorizeGate?.future;
    if (authorizeError != null) throw authorizeError!;
    return 'synthetic-a11y-password';
  }
}

const _exportPassword = Key('private-key-export-password');
const _exportSubmit = Key('private-key-export-password-submit');
const _authorizePassword = Key('confirmation-showing-operation');

/// Both dialogs, so one expectation covers the pair.
final _dialogs = <String, (Key, Widget Function(VoidCallback onCancel))>{
  'authorization': (
    _authorizePassword,
    (onCancel) => PasswordDialogContentWithLoading(
      wallet: accessibilityUser().wallet,
      onPasswordValidated: (_) async => true,
      onComplete: (_) {},
      onCancel: onCancel,
    ),
  ),
  'key export': (
    _exportPassword,
    (onCancel) => PrivateKeyExportPasswordDialog(
      walletName: accessibilityUser().walletId.name,
      isLoading: false,
      onSubmit: (_) {},
      onCancel: onCancel,
    ),
  ),
};

Future<void> _pumpDialog(
  WidgetTester tester,
  Widget dialog,
  _Access access, {
  bool settle = true,
}) async {
  final harness = LegalFormHarness();
  harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
  addTearDown(access.unlockCoordinator.dispose);
  await harness.pump(
    tester,
    RepositoryProvider<WalletAccessService>.value(value: access, child: dialog),
    disableAnimations: true,
  );
  if (settle) await tester.pumpAndSettle();
}

EditableText _input(WidgetTester tester, Key field) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(field),
        matching: find.byType(EditableText),
      ),
    );

Finder get _continue =>
    find.widgetWithText(UiPrimaryButton, 'continueText'.tr());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));

  for (final MapEntry(key: name, value: (field, build)) in _dialogs.entries) {
    group('$name dialog', () {
      testWidgets('opens on the enrolled method with one steady title', (
        tester,
      ) async {
        final access = _Access();
        await _pumpDialog(tester, build(() {}), access);
        expect(find.text('authAuthorizationTitle'.tr()), findsOneWidget);
        expect(find.text('authConfirmWithDevice'.tr()), findsOneWidget);
        expect(find.byKey(field), findsNothing);
        // Enter goes to the primary action without a click first.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(access.authorized, [null]);
      });

      testWidgets('switches to the password and back', (tester) async {
        final access = _Access(protection: CredentialProtection.passkey);
        await _pumpDialog(tester, build(() {}), access);
        await tester.tap(find.text('authUsePassword'.tr()));
        await tester.pumpAndSettle();
        expect(find.text('authAuthorizationTitle'.tr()), findsOneWidget);
        expect(_input(tester, field).focusNode.hasFocus, isTrue);
        final username = find
            .byType(EditableText, skipOffstage: false)
            .evaluate()
            .map((element) => element.widget as EditableText)
            .singleWhere(
              (input) =>
                  input.autofillHints?.contains(AutofillHints.username) ??
                  false,
            );
        expect(username.focusNode.canRequestFocus, isFalse);

        await tester.tap(find.text('authUsePasskey'.tr()));
        await tester.pumpAndSettle();
        expect(find.byKey(field), findsNothing);
        expect(find.text('authConfirmWithDevice'.tr()), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(access.authorized, [null]);
      });

      testWidgets('a device failure is not blamed on a password', (
        tester,
      ) async {
        const failure = WalletAccessException(WalletAccessFailure.lockedOut);
        final access = _Access()..authorizeError = failure;
        await _pumpDialog(tester, build(() {}), access);
        await tester.tap(_continue);
        await tester.pumpAndSettle();
        final notice = tester.widget<WalletAccessNotice>(
          find.byType(WalletAccessNotice),
        );
        expect(
          notice.text,
          walletAccessFailureText(
            failure,
            passwordEntered: false,
            unlocking: false,
          ),
        );
        expect(notice.tone, WalletAccessTone.error);
        expect(find.text('passwordNotAccepted'.tr()), findsNothing);
        // The failed method's message does not follow to the other one.
        await tester.tap(find.text('authUsePassword'.tr()));
        await tester.pumpAndSettle();
        expect(find.text(notice.text), findsNothing);
      });

      testWidgets('Escape cancels', (tester) async {
        var cancelled = 0;
        await _pumpDialog(tester, build(() => cancelled++), _Access());
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(cancelled, 1);
      });

      testWidgets('explains a saved unlock that cannot be read', (
        tester,
      ) async {
        final access = _Access()
          ..statusError = const WalletAccessException(
            WalletAccessFailure.missingCredential,
          );
        await _pumpDialog(tester, build(() {}), access);
        expect(find.byKey(field), findsOneWidget);
        expect(
          find.byKey(const Key('wallet-unlock-unavailable')),
          findsOneWidget,
        );
        expect(find.text('authUsePassword'.tr()), findsNothing);
      });
    });
  }

  testWidgets('a wrong password leaves the authorization field focused', (
    tester,
  ) async {
    final access = _Access()
      ..managed = false
      ..authorizeGate = Completer<void>()
      ..authorizeError = const WalletAccessException(
        WalletAccessFailure.incorrectPassword,
      );
    await _pumpDialog(tester, _dialogs['authorization']!.$2(() {}), access);
    await tester.enterText(find.byKey(_authorizePassword), 'synthetic-wrong');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    final busy = tester.widget<UiTextFormField>(find.byKey(_authorizePassword));
    expect(busy.enabled, isTrue);
    expect(busy.readOnly, isTrue);
    expect(_input(tester, _authorizePassword).controller.text, isEmpty);

    access.authorizeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('passwordNotAccepted'.tr()), findsOneWidget);
    expect(_input(tester, _authorizePassword).focusNode.hasFocus, isTrue);
    expect(access.authorized, ['synthetic-wrong']);
  });

  testWidgets('the export dialog refocuses its field for the owner’s error', (
    tester,
  ) async {
    final props = ValueNotifier<({bool loading, String? error})>((
      loading: false,
      error: null,
    ));
    addTearDown(props.dispose);
    await _pumpDialog(
      tester,
      ValueListenableBuilder(
        valueListenable: props,
        builder: (_, value, _) => PrivateKeyExportPasswordDialog(
          walletName: accessibilityUser().walletId.name,
          isLoading: value.loading,
          errorText: value.error,
          onSubmit: (_) {},
          onCancel: () {},
        ),
      ),
      _Access()..managed = false,
    );
    await tester.enterText(find.byKey(_exportPassword), 'synthetic-wrong');
    await tester.tap(find.byKey(_exportSubmit));
    props.value = (loading: true, error: null);
    await tester.pump();
    expect(
      tester.widget<UiTextFormField>(find.byKey(_exportPassword)).readOnly,
      isTrue,
    );
    props.value = (loading: false, error: 'Incorrect password');
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(WalletAccessNotice, 'Incorrect password'),
      findsOneWidget,
    );
    expect(_input(tester, _exportPassword).focusNode.hasFocus, isTrue);
  });

  group('sign-in sheet', () {
    Future<LegalFormHarness> pumpSheet(
      WidgetTester tester,
      _Access? access, {
      VoidCallback? onSwitchWallet,
      VoidCallback? onCancel,
      void Function(String, Wallet, bool)? onLogin,
      bool remembered = false,
    }) async {
      final harness = LegalFormHarness();
      final sheet = WalletLogIn(
        wallet: legalTestWallet(),
        initialQuickLogin: remembered,
        onLogin: onLogin ?? (_, _, _) {},
        onCancel: onCancel ?? () {},
        onSwitchWallet: onSwitchWallet,
        onRecover: () {},
      );
      await harness.pump(
        tester,
        access == null
            ? sheet
            : RepositoryProvider<WalletAccessService>.value(
                value: access,
                child: sheet,
              ),
        disableAnimations: true,
      );
      await tester.pumpAndSettle();
      return harness;
    }

    List<String> exits(WidgetTester tester) => tester
        .widgetList<UiUnderlineTextButton>(find.byType(UiUnderlineTextButton))
        .map((button) => button.text)
        .toList();

    testWidgets('offers Switch wallet only when Cancel does not lead there', (
      tester,
    ) async {
      await pumpSheet(tester, _Access());
      expect(exits(tester), ['authRecoverWallet'.tr(), 'cancel'.tr()]);
      await tester.tap(find.text('authUsePassword'.tr()));
      await tester.pumpAndSettle();
      expect(exits(tester), ['authRecoverWallet'.tr(), 'cancel'.tr()]);
    });

    testWidgets('Escape cancels from either face', (tester) async {
      var cancelled = 0;
      await pumpSheet(tester, _Access(), onCancel: () => cancelled++);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelled, 1);
      await tester.tap(find.text('authUsePassword'.tr()));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelled, 2);
    });

    testWidgets('keeps one order of actions and one wording on both faces', (
      tester,
    ) async {
      final access = _Access(protection: CredentialProtection.passkey);
      await pumpSheet(tester, access, onSwitchWallet: () {});
      final all = [
        'authSwitchWallet'.tr(),
        'authRecoverWallet'.tr(),
        'cancel'.tr(),
      ];
      String consent() => tester
          .widget<Text>(find.byKey(const Key('legal-agreement-notice')))
          .textSpan!
          .toPlainText();

      expect(exits(tester), all);
      expect(
        find.widgetWithText(UiPrimaryButton, 'authUnlockWithPasskey'.tr()),
        findsOneWidget,
      );
      expect(consent(), contains('authUnlockWithPasskey'.tr()));
      expect(
        find.text('authUnlockWalletTitle'.tr(args: ['My wallet'])),
        findsOneWidget,
      );

      await tester.tap(find.text('authUsePassword'.tr()));
      await tester.pumpAndSettle();
      expect(exits(tester), all);
      expect(
        find.widgetWithText(UiPrimaryButton, 'authUnlock'.tr()),
        findsOneWidget,
      );
      expect(consent(), contains('authUnlock'.tr()));
      expect(consent(), isNot(contains('authUnlockWithPasskey'.tr())));
      expect(
        find.text('authUnlockWalletTitle'.tr(args: ['My wallet'])),
        findsOneWidget,
      );
      // The way back names the method, as the primary did.
      expect(
        find.widgetWithText(UiBorderButton, 'authUnlockWithPasskey'.tr()),
        findsOneWidget,
      );
    });

    testWidgets('has no Quick Login switch and hands the flag back unchanged', (
      tester,
    ) async {
      final remembered = <bool>[];
      await pumpSheet(
        tester,
        null,
        remembered: true,
        onLogin: (_, _, flag) => remembered.add(flag),
      );
      expect(find.byType(QuickLoginSwitch), findsNothing);
      expect(find.byType(Switch), findsNothing);
      await tester.enterText(
        find.byKey(const Key('create-password-field')),
        legalTestPassword,
      );
      await tester.tap(find.byKey(const Key('wallet-password-unlock')));
      await tester.pumpAndSettle();
      await tester.pump();
      expect(remembered, [true]);
    });

    testWidgets('explains a missing saved unlock and leads with recovery', (
      tester,
    ) async {
      final access = _Access()
        ..statusError = const WalletAccessException(
          WalletAccessFailure.invalidated,
        );
      await pumpSheet(tester, access);
      expect(find.byKey(const Key('create-password-field')), findsOneWidget);
      expect(
        find.byKey(const Key('wallet-unlock-unavailable')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(UiBorderButton, 'authRecoverWallet'.tr()),
        findsOneWidget,
      );
      expect(exits(tester), ['cancel'.tr()]);
    });

    testWidgets('a failed password hands focus back to the field', (
      tester,
    ) async {
      final harness = await pumpSheet(tester, null);
      final field = find.byKey(const Key('create-password-field'));
      await tester.enterText(field, 'synthetic-wrong');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      const key = Key('create-password-field');
      expect(_input(tester, key).focusNode.hasFocus, isFalse);
      harness.auth.emit(
        AuthBlocState.error(
          AuthException(
            'Incorrect password',
            type: AuthExceptionType.incorrectPassword,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(WalletAccessNotice, 'incorrectPassword'.tr()),
        findsOneWidget,
      );
      expect(_input(tester, key).focusNode.hasFocus, isTrue);
    });
  });
}
