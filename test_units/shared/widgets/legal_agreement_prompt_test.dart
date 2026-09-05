import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// No public API resets the package's global translations between test groups.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/widgets/disclaimer/legal_agreement_prompt.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_view.dart';

class _EnglishAssetLoader extends AssetLoader {
  const _EnglishAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _LegalDocuments extends Fake implements LegalDocumentsRepository {
  final List<LegalDocumentType> opened = [];

  @override
  Future<LegalDocumentContent> loadPreferredContent(
    LegalDocumentType document,
  ) async {
    opened.add(document);
    return LegalDocumentContent(
      markdown: '# ${document.name}',
      source: LegalDocumentSource.bundledAsset,
    );
  }

  @override
  Future<LegalDocumentContent?> refreshFromRemote(
    LegalDocumentType document,
  ) async => null;
}

Future<void> _pump(
  WidgetTester tester, {
  required VoidCallback onAgree,
  required _LegalDocuments documents,
  Size size = const Size(800, 900),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _EnglishAssetLoader(),
      child: RepositoryProvider<LegalDocumentsRepository>.value(
        value: documents,
        child: Builder(
          builder: (context) => MaterialApp(
            theme: ThemeData.dark(),
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 440,
                    child: LegalAgreementPrompt(onAgree: onAgree),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Legal agreement prompt', () {
    setUpAll(() async {
      // The analyzer does not recognize the repository's test_units directory.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });

    // Other suites intentionally assert untranslated keys. Do not leak this
    // group's real English copy through easy_localization's global singleton.
    tearDown(() => Localization.load(const Locale('en')));
    testWidgets('names the action and puts linked agreements above it', (
      tester,
    ) async {
      var accepted = 0;
      await _pump(
        tester,
        documents: _LegalDocuments(),
        onAgree: () => accepted++,
      );

      final notice = find.byKey(const Key('legal-agreement-notice'));
      final button = find.byKey(const Key('agree-and-continue-button'));
      final text = tester.widget<Text>(notice).textSpan!;
      expect(
        text.toPlainText(includePlaceholders: false),
        'By selecting ‘Agree and continue’, you accept the  and .',
      );
      expect(find.text('EULA'), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(find.text('Agree and continue'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(
        tester.getBottomLeft(notice).dy,
        lessThan(tester.getTopLeft(button).dy),
      );
      expect(accepted, 0);

      await tester.tap(button);
      expect(accepted, 1);
    });

    for (final (key, document) in [
      ('agreement-eula-link', LegalDocumentType.eula),
      ('agreement-terms-link', LegalDocumentType.termsOfService),
    ]) {
      testWidgets('opening and closing $key never accepts the agreements', (
        tester,
      ) async {
        var accepted = 0;
        final documents = _LegalDocuments();
        await _pump(tester, documents: documents, onAgree: () => accepted++);

        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(documents.opened, [document]);
        expect(
          tester
              .widget<LegalDocumentView>(find.byType(LegalDocumentView))
              .document,
          document,
        );
        expect(accepted, 0);

        await tester.tap(find.byKey(const Key('close-disclaimer')));
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentView), findsNothing);
        expect(
          find.byKey(const Key('agree-and-continue-button')),
          findsOneWidget,
        );
        expect(accepted, 0);
      });
    }

    testWidgets('both links and the agreement action work with a keyboard', (
      tester,
    ) async {
      var accepted = 0;
      final documents = _LegalDocuments();
      await _pump(tester, documents: documents, onAgree: () => accepted++);

      for (final document in [
        LegalDocumentType.eula,
        LegalDocumentType.termsOfService,
      ]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(documents.opened.last, document);
        expect(accepted, 0);
        await tester.tap(find.byKey(const Key('close-disclaimer')));
        await tester.pumpAndSettle();
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(accepted, 1);
    });

    testWidgets('links expose labels and meet accessible target sizes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _pump(tester, documents: _LegalDocuments(), onAgree: () {});

        for (final (key, label) in [
          ('agreement-eula-link', 'EULA'),
          ('agreement-terms-link', 'Terms & Conditions'),
        ]) {
          final link = find.byKey(Key(key));
          expect(
            tester.getSemantics(link),
            matchesSemantics(
              label: label,
              isButton: true,
              isLink: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true,
              hasTapAction: true,
              hasFocusAction: true,
            ),
          );
        }
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      } finally {
        semantics.dispose();
      }
    });

    for (final (size, scale) in [
      (const Size(320, 700), 1.0),
      (const Size(320, 900), 2.0),
      (const Size(1024, 768), 1.0),
    ]) {
      testWidgets(
        'notice and action fit ${size.width}px at text scale $scale',
        (tester) async {
          await _pump(
            tester,
            documents: _LegalDocuments(),
            onAgree: () {},
            size: size,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          final button = find.byKey(const Key('agree-and-continue-button'));
          expect(
            tester.getBottomRight(button).dx,
            lessThanOrEqualTo(size.width),
          );
          expect(
            tester.getBottomRight(button).dy,
            lessThanOrEqualTo(size.height),
          );
          expect(find.text('EULA'), findsOneWidget);
          expect(find.text('Terms & Conditions'), findsOneWidget);
          expect(find.text('Agree and continue'), findsOneWidget);
        },
      );
    }
  });
}
