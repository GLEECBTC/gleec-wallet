import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_boundary.dart';
import 'package:web_dex/views/common/wallet_access/wallet_setup_card.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_manager_save.dart';
import 'package:web_dex/views/settings/widgets/security_settings/device_protection_section.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_confirm_success.dart';
import 'package:web_dex/views/settings/widgets/security_settings/wallet_display_name_section.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_creation.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_manager_entry.dart';

import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

class _EmptyWallets extends Fake implements WalletsRepository {
  @override
  List<Wallet> get wallets => [];
  @override
  Stream<List<Wallet>> watchWallets() => Stream.value([]);
  @override
  Future<List<Wallet>> refreshWallets() async => [];
}

void _expectFullLabel(WidgetTester tester, Finder button, String label) {
  final text = find.descendant(of: button, matching: find.text(label));
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse, reason: label);
  expect(
    tester
        .getRect(button)
        .inflate(1)
        .contains(tester.getRect(text).bottomRight),
    isTrue,
    reason: 'Full label must fit within its action: $label',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Authentication accessibility release checks', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    for (final brightness in Brightness.values) {
      for (final profile in [
        (const Size(320, 568), 2.0),
        (const Size(844, 390), 3.0),
        (const Size(1280, 900), 1.0),
      ]) {
        final (size, scale) = profile;
        testWidgets(
          'managed unlock $brightness $size ${scale}x keeps every fallback reachable',
          (tester) async {
            final harness = LegalFormHarness();
            final access = AccessibilityAccess();
            addTearDown(access.unlockCoordinator.dispose);
            await harness.pump(
              tester,
              RepositoryProvider<WalletAccessService>.value(
                value: access,
                child: WalletLogIn(
                  wallet: legalTestWallet(),
                  onLogin: (_, _, _) {},
                  onCancel: () {},
                  onSwitchWallet: () {},
                  onRecover: () {},
                ),
              ),
              size: size,
              textScale: scale,
              brightness: brightness,
              disableAnimations: true,
            );
            _expectFullLabel(
              tester,
              find.byKey(const Key('managed-wallet-unlock')),
              'authUseDeviceUnlock'.tr(),
            );
            for (final label in [
              'authUsePassword',
              'authSwitchWallet',
              'authRecoverWallet',
            ]) {
              final action = find.text(label.tr());
              await tester.ensureVisible(action);
              await tester.pumpAndSettle();
              expect(action.hitTestable(), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          },
        );
        testWidgets(
          'entry $brightness $size ${scale}x is readable and actionable',
          (tester) async {
            final harness = LegalFormHarness();
            final semantics = tester.ensureSemantics();

            await harness.pump(
              tester,
              RepositoryProvider<WalletsRepository>.value(
                value: _EmptyWallets(),
                child: WalletsManagerEntry(
                  onAction: (_) {},
                  onWalletSelected: (_, _) {},
                  onHardwareWallet: () {},
                  onCancel: () {},
                ),
              ),
              size: size,
              textScale: scale,
              brightness: brightness,
              disableAnimations: true,
            );
            expect(tester.takeException(), isNull);
            for (final key in [
              'create-wallet-button',
              'import-wallet-button',
            ]) {
              final action = find.byKey(Key(key));
              await tester.ensureVisible(action);
              await tester.pumpAndSettle();
              expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
            }
            _expectFullLabel(
              tester,
              find.byKey(const Key('create-wallet-button')),
              'onboardingCreateWallet'.tr(),
            );
            expect(
              tester
                  .getSemantics(find.byKey(const Key('import-wallet-button')))
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              isTrue,
            );
            expect(
              tester
                  .getSemantics(find.text('onboardingTitle'.tr()))
                  .getSemanticsData()
                  .flagsCollection
                  .isHeader,
              isTrue,
            );
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantics.dispose();
          },
        );

        testWidgets(
          'security setup $brightness $size ${scale}x preserves independent actions',
          (tester) async {
            final harness = LegalFormHarness();
            final access = AccessibilityAccess()..protected = false;
            addTearDown(access.unlockCoordinator.dispose);
            // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
            harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
            await harness.pump(
              tester,
              RepositoryProvider<WalletAccessService>.value(
                value: access,
                child: Column(
                  children: [
                    WalletSetupCard(
                      hasRecoveryPhrase: false,
                      hasDeviceProtection: false,
                      onBackup: () {},
                      onProtect: () {},
                    ),
                    const DeviceProtectionSection(),
                    const WalletDisplayNameSection(),
                  ],
                ),
              ),
              size: size,
              textScale: scale,
              brightness: brightness,
              disableAnimations: true,
            );
            for (final key in [
              'wallet-setup-backup',
              'wallet-setup-protect',
              'enable-device-unlock',
              'enable-passkey-unlock',
              'rename-wallet',
            ]) {
              final action = find.byKey(Key(key));
              await tester.ensureVisible(action);
              await tester.pumpAndSettle();
              expect(action.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
            }
            await tester.tap(find.byKey(const Key('rename-wallet')));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const Key('wallet-display-name-input')),
              'Travel',
            );
            await tester.testTextInput.receiveAction(TextInputAction.done);
            await tester.pumpAndSettle();
            expect(access.renamed, ['Travel']);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'recovery completion $brightness $size ${scale}x stays readable without password step',
          (tester) async {
            final harness = LegalFormHarness();
            final security = AccessibilitySecurity();
            addTearDown(security.close);
            await harness.pump(
              tester,
              BlocProvider<SecuritySettingsBloc>.value(
                value: security,
                child: const SeedConfirmSuccess(),
              ),
              size: size,
              textScale: scale,
              brightness: brightness,
              disableAnimations: true,
            );
            expect(tester.takeException(), isNull);
            final done = find.byKey(const Key('seed-confirm-got-it'));
            await tester.ensureVisible(done);
            await tester.pumpAndSettle();
            _expectFullLabel(tester, done, 'seedPhraseGotIt'.tr());
            await tester.tap(done);
            expect(security.events.whereType<ResetEvent>(), hasLength(1));
            expect(find.byType(TextField), findsNothing);
          },
        );
      }
    }

    testWidgets(
      'managed password fallback skips hidden username and names reveal control',
      (tester) async {
        final harness = LegalFormHarness();
        final access = AccessibilityAccess();
        addTearDown(access.unlockCoordinator.dispose);
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: WalletLogIn(
              wallet: legalTestWallet(),
              onLogin: (_, _, _) {},
              onCancel: () {},
            ),
          ),
        );
        await tester.tap(find.text('authUsePassword'.tr()));
        await tester.pumpAndSettle();
        final hiddenFields = find.descendant(
          of: find.byKey(const Key('wallet-field'), skipOffstage: false),
          matching: find.byType(EditableText, skipOffstage: false),
          skipOffstage: false,
        );
        expect(hiddenFields, findsOneWidget);
        expect(
          tester.widget<EditableText>(hiddenFields).focusNode.canRequestFocus,
          isFalse,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(
          tester.widget<EditableText>(hiddenFields).focusNode.hasFocus,
          isFalse,
        );
        expect(find.byTooltip('authShowPassword'.tr()), findsOneWidget);
        await tester.tap(find.byTooltip('authShowPassword'.tr()));
        await tester.pump();
        expect(find.byTooltip('authHidePassword'.tr()), findsOneWidget);
      },
    );

    testWidgets(
      'root password cover excludes wallet semantics and respects keyboard insets',
      (tester) async {
        final harness = LegalFormHarness();
        final access = AccessibilityAccess();
        addTearDown(access.unlockCoordinator.dispose);
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loggedIn(accessibilityUser()));
        access.unlockCoordinator.attachWallet(
          'accessibility-entry',
          requiresAuthentication: true,
          authenticated: true,
        );
        access.unlockCoordinator.lock();
        final semantics = tester.ensureSemantics();

        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await harness.pump(
          tester,
          RepositoryProvider<WalletAccessService>.value(
            value: access,
            child: const WalletAccessBoundary(
              child: Text('Private wallet balance'),
            ),
          ),
          size: const Size(390, 844),
          textScale: 2,
          scrollable: false,
          disableAnimations: true,
        );
        expect(find.bySemanticsLabel('Private wallet balance'), findsNothing);
        await tester.ensureVisible(
          find.byKey(const Key('wallet-lock-use-password')),
        );
        await tester.tap(find.byKey(const Key('wallet-lock-use-password')));
        await tester.pumpAndSettle();
        final recover = find.text('authRecoverWallet'.tr());
        await tester.ensureVisible(recover);
        await tester.pumpAndSettle();
        expect(tester.getRect(recover).bottom, lessThanOrEqualTo(544));
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );

    for (final brightness in Brightness.values) {
      for (final size in [const Size(320, 568), const Size(844, 390)]) {
        testWidgets(
          'provider save $brightness $size adds no app dialog or secret semantics',
          (tester) async {
            final harness = LegalFormHarness();
            final access = AccessibilityAccess();
            addTearDown(access.unlockCoordinator.dispose);
            final semantics = tester.ensureSemantics();
            await harness.pump(
              tester,
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => offerWalletPasswordSave(
                    context,
                    access: access,
                    walletId: accessibilityUser().walletId,
                  ),
                  child: const Text('Create wallet'),
                ),
              ),
              size: size,
              textScale: size.width > 320 ? 3 : 2,
              brightness: brightness,
              disableAnimations: true,
            );
            await tester.tap(find.text('Create wallet'));
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(find.byType(TextField), findsNothing);
            expect(
              find.bySemanticsLabel(RegExp('synthetic-a11y-password')),
              findsNothing,
            );
            expect(access.authorized, isEmpty);
            expect(tester.takeException(), isNull);
            semantics.dispose();
          },
        );
      }
    }

    testWidgets(
      'reduced-motion creation keeps announced progress without a repeating ticker',
      (tester) async {
        final harness = LegalFormHarness();
        final semantics = tester.ensureSemantics();

        await harness.pump(
          tester,
          WalletCreation(
            action: WalletsManagerAction.create,
            onCreate: () {},
            onCancel: () {},
          ),
          disableAnimations: true,
        );
        // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
        harness.auth.emit(AuthBlocState.loading());
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('authCreatingWallet'.tr()), findsWidgets);
        expect(tester.binding.transientCallbackCount, 0);
        semantics.dispose();
      },
    );

    testWidgets(
      'primary-button text expansion is opt-in and preserves default height',
      (tester) async {
        final harness = LegalFormHarness();
        await harness.pump(
          tester,
          Column(
            children: [
              UiPrimaryButton(
                key: const Key('fixed-button'),
                height: 52,
                text: 'Continue',
                onPressed: () {},
              ),
              UiPrimaryButton(
                key: const Key('expanding-button'),
                height: 52,
                expandForText: true,
                text: 'Continue with this wallet',
                onPressed: () {},
              ),
            ],
          ),
          textScale: 3,
        );
        expect(
          tester.getSize(find.byKey(const Key('fixed-button'))).height,
          52,
        );
        expect(
          tester.getSize(find.byKey(const Key('expanding-button'))).height,
          greaterThan(52),
        );
        _expectFullLabel(
          tester,
          find.byKey(const Key('expanding-button')),
          'Continue with this wallet',
        );
      },
    );

    for (final brightness in Brightness.values) {
      testWidgets(
        'setup card $brightness has labeled touch targets and readable contrast',
        (tester) async {
          final harness = LegalFormHarness();
          final semantics = tester.ensureSemantics();
          await harness.pump(
            tester,
            WalletSetupCard(
              hasRecoveryPhrase: false,
              hasDeviceProtection: false,
              onBackup: () {},
              onProtect: () {},
            ),
            brightness: brightness,
          );
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantics.dispose();
        },
      );
    }
  });
}
