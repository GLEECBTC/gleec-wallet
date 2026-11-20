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
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/utils/validators.dart';
import 'package:web_dex/views/settings/widgets/security_settings/password_update_page.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';

import '../../support/legal_onboarding_harness.dart';
import '../../support/wallet_access_ui_fixture.dart';

const _newPassword = 'Updated-key-456!';

class _PasswordAccess extends AccessibilityAccess {
  final changesMade = <(WalletId, String?)>[];
  final saved = <(WalletId, String?)>[];
  Future<void> Function()? confirmChange;
  Completer<void>? saveGate;
  PasswordManagerOutcome outcome = PasswordManagerOutcome.accepted;
  WalletAccessFailure? saveFailure;

  PasswordChangeOutcome changeOutcome = PasswordChangeOutcome.completed;
  Object? changeFailure;

  @override
  Future<PasswordChangeOutcome> changePasswordWithOutcome({
    required WalletId walletId,
    String? currentPassword,
    required String newPassword,
  }) async {
    changesMade.add((walletId, currentPassword));
    expect(newPassword, _newPassword);
    await confirmChange?.call();
    if (changeFailure case final failure?) throw failure;
    return changeOutcome;
  }

  @override
  Future<PasswordManagerOutcome> saveToPasswordManager({
    required WalletId walletId,
    String? password,
  }) async {
    saved.add((walletId, password));
    await saveGate?.future;
    if (saveFailure case final failure?) {
      throw WalletAccessException(failure);
    }
    return outcome;
  }
}

/// The page's host of the last [_pump], which receives its way back.
late AccessibilitySecurity _security;

Future<LegalFormHarness> _pump(
  WidgetTester tester,
  _PasswordAccess access, {
  double scale = 1,
  Size size = const Size(800, 1100),
}) async {
  final harness = LegalFormHarness();
  final security = _security = AccessibilitySecurity();
  // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
  harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
  addTearDown(access.unlockCoordinator.dispose);
  addTearDown(security.close);
  await harness.pump(
    tester,
    RepositoryProvider<WalletAccessService>.value(
      value: access,
      child: BlocProvider<SecuritySettingsBloc>.value(
        value: security,
        child: const PasswordUpdatePage(),
      ),
    ),
    size: size,
    textScale: scale,
    scrollable: false,
  );
  return harness;
}

Finder _newFields() => find.byWidgetPredicate(
  (widget) =>
      widget is EditableText &&
      widget.autofillHints?.contains(AutofillHints.newPassword) == true,
);

