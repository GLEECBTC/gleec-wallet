import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
// No public API resets the global translations between aggregated suites.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/hw_dialog_wallet_select.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_creation.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_by_file.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_simple_import.dart';

import '../../../support/legal_onboarding_harness.dart';

Future<void> _fillPasswords(WidgetTester tester) async {
  await enterLegalField(tester, 'create-password-field', legalTestPassword);
  await enterLegalField(
    tester,
    'create-password-field-confirm',
    legalTestPassword,
  );
}

void _expectInlineNotice(WidgetTester tester, {required bool updated}) {
  expect(
    find.byKey(const Key('legal-agreements-updated')),
    updated ? findsOneWidget : findsNothing,
  );
  expect(find.byKey(const Key('legal-agreement-notice')), findsOneWidget);
  expect(find.byKey(const Key('agree-and-continue-button')), findsNothing);
  expect(find.byKey(const Key('checkbox-eula-tos')), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Form submission owns legal acceptance', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    for (final updated in [false, true]) {
      for (final keyboard in [false, true]) {
        testWidgets(
          'create accepts only on valid submission (updated: $updated, keyboard: $keyboard)',
          (tester) async {
            final harness = LegalFormHarness(updated: updated);
            var created = 0;
            await harness.pump(
              tester,
              WalletCreation(
                action: WalletsManagerAction.create,
                onCreate:
                    ({
                      required name,
                      required password,
                      walletType,
                      required rememberMe,
                    }) => created++,
                onCancel: () {},
              ),
            );
            _expectInlineNotice(tester, updated: updated);
            final oldRecord = await harness.repository.readAcceptance();
            expect(
              tester
                  .widget<UiPrimaryButton>(
                    find.byKey(const Key('confirm-password-button')),
                  )
                  .onPressed,
              isNull,
            );
            expect(created, 0);
            expect(
              (await harness.repository.readAcceptance())?.surface,
              oldRecord?.surface,
            );
            await enterLegalField(tester, 'name-wallet-field', 'My wallet');
            await _fillPasswords(tester);
            if (keyboard) {
              await tester.testTextInput.receiveAction(TextInputAction.done);
              await tester.pumpAndSettle();
              await tester.pump();
            } else {
              await tapLegalSubmit(tester, 'confirm-password-button');
            }
            expect(created, 1);
            expect(
              (await harness.repository.readAcceptance())?.surface,
              'wallet-creation',
            );
            expect(await harness.repository.hasAcceptedCurrentTerms(), isTrue);
          },
        );
      }

      testWidgets(
        'seed import accepts on final Import only (updated: $updated)',
        (tester) async {
          final harness = LegalFormHarness(updated: updated);
          var imported = 0;
          await harness.pump(
            tester,
            WalletSimpleImport(
              onImport:
                  ({
                    required name,
                    required password,
                    required walletConfig,
                    required rememberMe,
                  }) => imported++,
              onUploadFiles: ({required fileName, required fileData}) {},
              onCancel: () {},
            ),
          );
          final oldRecord = await harness.repository.readAcceptance();
          expect(find.byKey(const Key('legal-agreement-notice')), findsNothing);
          await enterLegalField(tester, 'name-wallet-field', 'My wallet');
          await enterLegalField(tester, 'import-seed-field', legalTestSeed);
          await tapLegalSubmit(tester, 'confirm-seed-button');
          expect(imported, 0);
          expect(
            (await harness.repository.readAcceptance())?.surface,
            oldRecord?.surface,
          );
          _expectInlineNotice(tester, updated: updated);
          await _fillPasswords(tester);
          await tapLegalSubmit(tester, 'confirm-seed-button');
          expect(imported, 1);
          expect(
            (await harness.repository.readAcceptance())?.surface,
            'wallet-import-seed',
          );
          expect(await harness.repository.hasAcceptedCurrentTerms(), isTrue);
        },
      );

      testWidgets(
        'file import accepts after successful decryption (updated: $updated)',
        (tester) async {
          final harness = LegalFormHarness(updated: updated);
          final encrypted = await tester.runAsync(() async {
            final tool = EncryptionTool();
            final config = WalletConfig(
              seedPhrase: await tool.encryptData(
                legalTestPassword,
                legalTestSeed,
              ),
              activatedCoins: [],
              hasBackup: true,
              type: WalletType.hdwallet,
            );
            return tool.encryptData(
              legalTestPassword,
              jsonEncode(config.toJson()),
            );
          });
          var imported = 0;
          await harness.pump(
            tester,
            WalletImportByFile(
              fileData: WalletFileData(
                content: encrypted!,
                name: 'My wallet.json',
              ),
              onImport:
                  ({
                    required name,
                    required password,
                    required walletConfig,
                    required rememberMe,
                  }) => imported++,
              onCancel: () {},
            ),
          );
          _expectInlineNotice(tester, updated: updated);
          final oldRecord = await harness.repository.readAcceptance();
          await enterLegalField(
            tester,
            'file-password-field',
            'wrong password',
          );
          await tapLegalSubmit(tester, 'confirm-password-button');
          expect(imported, 0);
          expect(
            (await harness.repository.readAcceptance())?.surface,
            oldRecord?.surface,
          );
          await enterLegalField(
            tester,
            'file-password-field',
            legalTestPassword,
          );
          await tapLegalSubmit(tester, 'confirm-password-button');
          expect(imported, 1);
          expect(
            (await harness.repository.readAcceptance())?.surface,
            'wallet-import-file',
          );
          expect(await harness.repository.hasAcceptedCurrentTerms(), isTrue);
        },
      );

      testWidgets('login accepts on its ordinary button (updated: $updated)', (
        tester,
      ) async {
        final harness = LegalFormHarness(updated: updated);
        var loggedIn = 0;
        await harness.pump(
          tester,
          WalletLogIn(
            wallet: legalTestWallet(),
            onLogin: (_, _, _) => loggedIn++,
            onCancel: () {},
          ),
        );
        _expectInlineNotice(tester, updated: updated);
        final oldRecord = await harness.repository.readAcceptance();
        await enterLegalField(
          tester,
          'create-password-field',
          legalTestPassword,
        );
        expect(
          (await harness.repository.readAcceptance())?.surface,
          oldRecord?.surface,
        );
        await tester.ensureVisible(find.text('Log In'));
        await tester.tap(find.text('Log In'));
        await tester.pumpAndSettle();
        await tester.pump();
        expect(loggedIn, 1);
        expect(
          (await harness.repository.readAcceptance())?.surface,
          'wallet-login',
        );
        expect(await harness.repository.hasAcceptedCurrentTerms(), isTrue);
      });

      testWidgets(
        'hardware accepts on Continue, not device selection (updated: $updated)',
        (tester) async {
          final harness = LegalFormHarness(updated: updated);
          var selected = 0;
          await harness.pump(
            tester,
            HwDialogWalletSelect(onSelect: (_) => selected++),
          );
          _expectInlineNotice(tester, updated: updated);
          final oldRecord = await harness.repository.readAcceptance();
          await tester.tap(find.byType(InkWell).first);
          await tester.pump();
          expect(selected, 0);
          expect(
            (await harness.repository.readAcceptance())?.surface,
            oldRecord?.surface,
          );
          await tester.ensureVisible(find.text('Continue'));
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          await tester.pump();
          expect(selected, 1);
          expect(
            (await harness.repository.readAcceptance())?.surface,
            'wallet-hardware',
          );
          expect(await harness.repository.hasAcceptedCurrentTerms(), isTrue);
        },
      );
    }

    testWidgets('duplicate wallet name and cancellation do not accept', (
      tester,
    ) async {
      final harness = LegalFormHarness(updated: true);
      harness.wallets.uniquenessError = 'Name already exists';
      var created = 0;
      var cancelled = 0;
      await harness.pump(
        tester,
        WalletCreation(
          action: WalletsManagerAction.create,
          onCreate:
              ({
                required name,
                required password,
                walletType,
                required rememberMe,
              }) => created++,
          onCancel: () => cancelled++,
        ),
      );
      await enterLegalField(tester, 'name-wallet-field', 'My wallet');
      await _fillPasswords(tester);
      await tapLegalSubmit(tester, 'confirm-password-button');
      expect(created, 0);
      expect((await harness.repository.readAcceptance())?.surface, 'old-form');
      await tester.ensureVisible(find.text('Cancel'));
      await tester.tap(find.text('Cancel'));
      expect(cancelled, 1);
      expect((await harness.repository.readAcceptance())?.surface, 'old-form');
    });
  });
}
