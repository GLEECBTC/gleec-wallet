import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/model/wallets_manager_models.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Wallet legal document gates', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));
    for (final form in ['create', 'seed', 'file', 'login', 'hardware']) {
      testWidgets(
        '$form disables submission and keyboard, then recovers after Retry',
        (tester) async {
          var submitted = 0;
          final harness = LegalFormHarness(available: false);
          final child = switch (form) {
            'create' => WalletCreation(
              action: WalletsManagerAction.create,
              onCreate:
                  ({
                    required name,
                    required password,
                    walletType,
                    required rememberMe,
                  }) => submitted++,
              onCancel: () {},
            ),
            'seed' => WalletSimpleImport(
              onImport:
                  ({
                    required name,
                    required password,
                    required walletConfig,
                    required rememberMe,
                  }) => submitted++,
              onUploadFiles: ({required fileName, required fileData}) {},
              onCancel: () {},
            ),
            'file' => WalletImportByFile(
              fileData: WalletFileData(
                content: 'not-decrypted-while-gated',
                name: 'My wallet.json',
              ),
              onImport:
                  ({
                    required name,
                    required password,
                    required walletConfig,
                    required rememberMe,
                  }) => submitted++,
              onCancel: () {},
            ),
            'login' => WalletLogIn(
              wallet: legalTestWallet(),
              onLogin: (_, _, _) => submitted++,
              onCancel: () {},
            ),
            _ => HwDialogWalletSelect(onSelect: (_) => submitted++),
          };
          await harness.pump(tester, child, size: const Size(360, 800));
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
              await enterLegalField(
                tester,
                'file-password-field',
                legalTestPassword,
              );
            case 'login':
              await enterLegalField(
                tester,
                'create-password-field',
                legalTestPassword,
              );
            case 'hardware':
              await tester.tap(find.byType(InkWell).first);
              await tester.pump();
          }
          final button = find.byType(UiPrimaryButton);
          expect(tester.widget<UiPrimaryButton>(button).onPressed, isNull);
          expect(find.byTooltip(_unavailable), findsOneWidget);
          expect(find.text(_unavailable), findsOneWidget);
          final semantics = tester.ensureSemantics();
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
          await tester.ensureVisible(
            find.byKey(const Key('legal-documents-retry')),
          );
          await tester.tap(find.byKey(const Key('legal-documents-retry')));
          await tester.pumpAndSettle();
          expect(tester.widget<UiPrimaryButton>(button).onPressed, isNotNull);
          expect(find.text(_unavailable), findsNothing);
          expect(await harness.repository.readAcceptance(), isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }

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
