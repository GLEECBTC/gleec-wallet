import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_notice.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/hw_dialog_wallet_select.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_creation.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_by_file.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_simple_import.dart';

import '../../../support/legal_onboarding_harness.dart';

const _unavailable =
    'The legal documentation could not be retrieved. Please consult Gleec’s online legal documentation before proceeding.';

Future<void> _passwords(WidgetTester tester) async {
  await enterLegalField(tester, 'create-password-field', legalTestPassword);
  await enterLegalField(
    tester,
    'create-password-field-confirm',
    legalTestPassword,
  );
}

Widget _form(String form, VoidCallback submitted, {String? fileContent}) =>
    switch (form) {
      'create' => WalletCreation(
        action: WalletsManagerAction.create,
        onCreate:
            ({
              required name,
              required password,
              walletType,
              required rememberMe,
            }) => submitted(),
        onCancel: () {},
      ),
      'seed' => WalletSimpleImport(
        onImport:
            ({
              required name,
              required password,
              required walletConfig,
              required rememberMe,
            }) => submitted(),
        onUploadFiles: ({required fileName, required fileData}) {},
        onCancel: () {},
      ),
      'file' => WalletImportByFile(
        fileData: WalletFileData(
          content: fileContent ?? 'not-decrypted-while-gated',
          name: 'My wallet.json',
        ),
        onImport:
            ({
              required name,
              required password,
              required walletConfig,
              required rememberMe,
            }) => submitted(),
        onCancel: () {},
      ),
      'login' => WalletLogIn(
        wallet: legalTestWallet(),
        onLogin: (_, _, _) => submitted(),
        onCancel: () {},
      ),
      _ => HwDialogWalletSelect(onSelect: (_) => submitted()),
    };

