import 'dart:ui' show Tristate;

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
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/device_protection_section.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Security settings accessibility release checks', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));
    for (final brightness in Brightness.values) {
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
          final options = find.byType(ChoiceChip);
          expect(options, findsNWidgets(2));
          for (var i = 0; i < 2; i++) {
            await tester.ensureVisible(options.at(i));
            await tester.pumpAndSettle();
            expect(
              tester
                  .getSemantics(options.at(i))
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              i == 1 ? Tristate.isTrue : Tristate.isFalse,
            );
            expect(options.at(i).hitTestable(), findsOneWidget);
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
