import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_password_dialog.dart';

const _passwordFieldKey = Key('private-key-export-password');
const _submitKey = Key('private-key-export-password-submit');
const _cancelKey = Key('private-key-export-password-cancel');
const _passwordSentinel = 'synthetic-password-for-export';

class _AssetLoader extends AssetLoader {
  const _AssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    LocaleKeys.confirmationForShowingSeedPhraseTitle: 'Enter wallet password',
    LocaleKeys.enterThePassword: 'Enter your password',
    LocaleKeys.fetchingPrivateKeysTitle: 'Fetching Private Keys...',
    LocaleKeys.fetchingPrivateKeysMessage: 'Please wait for your private keys.',
    LocaleKeys.continueText: 'Continue',
    LocaleKeys.cancel: 'Cancel',
  };
}

void main() => testPrivateKeyExportPasswordDialog();

void testPrivateKeyExportPasswordDialog() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrivateKeyExportPasswordDialog', () {
    testWidgets('submits a redacted wrapper and clears input before callback', (
      tester,
    ) async {
      final submitted = <SensitiveString>[];
      await _pumpDialog(
        tester,
        onSubmit: (password) {
          expect(_controller(tester).text, isEmpty);
          submitted.add(password);
        },
      );
      await tester.enterText(find.byKey(_passwordFieldKey), _passwordSentinel);

      final field = tester.widget<UiTextFormField>(
        find.byKey(_passwordFieldKey),
      );
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      expect(
        tester
            .widget<PrivateKeyExportPasswordDialog>(
              find.byType(PrivateKeyExportPasswordDialog),
            )
            .toStringDeep(),
        isNot(contains(_passwordSentinel)),
      );

      // Invoke both entry points before the owning flow can rebuild as loading.
      field.onFieldSubmitted!(_passwordSentinel);
      tester.widget<UiPrimaryButton>(find.byKey(_submitKey)).onPressed!();
      await tester.pump();

      expect(submitted, hasLength(1));
      expect(submitted.single.value, _passwordSentinel);
      expect(submitted.single.toString(), isNot(contains(_passwordSentinel)));
      expect(_controller(tester).text, isEmpty);
      expect(
        tester.testTextInput.log.where(
          (call) => call.method == 'TextInput.finishAutofillContext',
        ),
        isNotEmpty,
      );
      expect(
        tester.testTextInput.log
            .where((call) => call.method == 'TextInput.finishAutofillContext')
            .every((call) => call.arguments == false),
        isTrue,
      );
    });

    testWidgets(
      'loading prevents submissions and keeps cancellation available',
      (tester) async {
        var submissions = 0;
        var cancellations = 0;
        await _pumpDialog(
          tester,
          isLoading: true,
          onSubmit: (_) => submissions++,
          onCancel: () => cancellations++,
        );

        final field = tester.widget<UiTextFormField>(
          find.byKey(_passwordFieldKey),
        );
        expect(field.enabled, isFalse);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Fetching Private Keys...'), findsOneWidget);
        expect(
          tester.widget<UiPrimaryButton>(find.byKey(_submitKey)).onPressed,
          isNull,
        );
        field.controller!.text = _passwordSentinel;
        field.onFieldSubmitted!(_passwordSentinel);
        expect(submissions, 0);

        await tester.tap(find.byKey(_cancelKey));
        await tester.pump();
        expect(cancellations, 1);
        expect(field.controller!.text, isEmpty);
        expect(submissions, 0);
      },
    );

    testWidgets('renders errors and allows retry after loading completes', (
      tester,
    ) async {
      final submitted = <SensitiveString>[];
      await _pumpDialog(tester, onSubmit: submitted.add);
      await tester.enterText(find.byKey(_passwordFieldKey), _passwordSentinel);
      await tester.tap(find.byKey(_submitKey));
      await tester.pump();
      await _pumpDialog(tester, isLoading: true, onSubmit: submitted.add);
      await _pumpDialog(
        tester,
        errorText: 'Incorrect password',
        onSubmit: submitted.add,
      );

      expect(find.text('Incorrect password'), findsOneWidget);
      expect(_controller(tester).text, isEmpty);
      expect(
        tester.widget<UiTextFormField>(find.byKey(_passwordFieldKey)).enabled,
        isTrue,
      );
      await tester.enterText(find.byKey(_passwordFieldKey), 'synthetic-retry');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted.map((value) => value.value), [
        _passwordSentinel,
        'synthetic-retry',
      ]);
    });

    testWidgets('cancellation clears input without submitting or navigating', (
      tester,
    ) async {
      var cancellations = 0;
      var submissions = 0;
      await _pumpDialog(
        tester,
        onCancel: () => cancellations++,
        onSubmit: (_) => submissions++,
      );
      await tester.enterText(find.byKey(_passwordFieldKey), _passwordSentinel);
      await tester.tap(find.byKey(_cancelKey));
      await tester.pump();

      expect(cancellations, 1);
      expect(submissions, 0);
      expect(_controller(tester).text, isEmpty);
      expect(find.byType(PrivateKeyExportPasswordDialog), findsOneWidget);
    });

    testWidgets('disposal clears input and releases screenshot sensitivity', (
      tester,
    ) async {
      final sensitivity = ScreenshotSensitivityController();
      addTearDown(sensitivity.dispose);
      await _pumpDialog(tester, sensitivity: sensitivity);
      await tester.enterText(find.byKey(_passwordFieldKey), _passwordSentinel);
      final controller = _controller(tester);
      expect(sensitivity.isSensitive, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(() => controller.addListener(() {}), throwsFlutterError);
      expect(sensitivity.isSensitive, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact height scrolls to cancellation without overflow', (
      tester,
    ) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(320, 240);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var cancellations = 0;
      await _pumpDialog(
        tester,
        isLoading: true,
        onCancel: () => cancellations++,
      );

      await tester.ensureVisible(find.byKey(_cancelKey));
      await tester.pump();
      await tester.tap(find.byKey(_cancelKey));
      await tester.pump();

      expect(cancellations, 1);
      expect(tester.takeException(), isNull);
    });
  });
}

TextEditingController _controller(WidgetTester tester) =>
    tester.widget<UiTextFormField>(find.byKey(_passwordFieldKey)).controller!;

Future<void> _pumpDialog(
  WidgetTester tester, {
  bool isLoading = false,
  String? errorText,
  ValueChanged<SensitiveString>? onSubmit,
  VoidCallback? onCancel,
  ScreenshotSensitivityController? sensitivity,
}) async {
  final dialog = PrivateKeyExportPasswordDialog(
    walletName: 'Synthetic wallet',
    isLoading: isLoading,
    errorText: errorText,
    onSubmit: onSubmit ?? (_) {},
    onCancel: onCancel ?? () {},
  );
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _AssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Scaffold(
            body: Center(
              child: sensitivity == null
                  ? dialog
                  : ScreenshotSensitivity(
                      controller: sensitivity,
                      child: dialog,
                    ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