Future<void> _fillForm(WidgetTester tester, String form) async {
  switch (form) {
    case 'create':
      await enterLegalField(tester, 'name-wallet-field', 'My wallet');
      await _passwords(tester);
    case 'seed':
      await enterLegalField(tester, 'name-wallet-field', 'My wallet');
      await enterLegalField(tester, 'import-seed-field', legalTestSeed);
      await tapLegalSubmit(tester, 'confirm-seed-button');
      await _passwords(tester);
    case 'file':
      await enterLegalField(tester, 'file-password-field', legalTestPassword);
    case 'login':
      await enterLegalField(tester, 'create-password-field', legalTestPassword);
    case 'hardware':
      await tester.tap(find.byType(InkWell).first);
      await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Wallet legal document gates', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));
    for (final brightness in Brightness.values) {
      for (final status in [
        LegalDocumentStatus.unavailable,
        LegalDocumentStatus.placeholder,
      ]) {
        testWidgets('failure notice wraps at 200% text, $brightness $status', (
          tester,
        ) async {
          final harness = LegalFormHarness();
          var retries = 0;
          await harness.pump(
            tester,
            LegalDocumentNotice(status: status, onRetry: () => retries++),
            size: const Size(360, 800),
            textScale: 2,
            brightness: brightness,
          );
          final retry = find.byKey(const Key('legal-documents-retry'));
          await tester.ensureVisible(retry);
          expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
          await tester.tap(retry);
          expect(retries, 1);
          expect(find.text('View legal documents'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
    for (final form in ['create', 'seed', 'file', 'login', 'hardware']) {
      for (final succeeds in [false, true]) {
        testWidgets('$form waits for the first fetch, succeeds=$succeeds', (
          tester,
        ) async {
          final response = Completer<void>();
          final harness = LegalFormHarness(
            available: false,
            responseGate: response.future,
          )..remoteAvailable = succeeds;
          String? fileContent;
          if (form == 'file') {
            fileContent = await tester.runAsync(() async {
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
          }
          var submitted = 0;
          await harness.pump(
            tester,
            _form(form, () => submitted++, fileContent: fileContent),
          );
          await _fillForm(tester, form);
          final button = find.byType(UiPrimaryButton);
          expect(tester.widget<UiPrimaryButton>(button).onPressed, isNotNull);
          expect(
            find.byKey(const Key('legal-documents-unavailable')),
            findsNothing,
          );
          expect(find.text('Loading legal documentation…'), findsNothing);
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.tap(button);
          if (form != 'hardware') {
            await tester.testTextInput.receiveAction(TextInputAction.done);
          }
          await tester.pump();
          expect(submitted, 0);
          expect(await harness.repository.readAcceptance(), isNull);
          response.complete();
          await tester.pumpAndSettle();
          await tester.pump();
          expect(submitted, succeeds ? 1 : 0);
          final acceptance = await harness.repository.readAcceptance();
          if (succeeds) {
            expect(acceptance, isNotNull);
            expect(
              acceptance!.documentShas,
              harness.agreement.presentedSnapshot!.documentShas,
            );
          } else {
            expect(acceptance, isNull);
            expect(tester.widget<UiPrimaryButton>(button).onPressed, isNull);
            expect(find.text(_unavailable), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
      testWidgets(
        '$form disables submission and keyboard, then recovers after Retry',
        (tester) async {
          var submitted = 0;
          final harness = LegalFormHarness(available: false);
          final child = _form(form, () => submitted++);
          await harness.pump(tester, child, size: const Size(360, 800));
          await _fillForm(tester, form);
          final button = find.byType(UiPrimaryButton);
          expect(tester.widget<UiPrimaryButton>(button).onPressed, isNull);
          expect(find.byTooltip(_unavailable), findsOneWidget);
          expect(find.text(_unavailable), findsOneWidget);
          final semantics = tester.ensureSemantics();
          final materialButton = find.descendant(
            of: button,
            matching: find.byType(ElevatedButton),
          );
          expect(
            tester.widget<ElevatedButton>(materialButton).onPressed,
            isNull,
          );
          expect(
            tester
                .getSemantics(materialButton)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isFalse,
          );
          expect(
            tester
                .getSemantics(
                  find.byKey(const Key('legal-documents-unavailable')),
                )
                .label,
            contains(_unavailable),
          );
          semantics.dispose();
          await tester.ensureVisible(button);
          await tester.tap(button, warnIfMissed: false);
          if (form != 'hardware') {
            await tester.testTextInput.receiveAction(TextInputAction.done);
          } else {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          }
          await tester.pumpAndSettle();
          expect(submitted, 0);
          expect(await harness.repository.readAcceptance(), isNull);
          harness.remoteAvailable = true;
          final retryResponse = Completer<void>();
          harness.responseGate = retryResponse.future;
          await tester.ensureVisible(
            find.byKey(const Key('legal-documents-retry')),
          );
          await tester.tap(find.byKey(const Key('legal-documents-retry')));
          await tester.pump();
          expect(find.text(_unavailable), findsOneWidget);
          expect(find.text('Loading legal documentation…'), findsNothing);
          expect(tester.widget<UiPrimaryButton>(button).onPressed, isNull);
          retryResponse.complete();
          await tester.pumpAndSettle();
          expect(tester.widget<UiPrimaryButton>(button).onPressed, isNotNull);
          expect(find.text(_unavailable), findsNothing);
          expect(await harness.repository.readAcceptance(), isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('closing a form cancels a submission waiting for documents', (
      tester,
    ) async {
      final response = Completer<void>();
      final harness = LegalFormHarness(
        available: false,
        responseGate: response.future,
      )..remoteAvailable = true;
      var submitted = 0;
      await harness.pump(tester, _form('login', () => submitted++));
      await _fillForm(tester, 'login');
      await tester.tap(find.byType(UiPrimaryButton));
      await tester.pumpWidget(const SizedBox.shrink());
      response.complete();
      await tester.pumpAndSettle();
      expect(submitted, 0);
      expect(await harness.repository.readAcceptance(), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'preview bypass keeps the notice and permits login without acceptance',
      (tester) async {
        final harness = LegalFormHarness(available: false, bypass: true);
        var loggedIn = 0;
        await harness.pump(
          tester,
          WalletLogIn(
            wallet: legalTestWallet(),
            onLogin: (_, _, _) => loggedIn++,
            onCancel: () {},
          ),
        );
        await enterLegalField(
          tester,
          'create-password-field',
          legalTestPassword,
        );
        expect(find.text(_unavailable), findsOneWidget);
        expect(find.textContaining('By selecting'), findsNothing);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(loggedIn, 1);
        expect(await harness.repository.readAcceptance(), isNull);
      },
    );
  });
}
