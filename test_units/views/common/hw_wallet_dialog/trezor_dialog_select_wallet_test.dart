import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/common/hw_wallet_dialog/trezor_steps/trezor_dialog_select_wallet.dart';

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required void Function(String) onComplete,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _EmptyAssetLoader(),
      child: Builder(
        builder: (context) {
          return MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: TrezorDialogSelectWallet(onComplete: onComplete),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'tapping standard wallet does not show passphrase validation error',
    (tester) async {
      String? submittedPassphrase;
      await _pumpDialog(
        tester,
        onComplete: (value) {
          submittedPassphrase = value;
        },
      );

      await tester.tap(find.text('standardWallet'));
      await tester.pump();

      expect(submittedPassphrase, '');
      expect(find.text('passphraseIsEmpty'), findsNothing);
    },
  );

  testWidgets('hidden wallet submits entered passphrase', (tester) async {
    String? submittedPassphrase;
    await _pumpDialog(
      tester,
      onComplete: (value) {
        submittedPassphrase = value;
      },
    );

    await tester.enterText(find.byType(TextFormField), 'my-secret-passphrase');
    await tester.pump();
    await tester.tap(find.text('hiddenWallet'));
    await tester.pump();

    expect(submittedPassphrase, 'my-secret-passphrase');
    expect(find.text('passphraseIsEmpty'), findsNothing);
  });

  testWidgets(
    'hidden wallet empty submit via keyboard shows validation error and does not submit',
    (tester) async {
      String? submittedPassphrase;
      await _pumpDialog(
        tester,
        onComplete: (value) {
          submittedPassphrase = value;
        },
      );

      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(submittedPassphrase, isNull);
      expect(find.text('passphraseIsEmpty'), findsOneWidget);
    },
  );
}
