import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart'
    show DerivationMethod;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_file/wallet_file_codec.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_by_file.dart';

import '../../../support/legacy_wallet_file_writer.dart';
import '../../../support/legal_onboarding_harness.dart';

class _Imported {
  WalletConfig? config;
  String? password;
}

WalletConfig _config(WalletType type) => WalletConfig(
  seedPhrase: '',
  activatedCoins: ['KMD'],
  hasBackup: true,
  type: type,
);

Future<String> _currentFile(WalletType type, {String phrase = legalTestSeed}) =>
    const WalletFileCodec().seal(
      password: legalTestPassword,
      mnemonic: phrase,
      config: _config(type),
      derivation: type == WalletType.hdwallet
          ? DerivationMethod.hdWallet
          : DerivationMethod.iguana,
    );

Future<_Imported> _pump(
  WidgetTester tester,
  LegalFormHarness harness,
  String? content,
) async {
  final imported = _Imported();
  await harness.pump(
    tester,
    WalletImportByFile(
      fileData: WalletFileData(content: content!, name: 'My wallet.txt'),
      onImport: ({required name, required password, required walletConfig}) =>
          imported
            ..config = walletConfig
            ..password = password,
      onCancel: () {},
    ),
  );
  return imported;
}

/// Opening a current file derives its key in a background isolate, which the
/// widget clock cannot advance: real time passes, then the frame is flushed.
Future<void> _submit(WidgetTester tester, bool Function() settled) async {
  final button = find.byKey(const Key('confirm-password-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
  for (var i = 0; i < 400 && !settled(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

bool _shows(String text) => find.text(text).evaluate().isNotEmpty;

final _typeChoice = find.byKey(const Key('wallet-import-type-dropdown'));
final _legacyNotice = find.byKey(const Key('wallet-file-legacy-notice'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Wallet import by file', () {
    setUpAll(() async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    for (final type in [WalletType.iguana, WalletType.hdwallet]) {
      testWidgets('a current ${type.name} file restores its type unasked', (
        tester,
      ) async {
        final harness = LegalFormHarness();
        final file = await tester.runAsync(() => _currentFile(type));
        final imported = await _pump(tester, harness, file);
        expect(_typeChoice, findsNothing);
        expect(_legacyNotice, findsNothing);

        await enterLegalField(tester, 'file-password-field', legalTestPassword);
        await _submit(tester, () => imported.config != null);

        expect(imported.config?.type, type);
        expect(imported.config?.seedPhrase, legalTestSeed);
        expect(imported.config?.hasBackup, isFalse);
        expect(imported.password, legalTestPassword);
      });
    }

    testWidgets('the import button shows progress while the file opens', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      final file = await tester.runAsync(
        () => _currentFile(WalletType.hdwallet),
      );
      final imported = await _pump(tester, harness, file);
      await enterLegalField(tester, 'file-password-field', legalTestPassword);
      final button = find.byKey(const Key('confirm-password-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(
        find.descendant(
          of: button,
          matching: find.byType(WalletAccessProgress),
        ),
        findsOneWidget,
      );
      await _submit(tester, () => imported.config != null);
      expect(imported.config, isNotNull);
      expect(find.byType(WalletAccessProgress), findsNothing);
    });

    testWidgets('the wallet gets the password that opened its file', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      final file = await tester.runAsync(
        () => _currentFile(WalletType.hdwallet),
      );
      final imported = await _pump(tester, harness, file);
      await enterLegalField(tester, 'file-password-field', legalTestPassword);
      final button = find.byKey(const Key('confirm-password-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      final editable = find.descendant(
        of: find.byKey(const Key('file-password-field')),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(editable).readOnly, isTrue);
      // Even a change that gets past the read-only field is not used.
      tester.widget<EditableText>(editable).controller.text = 'changed';
      await _submit(tester, () => imported.config != null);
      expect(imported.password, legalTestPassword);
      expect(tester.widget<EditableText>(editable).readOnly, isFalse);
    });

    testWidgets('a current iguana file with a custom phrase stays iguana', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      const custom = 'my own words, not a bip39 phrase';
      final file = await tester.runAsync(
        () => _currentFile(WalletType.iguana, phrase: custom),
      );
      final imported = await _pump(tester, harness, file);
      final notBip39 = 'walletCreationBip39SeedError'.tr();
      await enterLegalField(tester, 'file-password-field', legalTestPassword);
      await _submit(tester, () => _shows(notBip39));
      expect(imported.config, isNull);
      expect(_typeChoice, findsNothing);

      // The same confirmation a typed custom phrase asks for.
      await tester.ensureVisible(find.byKey(const Key('checkbox-custom-seed')));
      await tester.tap(find.byKey(const Key('checkbox-custom-seed')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('custom-seed-dialog-input')),
        'customSeedIUnderstand'.tr(),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('custom-seed-dialog-ok-button')));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await _submit(tester, () => imported.config != null);

      expect(imported.config?.type, WalletType.iguana);
      expect(imported.config?.seedPhrase, custom);
    });

    testWidgets('a wrong password leaves the file closed', (tester) async {
      final harness = LegalFormHarness();
      final file = await tester.runAsync(
        () => _currentFile(WalletType.hdwallet),
      );
      final imported = await _pump(tester, harness, file);
      final error = 'authImportFileNotOpened'.tr();
      await enterLegalField(tester, 'file-password-field', 'wrong password');
      await _submit(tester, () => _shows(error));
      expect(find.text(error), findsOneWidget);
      expect(imported.config, isNull);
    });

    testWidgets('an HD file whose phrase is not BIP39 is never made legacy', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      final file = await tester.runAsync(
        () => _currentFile(WalletType.hdwallet, phrase: 'not a bip39 phrase'),
      );
      final imported = await _pump(tester, harness, file);
      final damaged = 'authImportFileDamaged'.tr();
      await enterLegalField(tester, 'file-password-field', legalTestPassword);
      await _submit(tester, () => _shows(damaged));
      expect(find.text(damaged), findsOneWidget);
      expect(_typeChoice, findsNothing);
      expect(imported.config, isNull);
    });

    testWidgets('a legacy file asks for the type and suggests a new file', (
      tester,
    ) async {
      final harness = LegalFormHarness();
      // The file says HD; nothing authenticates that, so the choice decides.
      final file = await tester.runAsync(
        () => legacyWalletFile(
          legalTestPassword,
          _config(WalletType.hdwallet),
          legalTestSeed,
        ),
      );
      final imported = await _pump(tester, harness, file);
      expect(_typeChoice, findsOneWidget);
      expect(find.text('authImportFileLegacyTypeHint'.tr()), findsOneWidget);
      expect(_legacyNotice, findsOneWidget);
      final notice = tester.widget<WalletAccessNotice>(_legacyNotice);
      expect(notice.tone, WalletAccessTone.info);
      expect(notice.announce, isFalse);

      await tester.ensureVisible(_typeChoice);
      await tester.tap(_typeChoice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('walletImportTypeLegacyLabel'.tr()).last);
      await tester.pumpAndSettle();
      await enterLegalField(tester, 'file-password-field', legalTestPassword);
      await _submit(tester, () => imported.config != null);

      expect(imported.config?.type, WalletType.iguana);
      expect(imported.config?.seedPhrase, legalTestSeed);
    });

    final unreadable = <String, (String, String)>{
      'newer': (
        jsonEncode({'format': 'gleec-wallet-file', 'version': 3}),
        'authImportFileNewer',
      ),
      'damaged': (
        jsonEncode({'format': 'gleec-wallet-file', 'version': 2}),
        'authImportFileDamaged',
      ),
      'truncated': (
        '{"format": "gleec-wallet-file", "version": 2, "wallet": {"type": "hd',
        'authImportFileDamaged',
      ),
    };
    for (final MapEntry(key: name, value: (content, message))
        in unreadable.entries) {
      testWidgets('a $name file is explained and cannot be submitted', (
        tester,
      ) async {
        final harness = LegalFormHarness();
        await _pump(tester, harness, content);
        expect(
          find.descendant(
            of: find.byKey(const Key('wallet-file-unreadable')),
            matching: find.text(message.tr()),
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('file-password-field')), findsNothing);
        expect(find.byKey(const Key('confirm-password-button')), findsNothing);
        expect(_typeChoice, findsNothing);
      });
    }
  });
}
