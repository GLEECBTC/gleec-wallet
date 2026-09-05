import 'package:easy_localization/easy_localization.dart';
// Reset translations after the shared harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_simple_import.dart';

import '../../../support/legal_onboarding_harness.dart';

void main() {
  setUpAll(() async {
    // The analyzer does not recognize the test_units directory as test code.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));

  testWidgets('import becomes enabled when matching passwords are entered', (
    tester,
  ) async {
    final harness = LegalFormHarness();
    var imports = 0;
    await harness.pump(
      tester,
      WalletSimpleImport(
        onImport:
            ({
              required name,
              required password,
              required walletConfig,
              required rememberMe,
            }) => imports++,
        onUploadFiles: ({required fileName, required fileData}) {},
        onCancel: () {},
      ),
      size: const Size(1200, 1200),
    );
    final button = find.byKey(const Key('confirm-seed-button'));
    final password = find.byKey(const Key('create-password-field'));
    final confirmation = find.byKey(const Key('create-password-field-confirm'));
    await tester.enterText(find.byKey(const Key('name-wallet-field')), 'test');
    await tester.enterText(
      find.byKey(const Key('import-seed-field')),
      legalTestSeed,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(password, findsOneWidget);
    expect(tester.widget<UiPrimaryButton>(button).onPressed, isNull);

    await tester.enterText(password, legalTestPassword);
    await tester.enterText(confirmation, legalTestPassword);
    await tester.pumpAndSettle();
    expect(tester.widget<UiPrimaryButton>(button).onPressed, isNotNull);

    await tester.enterText(confirmation, 'different-password');
    await tester.pumpAndSettle();
    expect(tester.widget<UiPrimaryButton>(button).onPressed, isNull);

    await tester.enterText(confirmation, legalTestPassword);
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(imports, 1);
  });
}