Future<void> _submit(WidgetTester tester) async {
  final fields = _newFields();
  expect(fields, findsNWidgets(2));
  for (final field in [fields.first, fields.last]) {
    await tester.ensureVisible(field);
    await tester.enterText(field, _newPassword);
  }
  final action = find.text('updatePassword'.tr());
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Password update provider handoff', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    testWidgets(
      'login password remasks when backgrounded without disabling paste',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await LegalFormHarness().pump(
          tester,
          PasswordTextField(controller: controller, onFieldSubmitted: null),
        );
        await tester.enterText(find.byType(EditableText), _newPassword);
        await tester.tap(find.byTooltip('authShowPassword'.tr()));
        await tester.pump();
        expect(
          tester.widget<EditableText>(find.byType(EditableText)).obscureText,
          isFalse,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        final field = tester.widget<EditableText>(find.byType(EditableText));
        expect(field.obscureText, isTrue);
        expect(field.enableInteractiveSelection, isTrue);
        expect(find.byTooltip('authShowPassword'.tr()), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );

    testWidgets(
      'saves the committed password after device confirmation clears inputs',
      (tester) async {
        final access = _PasswordAccess();
        await _pump(tester, access);
        access.confirmChange = () async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          expect(
            tester
                .widgetList<EditableText>(_newFields())
                .every((field) => field.controller.text.isEmpty),
            isTrue,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        };
        await _submit(tester);
        expect(access.changesMade, [(accessibilityUser().walletId, null)]);
        expect(access.saved, [(accessibilityUser().walletId, _newPassword)]);
        expect(find.text('passwordHasChanged'.tr()), findsOneWidget);
        expect(find.text('authOfferPasswordSave'.tr()), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'uses ordinary autofill once when native saving is unavailable',
      (tester) async {
        final access = _PasswordAccess()
          ..outcome = PasswordManagerOutcome.unavailable;
        await _pump(tester, access);
        tester.testTextInput.log.clear();
        await _submit(tester);
        final saves = tester.testTextInput.log.where(
          (call) =>
              call.method == 'TextInput.finishAutofillContext' &&
              call.arguments == true,
        );
        expect(saves, hasLength(1));
        expect(access.outcomes, [PasswordManagerOutcome.unknown]);
        expect(find.text('passwordHasChanged'.tr()), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final failure in [
      WalletAccessFailure.canceled,
      WalletAccessFailure.storageFailed,
    ]) {
      testWidgets(
        '$failure from optional saving preserves password-change success',
        (tester) async {
          final access = _PasswordAccess()..saveFailure = failure;
          await _pump(tester, access);
          await _submit(tester);
          expect(access.changesMade, hasLength(1));
          expect(find.text('passwordHasChanged'.tr()), findsOneWidget);
          expect(find.text('passwordNotAccepted'.tr()), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'closing during provider confirmation does not update disposed fields',
      (tester) async {
        final access = _PasswordAccess()..saveGate = Completer<void>();
        await _pump(tester, access);
        await _submit(tester);
        expect(access.saved, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        access.saveGate!.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'wallet switching during confirmation never saves for the previous wallet',
      (tester) async {
        final access = _PasswordAccess();
        final harness = await _pump(tester, access);
        access.confirmChange = () async {
          // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
          harness.auth.emit(AuthBlocState.initial());
        };
        await _submit(tester);
        expect(access.saved, isEmpty);
        expect(find.text('passwordHasChanged'.tr()), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Enter on the last field submits the form', (tester) async {
      final access = _PasswordAccess();
      await _pump(tester, access);
      final fields = _newFields();
      await tester.enterText(fields.first, _newPassword);
      await tester.enterText(fields.last, _newPassword);
      expect(
        tester.widget<EditableText>(fields.first).textInputAction,
        TextInputAction.next,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(access.changesMade, hasLength(1));
    });

    testWidgets(
      'success is a status with its own way back, not a button dressed as one',
      (tester) async {
        final access = _PasswordAccess();
        await _pump(tester, access);
        await _submit(tester);
        final status = find.byKey(const Key('password-update-success'));
        expect(
          find.descendant(
            of: status,
            matching: find.text('passwordHasChanged'.tr()),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: status, matching: find.byType(ElevatedButton)),
          findsNothing,
        );
        expect(
          find.byKey(const Key('password-update-device-unlock-reset')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('password-update-done')));
        expect(_security.events.whereType<ResetEvent>(), hasLength(1));
      },
    );

    testWidgets('says when device unlock did not follow the new password', (
      tester,
    ) async {
      final access = _PasswordAccess()
        ..changeOutcome = PasswordChangeOutcome.deviceUnlockNeedsSetup;
      await _pump(tester, access);
      await _submit(tester);
      expect(find.text('passwordHasChanged'.tr()), findsOneWidget);
      expect(
        find.byKey(const Key('password-update-device-unlock-reset')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a password that breaks the rules shows the rule and is never sent',
      (tester) async {
        final access = _PasswordAccess();
        await _pump(tester, access);
        for (final field in [_newFields().first, _newFields().last]) {
          await tester.enterText(field, 'weak');
        }
        await tester.tap(find.byKey(const Key('password-update-submit')));
        await tester.pumpAndSettle();
        expect(find.text(validatePassword('weak')!), findsOneWidget);
        expect(access.changesMade, isEmpty);
      },
    );

    testWidgets(
      'a cancelled confirmation is announced, and the button keeps its place',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final access = _PasswordAccess()
          ..changeFailure = const WalletAccessException(
            WalletAccessFailure.canceled,
          );
        await _pump(tester, access);
        await _submit(tester);
        final error = find.byKey(const Key('password-update-error'));
        expect(
          find.descendant(
            of: error,
            matching: find.text('authConfirmationCanceled'.tr()),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .getSemantics(error)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
        );
        // Still enabled, so it kept keyboard focus for the retry.
        expect(
          tester
              .widget<ElevatedButton>(
                find.descendant(
                  of: find.byKey(const Key('password-update-submit')),
                  matching: find.byType(ElevatedButton),
                ),
              )
              .onPressed,
          isNotNull,
        );
        semantics.dispose();
      },
    );

    testWidgets('a second press while the change runs starts nothing', (
      tester,
    ) async {
      final gate = Completer<void>();
      final access = _PasswordAccess()..confirmChange = () => gate.future;
      await _pump(tester, access);
      final fields = _newFields();
      await tester.enterText(fields.first, _newPassword);
      await tester.enterText(fields.last, _newPassword);
      final submit = find.byKey(const Key('password-update-submit'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      expect(access.changesMade, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('passwordHasChanged'.tr()), findsOneWidget);
    });

    testWidgets(
      'on desktop, clicking another window keeps what was typed',
      (tester) async {
        final access = _PasswordAccess();
        await _pump(tester, access);
        final field = _newFields().first;
        await tester.enterText(field, _newPassword);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(
          tester.widget<EditableText>(field).controller.text,
          _newPassword,
        );
        // Hiding the window is leaving: nothing typed stays behind.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();
        expect(tester.widget<EditableText>(field).controller.text, isEmpty);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }),
    );

    testWidgets('remasks immediately and remains usable with large text', (
      tester,
    ) async {
      final access = _PasswordAccess();
      await _pump(tester, access, size: const Size(320, 568), scale: 2);
      final field = _newFields().first;
      await tester.ensureVisible(field);
      await tester.enterText(field, _newPassword);
      final visibility = find.byTooltip('authShowPassword'.tr()).first;
      await tester.ensureVisible(visibility);
      await tester.tap(visibility);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        tester
            .widgetList<EditableText>(_newFields())
            .every(
              (field) =>
                  field.obscureText &&
                  field.controller.text.isEmpty &&
                  !field.enableSuggestions &&
                  !field.enableIMEPersonalizedLearning &&
                  field.enableInteractiveSelection,
            ),
        isTrue,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _submit(tester);
      expect(find.text('passwordHasChanged'.tr()), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
