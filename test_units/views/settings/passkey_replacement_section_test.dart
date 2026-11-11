import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/device_protection_section.dart';

import '../../support/legal_onboarding_harness.dart';
import '../../support/wallet_access_ui_fixture.dart';

class _ReplacementAccess extends AccessibilityAccess {
  bool passkey = true;
  bool available = true;
  WalletAccessFailure? authorizationFailure;
  WalletAccessFailure? replacementFailure;
  final replacements = <(WalletId, String)>[];
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      WalletAccessStatus(
        entryId: 'replacement-entry',
        protection: passkey
            ? CredentialProtection.passkey
            : CredentialProtection.authenticationBound,
        hasManagedCredential: true,
        requiresAuthentication: true,
        generatedPassword: true,
      );
  @override
  Future<CredentialCapabilities> capabilities() async => CredentialCapabilities(
    available: true,
    protection: CredentialProtection.browserLocal,
    passkeyCandidate: available,
  );
  @override
  Future<String> authorize({
    required WalletId walletId,
    String? password,
    String reason = 'Unlock your wallet',
  }) async {
    if (authorizationFailure case final failure?) {
      authorized.add(password);
      throw WalletAccessException(failure);
    }
    return super.authorize(
      walletId: walletId,
      password: password,
      reason: reason,
    );
  }

  @override
  Future<void> replacePasskeyUsingPassword({
    required WalletId walletId,
    required String password,
  }) async {
    replacements.add((walletId, password));
    if (replacementFailure case final failure?) {
      throw WalletAccessException(failure);
    }
  }
}

Future<void> _pump(
  WidgetTester tester,
  _ReplacementAccess access, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
}) async {
  final auth = LegalFormAuth();
  // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
  auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 150));
    await auth.close();
    await access.unlockCoordinator.dispose();
  });
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const LegalEnglishLoader(),
      child: RepositoryProvider<WalletAccessService>.value(
        value: access,
        child: BlocProvider<AuthBloc>.value(
          value: auth,
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
                  disableAnimations: true,
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              ),
              home: const Scaffold(
                body: SingleChildScrollView(child: DeviceProtectionSection()),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  final button = find.byKey(const Key('replace-passkey-using-password'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('confirmation-showing-seed-phrase')),
    'known-synthetic-password',
  );
  await tester.tap(find.text('continueText'.tr()));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Replace a lost passkey from security settings', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    for (final brightness in Brightness.values) {
      testWidgets('is explicit and readable at 200% text in $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final access = _ReplacementAccess();
        await _pump(tester, access, brightness: brightness, textScale: 2);
        final button = find.byKey(const Key('replace-passkey-using-password'));
        await tester.ensureVisible(button);
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(access.authorized, isEmpty);
        expect(access.replacements, isEmpty);
        expect(find.byType(PasswordDialogContent), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'requires the known password and targets the current immutable wallet',
      (tester) async {
        final access = _ReplacementAccess();
        await _pump(tester, access);
        await _open(tester);
        expect(
          find.byKey(const Key('confirmation-showing-seed-phrase')),
          findsOneWidget,
        );
        expect(find.text('authUseDeviceUnlock'.tr()), findsNothing);
        expect(find.text('authUsePassword'.tr()), findsNothing);
        expect(access.authorized, isEmpty);
        await _submit(tester);
        expect(access.authorized, ['known-synthetic-password']);
        expect(access.replacements, [
          (accessibilityUser().walletId, 'synthetic-a11y-password'),
        ]);
        expect(find.text('authPasskeyReplaced'.tr()), findsOneWidget);
      },
    );

    testWidgets(
      'Escape cancels the password prompt and leaves a usable retry',
      (tester) async {
        final access = _ReplacementAccess();
        await _pump(tester, access);
        await _open(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
        expect(access.authorized, isEmpty);
        expect(access.replacements, isEmpty);
        await _open(tester);
        expect(find.byType(PasswordDialogContent), findsOneWidget);
        await tester.tap(find.text('cancel'.tr()));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 150));
      },
    );

    testWidgets('incorrect password never starts replacement', (tester) async {
      final access = _ReplacementAccess()
        ..authorizationFailure = WalletAccessFailure.incorrectPassword;
      await _pump(tester, access);
      await _open(tester);
      await _submit(tester);
      expect(access.replacements, isEmpty);
      expect(find.text('passwordNotAccepted'.tr()), findsOneWidget);
      await tester.tap(find.text('cancel'.tr()));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 150));
    });

    for (final failure in [
      WalletAccessFailure.canceled,
      WalletAccessFailure.storageFailed,
    ]) {
      testWidgets(
        '$failure leaves protection status intact with a safe message',
        (tester) async {
          final access = _ReplacementAccess()..replacementFailure = failure;
          await _pump(tester, access);
          await _open(tester);
          await _submit(tester);
          expect(find.text('authPasskeyProtected'.tr()), findsOneWidget);
          expect(find.text('authPasskeyReplaced'.tr()), findsNothing);
          expect(
            find.text(
              (failure == WalletAccessFailure.canceled
                      ? 'authProtectionCanceled'
                      : 'authProtectionFailed')
                  .tr(),
            ),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      'is absent for other protection methods or unavailable passkeys',
      (tester) async {
        final access = _ReplacementAccess()..passkey = false;
        await _pump(tester, access);
        expect(
          find.byKey(const Key('replace-passkey-using-password')),
          findsNothing,
        );
      },
    );
    testWidgets('is absent when passkey enrollment is disabled', (
      tester,
    ) async {
      final access = _ReplacementAccess()..available = false;
      await _pump(tester, access);
      expect(
        find.byKey(const Key('replace-passkey-using-password')),
        findsNothing,
      );
    });
  });
}
