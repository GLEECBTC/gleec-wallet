// The lock screen as the app mounts it: in MaterialApp.builder, above the
// Navigator, in the app theme.
// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_theme/app_theme.dart';
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
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/widgets/logout_popup.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_boundary.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

/// The checkout's English, plus templates for the keys this screen adds so
/// their arguments render before the catalogue carries them.
class _English extends AssetLoader {
  const _English();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    'authUnlockWalletTitle': 'Unlock {}',
    'authSwitchWalletConfirmBody': 'You’ll sign out of {} first.',
    'authRecoverWalletConfirmBody': 'You’ll sign out of {} to recover.',
    ...jsonDecode(File('$path/en.json').readAsStringSync())
        as Map<String, dynamic>,
  };
}

class _Access extends AccessibilityAccess {
  _Access({
    this.protection = CredentialProtection.authenticationBound,
    this.managed = true,
    this.generated = true,
  });
  final CredentialProtection protection;
  final bool managed;
  final bool generated;
  Object? statusError;
  Object? authorizeError;
  Completer<void>? authorizeGate;
  final _changed = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changed.stream;
  void notifyChanged() => _changed.add(null);

  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async {
    if (statusError != null) throw statusError!;
    return WalletAccessStatus(
      entryId: 'accessibility-entry',
      protection: protection,
      hasManagedCredential: managed,
      requiresAuthentication: true,
      generatedPassword: generated,
    );
  }

  @override
  Future<bool> unlockCurrent({String? password, bool automatic = false}) async {
    final attempt = unlockCoordinator.beginUnlock(automatic: automatic);
    if (attempt == null) return false;
    authorized.add(password);
    try {
      await authorizeGate?.future;
      if (authorizeError != null) throw authorizeError!;
    } catch (_) {
      unlockCoordinator.cancelUnlock(attempt);
      rethrow;
    }
    return unlockCoordinator.completeUnlock(attempt);
  }
}

class _Trading extends Cubit<TradingStatusState> implements TradingStatusBloc {
  _Trading() : super(TradingStatusLoadSuccess());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _password = Key('wallet-lock-password');
const _submit = Key('wallet-lock-password-submit');
const _unlock = Key('wallet-lock-unlock');
const _usePassword = Key('wallet-lock-use-password');
const _switchWallet = Key('wallet-lock-switch-wallet');
const _recover = Key('wallet-lock-recover-wallet');

Future<LegalFormAuth> _pumpLocked(
  WidgetTester tester,
  _Access access, {
  Size size = const Size(390, 844),
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final auth = LegalFormAuth()
    ..emit(AuthBlocState.loggedIn(accessibilityUser()));
  final trading = _Trading();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await auth.close();
    await trading.close();
    await access.unlockCoordinator.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  access.unlockCoordinator.attachWallet(
    'accessibility-entry',
    requiresAuthentication: true,
    authenticated: true,
  );
  access.unlockCoordinator.lock();
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _English(),
      child: RepositoryProvider<WalletAccessService>.value(
        value: access,
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: auth),
            BlocProvider<TradingStatusBloc>.value(value: trading),
          ],
          child: Builder(
            builder: (context) => MaterialApp(
              theme: brightness == Brightness.dark
                  ? theme.global.dark
                  : theme.global.light,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                  disableAnimations: true,
                ),
                child: WalletAccessBoundary(child: child!),
              ),
              home: const Scaffold(body: Text('Wallet contents')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

EditableText _passwordInput(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(
    of: find.byKey(_password),
    matching: find.byType(EditableText),
  ),
);

String _hint(WidgetTester tester) => tester
    .widget<WalletAccessNotice>(
      find.byKey(const Key('wallet-generated-password-hint')),
    )
    .text;

/// "Recover wallet" as the prominent secondary button, or among the exits.
Finder _recoverAs<T extends Widget>() =>
    find.descendant(of: find.byKey(_recover), matching: find.byType(T));

Future<void> _submitPassword(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(_password), value);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));

