import 'dart:ui' show Tristate;

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_show.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_word_button.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_confirmation/seed_confirmation.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Recovery accessibility release checks', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() {
      Localization.load(const Locale('en'));
      // ignore: invalid_use_of_visible_for_testing_member
      resetScreenType();
    });
    for (final brightness in Brightness.values) {
      testWidgets(
        'phrase confirmation $brightness keeps selected words and controls readable at 300%',
        (tester) async {
          final harness = LegalFormHarness();
          final security = AccessibilitySecurity();
          final sessions = AuthSessionTracker()..observe(accessibilityUser());
          addTearDown(security.close);
          addTearDown(sessions.dispose);
          await harness.pump(
            tester,
            BlocProvider<SecuritySettingsBloc>.value(
              value: security,
              child: Builder(
                builder: (context) {
                  updateScreenType(context);
                  return SeedConfirmation(
                    seedPhrase: legalTestSeed,
                    session: sessions.current!,
                  );
                },
              ),
            ),
            size: const Size(320, 568),
            textScale: 3,
            brightness: brightness,
            disableAnimations: true,
          );
          final word = find.byType(SeedWordButton).first;
          await tester.ensureVisible(word);
          await tester.tap(word);
          await tester.pumpAndSettle();
          expect(tester.widget<SeedWordButton>(word).isSelected, isTrue);
          expect(
            tester
                .widget<UiPrimaryButton>(
                  find.byKey(const Key('seed-confirm-check-button')),
                )
                .onPressed,
            isNull,
          );
          for (var index = 1; index < 12; index++) {
            final next = find.byType(SeedWordButton).at(index);
            await tester.ensureVisible(next);
            await tester.tap(next);
            await tester.pumpAndSettle();
          }
          for (final key in [
            'seed-confirm-clear-button',
            'seed-confirm-check-button',
          ]) {
            final button = find.byKey(Key(key));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
            expect(button.hitTestable(), findsOneWidget);
          }
          await tester.tap(find.byKey(const Key('seed-confirm-clear-button')));
          await tester.pumpAndSettle();
          expect(
            tester
                .widgetList<SeedWordButton>(find.byType(SeedWordButton))
                .any((word) => word.isSelected),
            isFalse,
          );
          expect(tester.takeException(), isNull);
        },
      );
      for (final shown in [false, true]) {
        testWidgets(
          'recovery words $brightness shown=$shown remain legible at large text',
          (tester) async {
            final harness = LegalFormHarness();
            final security = AccessibilitySecurity();
            addTearDown(security.close);
            // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
            security.emit(security.state.copyWith(showSeedWords: shown));
            final semantics = tester.ensureSemantics();
            await harness.pump(
              tester,
              BlocProvider<SecuritySettingsBloc>.value(
                value: security,
                child: Builder(
                  builder: (context) {
                    updateScreenType(context);
                    return const SeedShow(
                      seedPhrase: legalTestSeed,
                      privKeys: {},
                    );
                  },
                ),
              ),
              size: const Size(320, 568),
              textScale: 2,
              brightness: brightness,
              disableAnimations: true,
            );
            expect(tester.takeException(), isNull);
            final switchNode = tester
                .getSemantics(find.byKey(const Key('seed-show-switch')))
                .getSemanticsData();
            expect(
              switchNode.flagsCollection.isToggled,
              shown ? Tristate.isTrue : Tristate.isFalse,
            );
            final fields = find.descendant(
              of: find.byType(UiTextFormField),
              matching: find.byType(EditableText),
            );
            expect(fields, findsNWidgets(12));
            for (final element in fields.evaluate()) {
              final field = find.byWidget(element.widget);
              await tester.ensureVisible(field);
              await tester.pumpAndSettle();
              final render = tester
                  .state<EditableTextState>(field)
                  .renderEditable;
              expect(
                render.size.height,
                greaterThanOrEqualTo(render.preferredLineHeight),
                reason: 'Each recovery word must fit vertically at 200% text.',
              );
              final data = tester.getSemantics(field).getSemanticsData();
              if (!shown) expect(data.value, isNot(contains('abandon')));
            }
            semantics.dispose();
          },
        );
      }
    }
    testWidgets(
      'confirmation word has selected semantics and keyboard activation at large text',
      (tester) async {
        final harness = LegalFormHarness();
        final semantics = tester.ensureSemantics();
        var presses = 0;
        await harness.pump(
          tester,
          SeedWordButton(
            text: 'synthetic confirmation word',
            onPressed: () => presses++,
            isSelected: true,
          ),
          textScale: 3,
        );
        final word = find.byType(SeedWordButton);
        expect(tester.getSize(word).height, greaterThanOrEqualTo(48));
        final data = tester.getSemantics(word).getSemanticsData();
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isSelected, Tristate.isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(presses, 1);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  });
}
