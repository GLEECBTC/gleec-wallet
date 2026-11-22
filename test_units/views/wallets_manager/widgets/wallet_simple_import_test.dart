import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// Reset translations after the shared harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_by_file.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_simple_import.dart';

import '../../../support/legal_onboarding_harness.dart';

/// Stands in for the platform picker, which only a device can open.
class _Picker extends Fake implements FileLoader {
  Completer<void>? gate;
  String? rejection;
  int picks = 0;

  @override
  Future<void> upload({
    required void Function(String name, String? content) onUpload,
    required void Function(String) onError,
    LoadFileType? fileType,
  }) async {
    picks++;
    await gate?.future;
    final error = rejection;
    error == null ? onUpload('backup.txt', 'content') : onError(error);
  }
}

void main() {
  setUpAll(() async {
    // The analyzer does not recognize the test_units directory as test code.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));

  final button = find.byKey(const Key('confirm-seed-button'));
  final password = find.byKey(const Key('create-password-field'));
  final confirmation = find.byKey(const Key('create-password-field-confirm'));
  final importError = find.byKey(const Key('wallet-import-error'));
  bool enabled(WidgetTester tester) =>
      tester.widget<UiPrimaryButton>(button).onPressed != null;

  Future<(LegalFormHarness, List<String>, List<String>)> pumpImport(
    WidgetTester tester, {
    FileLoader? picker,
  }) async {
    final harness = LegalFormHarness();
    final imports = <String>[];
    final uploads = <String>[];
    await harness.pump(
      tester,
      WalletSimpleImport(
        fileLoader: picker,
        onImport: ({required name, required password, required walletConfig}) =>
            imports.add(name),
        onUploadFiles: ({required fileName, required fileData}) =>
            uploads.add(fileName),
        onCancel: () {},
      ),
      size: const Size(1200, 1200),
    );
    return (harness, imports, uploads);
  }

  Future<void> enterNameAndPhrase(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const Key('name-wallet-field')), name);
    await tester.enterText(
      find.byKey(const Key('import-seed-field')),
      legalTestSeed,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('import becomes enabled when matching passwords are entered', (
    tester,
  ) async {
    final (_, imports, _) = await pumpImport(tester);
    await enterNameAndPhrase(tester, 'test');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(password, findsOneWidget);
    expect(enabled(tester), isFalse);

    await tester.enterText(password, legalTestPassword);
    await tester.enterText(confirmation, legalTestPassword);
    await tester.pumpAndSettle();
    expect(enabled(tester), isTrue);

    await tester.enterText(confirmation, 'different-password');
    await tester.pumpAndSettle();
    expect(enabled(tester), isFalse);

    await tester.enterText(confirmation, legalTestPassword);
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(imports, ['test']);
  });

  testWidgets(
    'Enter continues from the phrase and imports from the last field',
    (tester) async {
      final (_, imports, _) = await pumpImport(tester);
      // Typed last, the name alone must be enough to enable Continue.
      await tester.enterText(
        find.byKey(const Key('import-seed-field')),
        legalTestSeed,
      );
      await tester.pump();
      expect(enabled(tester), isFalse);
      await tester.enterText(
        find.byKey(const Key('name-wallet-field')),
        'test',
      );
      await tester.pump();
      expect(enabled(tester), isTrue);

      await tester.showKeyboard(find.byKey(const Key('import-seed-field')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // The password step opens on its first field and names the rules.
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: password,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasPrimaryFocus,
        isTrue,
      );
      expect(
        find.byKey(const Key('create-password-requirements')),
        findsOneWidget,
      );
      expect(find.byType(Switch), findsNothing);
      await tester.enterText(password, legalTestPassword);
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      // Next reaches the confirmation, not the show-password control.
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: confirmation,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasPrimaryFocus,
        isTrue,
      );
      await tester.enterText(confirmation, legalTestPassword);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(imports, ['test']);
    },
  );

  testWidgets('a taken name is reported beside the name field', (tester) async {
    final (harness, imports, _) = await pumpImport(tester);
    harness.wallets.uniquenessError = 'taken';
    await enterNameAndPhrase(tester, 'Savings');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(password, findsNothing);
    expect(
      find.text(LocaleKeys.walletImportNameTaken.tr(args: ['Savings'])),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(enabled(tester), isFalse);

    harness.wallets.uniquenessError = null;
    await tester.enterText(
      find.byKey(const Key('name-wallet-field')),
      'Savings 2',
    );
    await tester.pump();
    expect(
      find.text(LocaleKeys.walletImportNameTaken.tr(args: ['Savings'])),
      findsNothing,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(password, findsOneWidget);
    expect(imports, isEmpty);
  });

  testWidgets('a failed import is explained on the form, not in a snackbar', (
    tester,
  ) async {
    final (harness, _, _) = await pumpImport(tester);
    await enterNameAndPhrase(tester, 'test');
    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    harness.auth.emit(
      AuthBlocState.error(
        AuthException(
          'engine detail',
          type: AuthExceptionType.generalAuthError,
        ),
      ),
    );
    // One pump delivers the state, the next draws the form's answer to it.
    await tester.pump();
    await tester.pump();
    final semantics = tester.ensureSemantics();
    expect(find.text('authImportFailed'.tr()), findsOneWidget);
    expect(
      tester.getSemantics(importError),
      containsSemantics(isLiveRegion: true),
    );
    expect(find.text('engine detail'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await tester.enterText(find.byKey(const Key('name-wallet-field')), 'next');
    await tester.pump();
    expect(importError, findsNothing);
    semantics.dispose();
  });

  testWidgets('a rejected wallet file is explained until another is picked', (
    tester,
  ) async {
    final picker = _Picker()..rejection = 'Unsupported file type';
    final (_, _, uploads) = await pumpImport(tester, picker: picker);
    final pick = find.text(LocaleKeys.walletCreationUploadFile.tr());
    final notice = find.byKey(const Key('wallet-import-file-error'));
    expect(notice, findsNothing);
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    expect(find.text('authImportFileRejected'.tr()), findsOneWidget);
    expect(tester.getSemantics(notice), containsSemantics(isLiveRegion: true));
    expect(find.text('Unsupported file type'), findsNothing);
    expect(uploads, isEmpty);

    // Picking again clears the notice before the new file is known.
    picker
      ..rejection = null
      ..gate = Completer<void>();
    await tester.tap(pick);
    await tester.pump();
    expect(notice, findsNothing);
    picker.gate!.complete();
    await tester.pumpAndSettle();
    expect(picker.picks, 2);
    expect(uploads, ['backup.txt']);
    expect(notice, findsNothing);
    semantics.dispose();
  });

  testWidgets('file import explains an unopened file and a failed import', (
    tester,
  ) async {
    final harness = LegalFormHarness();
    var imports = 0;
    await harness.pump(
      tester,
      WalletImportByFile(
        fileData: const WalletFileData(
          content: 'not an encrypted wallet file',
          name: 'backup.txt',
        ),
        onImport: ({required name, required password, required walletConfig}) =>
            imports++,
        onCancel: () {},
      ),
      size: const Size(1200, 1200),
    );
    final field = find.byKey(const Key('file-password-field'));
    expect(find.byType(Switch), findsNothing);
    expect(find.text('authImportDerivationHint'.tr()), findsOneWidget);
    // Enter on the only field submits it.
    await tester.enterText(field, 'synthetic-wrong');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.pump();
    expect(find.text('authImportFileNotOpened'.tr()), findsOneWidget);
    expect(imports, 0);
    await tester.enterText(field, 'synthetic-other');
    await tester.pump();
    expect(find.text('authImportFileNotOpened'.tr()), findsNothing);

    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    harness.auth.emit(
      AuthBlocState.error(
        AuthException(
          'engine detail',
          type: AuthExceptionType.generalAuthError,
        ),
      ),
    );
    // One pump delivers the state, the next draws the form's answer to it.
    await tester.pump();
    await tester.pump();
    expect(find.text('authImportFailed'.tr()), findsOneWidget);
    expect(find.text('engine detail'), findsNothing);
  });
}