  for (final (protection, method) in [
    (CredentialProtection.authenticationBound, 'authUnlockWithDevice'),
    (CredentialProtection.passkey, 'authUnlockWithPasskey'),
  ]) {
    testWidgets('names the wallet and labels the primary by $method', (
      tester,
    ) async {
      final access = _Access(protection: protection);
      await _pumpLocked(tester, access);
      final title = find.text(
        'authUnlockWalletTitle'.tr(args: ['Gleec Wallet']),
      );
      expect(title, findsOneWidget);
      expect(tester.widget<Text>(title).data, contains('Gleec Wallet'));
      expect(
        tester.widget<Text>(title).style?.fontSize,
        theme.global.light.textTheme.titleLarge?.fontSize,
      );
      expect(
        find.descendant(
          of: find.byKey(_unlock),
          matching: find.text(method.tr()),
        ),
        findsOneWidget,
      );
      // One primary verb: the alternative is the only "Use …" on the screen.
      expect(find.textContaining('Use '), findsOneWidget);
      expect(find.byKey(_usePassword), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(access.authorized, [null]);
      expect(access.unlockCoordinator.state.isLocked, isFalse);
    });
  }

  testWidgets('a device failure is never reported as a rejected password', (
    tester,
  ) async {
    const failure = WalletAccessException(WalletAccessFailure.lockedOut);
    final access = _Access()..authorizeError = failure;
    await _pumpLocked(tester, access);
    await tester.tap(find.byKey(_unlock));
    await tester.pumpAndSettle();
    expect(
      find.text(walletAccessFailureText(failure, passwordEntered: false)),
      findsOneWidget,
    );
    expect(find.text('passwordNotAccepted'.tr()), findsNothing);
    expect(find.byType(WalletAccessNotice), findsOneWidget);

    await tester.tap(find.byKey(_usePassword));
    await tester.pumpAndSettle();
    access.authorizeError = const WalletAccessException(
      WalletAccessFailure.incorrectPassword,
    );
    await _submitPassword(tester, 'synthetic-wrong');
    expect(find.text('passwordNotAccepted'.tr()), findsOneWidget);
    expect(access.authorized, [null, 'synthetic-wrong']);
    // Enter took focus off the field; the failure hands it back.
    expect(_passwordInput(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('a cancelled prompt is a note, not an error', (tester) async {
    final access = _Access()
      ..authorizeError = const WalletAccessException(
        WalletAccessFailure.canceled,
      );
    await _pumpLocked(tester, access);
    await tester.tap(find.byKey(_unlock));
    await tester.pumpAndSettle();
    final notice = tester.widget<WalletAccessNotice>(
      find.byType(WalletAccessNotice),
    );
    expect(notice.text, 'authUnlockCanceled'.tr());
    expect(notice.tone, WalletAccessTone.info);
  });

  testWidgets('an unreadable saved unlock is explained, with recovery first', (
    tester,
  ) async {
    final access = _Access()
      ..statusError = const WalletAccessException(
        WalletAccessFailure.invalidated,
      );
    await _pumpLocked(tester, access);
    expect(find.byKey(_password), findsOneWidget);
    final explanation = tester.widget<WalletAccessNotice>(
      find.byKey(const Key('wallet-unlock-unavailable')),
    );
    expect(explanation.text, 'authDeviceUnlockUnavailable'.tr());
    expect(_hint(tester), 'authPasswordMaybeGeneratedHint'.tr());
    // Promoted to the secondary button, and offered once.
    expect(find.byKey(_recover), findsOneWidget);
    expect(_recoverAs<UiBorderButton>(), findsOneWidget);
    expect(find.byKey(_switchWallet), findsOneWidget);
    expect(find.byKey(const Key('wallet-lock-use-enrolled')), findsNothing);
  });

  testWidgets('a password created for the user says so', (tester) async {
    await _pumpLocked(tester, _Access(managed: false));
    expect(_hint(tester), 'authGeneratedPasswordHint'.tr());
    expect(find.byKey(const Key('wallet-unlock-unavailable')), findsNothing);
    expect(_recoverAs<UiBorderButton>(), findsOneWidget);
  });

  testWidgets('a chosen password needs no explanation', (tester) async {
    await _pumpLocked(tester, _Access(managed: false, generated: false));
    expect(find.byKey(_password), findsOneWidget);
    expect(find.byType(WalletAccessNotice), findsNothing);
    expect(_recoverAs<UiUnderlineTextButton>(), findsOneWidget);
  });

  testWidgets('the password field works above the Navigator', (tester) async {
    final semantics = tester.ensureSemantics();
    final access = _Access();
    await _pumpLocked(tester, access);
    await tester.tap(find.byKey(_usePassword));
    await tester.pumpAndSettle();

    final field = find.byKey(_password);
    expect(
      find.ancestor(of: field, matching: find.byType(Navigator)),
      findsNothing,
    );
    expect(Overlay.maybeOf(tester.element(field)), isNotNull);
    expect(_passwordInput(tester).focusNode.hasFocus, isTrue);
    expect(_passwordInput(tester).obscureText, isTrue);

    await tester.tap(find.byTooltip('authShowPassword'.tr()));
    await tester.pump();
    expect(_passwordInput(tester).obscureText, isFalse);
    expect(find.byTooltip('authHidePassword'.tr()), findsOneWidget);

    final username = find
        .byType(EditableText, skipOffstage: false)
        .evaluate()
        .map((element) => element.widget as EditableText)
        .singleWhere(
          (input) =>
              input.autofillHints?.contains(AutofillHints.username) ?? false,
        );
    expect(username.controller.text, accessibilityUser().walletId.name);
    expect(username.focusNode.canRequestFocus, isFalse);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  // On desktop a click on the button takes focus off the field.
  testWidgets(
    'a wrong password keeps the field usable and focused',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final access = _Access()
        ..authorizeGate = Completer<void>()
        ..authorizeError = StateError('synthetic wrong password');
      await _pumpLocked(tester, access);
      await tester.tap(find.byKey(_usePassword));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_password), 'synthetic-wrong');
      await tester.tap(find.byKey(_submit));
      await tester.pump();
      await tester.pump();

      final busy = tester.widget<UiTextFormField>(find.byKey(_password));
      expect(busy.enabled, isTrue);
      expect(busy.readOnly, isTrue);
      expect(_passwordInput(tester).controller.text, isEmpty);
      tester.widget<UiPrimaryButton>(find.byKey(_submit)).onPressed!();
      expect(access.authorized, ['synthetic-wrong']);

      access.authorizeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('passwordNotAccepted'.tr()), findsOneWidget);
      expect(
        tester.widget<UiTextFormField>(find.byKey(_password)).readOnly,
        isFalse,
      );
      expect(_passwordInput(tester).focusNode.hasFocus, isTrue);

      access
        ..authorizeGate = null
        ..authorizeError = null;
      await _submitPassword(tester, 'synthetic-right');
      expect(access.unlockCoordinator.state.isLocked, isFalse);
    },
  );

  testWidgets('a status refresh leaves the password form in place', (
    tester,
  ) async {
    final access = _Access(managed: false, generated: false);
    await _pumpLocked(tester, access);
    await tester.enterText(find.byKey(_password), 'synthetic-partial');
    final before = tester.element(find.byKey(_password));
    access.notifyChanged();
    await tester.pumpAndSettle();
    expect(find.byKey(_unlock), findsNothing);
    expect(tester.element(find.byKey(_password)), same(before));
    expect(_passwordInput(tester).controller.text, 'synthetic-partial');
    expect(_passwordInput(tester).focusNode.hasFocus, isTrue);
  });

  // Recovery has the longer copy, so it also runs at 320 dp and 200% text.
  for (final recover in [false, true]) {
    testWidgets(
      'leaving to ${recover ? 'recover' : 'switch'} says what it is for',
      (tester) async {
        await _pumpLocked(
          tester,
          _Access(),
          size: recover ? const Size(320, 568) : const Size(390, 844),
          textScale: recover ? 2 : 1,
        );
        final exit = find.byKey(recover ? _recover : _switchWallet);
        await tester.ensureVisible(exit);
        await tester.pumpAndSettle();
        await tester.tap(exit);
        await tester.pumpAndSettle();

        final popup = tester.widget<LogOutPopup>(find.byType(LogOutPopup));
        expect(
          popup.title,
          (recover
                  ? 'authRecoverWalletConfirmTitle'
                  : 'authSwitchWalletConfirmTitle')
              .tr(),
        );
        expect(find.textContaining('Gleec Wallet'), findsOneWidget);
        expect(find.text('authSignOutActivityWarning'.tr()), findsOneWidget);
        final confirm = find.byKey(const Key('popup-confirm-logout-button'));
        expect(
          find.descendant(
            of: confirm,
            matching: find.text(
              (recover ? 'authSignOutAndRecover' : 'authSignOutAndSwitch').tr(),
            ),
          ),
          findsOneWidget,
        );
        const cancel = Key('popup-cancel-logout-button');
        for (final action in [confirm, find.byKey(cancel)]) {
          await tester.ensureVisible(action);
          await tester.pumpAndSettle();
          expect(action.hitTestable(), findsOneWidget);
          expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        }
        expect(tester.takeException(), isNull);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(LogOutPopup), findsNothing);
        expect(find.byKey(_unlock), findsOneWidget);

        await tester.ensureVisible(exit);
        await tester.pumpAndSettle();
        await tester.tap(exit);
        await tester.pumpAndSettle();
        // The host's pending state; AuthBloc owns the sign-out itself.
        tester.widget<LogOutPopup>(find.byType(LogOutPopup)).onConfirm();
        await tester.pump();
        expect(find.text('authSigningOut'.tr()), findsOneWidget);
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('password face holds at 320 dp and 200% text, $brightness', (
      tester,
    ) async {
      final access = _Access()
        ..statusError = const WalletAccessException(
          WalletAccessFailure.missingCredential,
        )
        ..authorizeError = StateError('synthetic wrong password');
      await _pumpLocked(
        tester,
        access,
        size: const Size(320, 568),
        textScale: 2,
        brightness: brightness,
      );
      await _submitPassword(tester, 'synthetic-wrong');
      expect(tester.takeException(), isNull);
      for (final key in [_password, _submit, _recover, _switchWallet]) {
        final action = find.byKey(key);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget, reason: '$key');
        expect(
          tester.getSize(action).height,
          greaterThanOrEqualTo(48),
          reason: '$key',
        );
        expect(tester.takeException(), isNull, reason: '$key');
      }
    });
  }
}
