import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';

/// Opens a dialog labelled [label] and returns its close callback.
Future<VoidCallback> _open(WidgetTester tester, String label) async {
  late VoidCallback close;
  final host = tester.element(find.text('page'));
  unawaited(
    AppDialog.showWithCallback<void>(
      context: host,
      childBuilder: (closeDialog) {
        close = closeDialog;
        return Text(label);
      },
    ),
  );
  await tester.pumpAndSettle();
  return close;
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.global.dark,
      home: const Scaffold(body: Text('page')),
    ),
  );
}

void main() {
  group('AppDialog.showWithCallback close', () {
    testWidgets('a dialog below another closes itself, not the top one', (
      tester,
    ) async {
      await _pumpPage(tester);
      final closeLower = await _open(tester, 'lower');
      await _open(tester, 'upper');
      closeLower();
      await tester.pumpAndSettle();
      expect(find.text('lower'), findsNothing);
      expect(find.text('upper'), findsOneWidget);
    });

    for (final upperFirst in [true, false]) {
      testWidgets('two dialogs closed together both close '
          '(upper first: $upperFirst)', (tester) async {
        await _pumpPage(tester);
        final closeLower = await _open(tester, 'lower');
        final closeUpper = await _open(tester, 'upper');
        if (upperFirst) {
          closeUpper();
          closeLower();
        } else {
          closeLower();
          closeUpper();
        }
        await tester.pumpAndSettle();
        expect(find.byType(SimpleDialog), findsNothing);
        expect(find.text('page'), findsOneWidget);
      });
    }

    testWidgets('closing twice closes only this dialog', (tester) async {
      await _pumpPage(tester);
      await _open(tester, 'lower');
      final closeUpper = await _open(tester, 'upper');
      closeUpper();
      await tester.pumpAndSettle();
      closeUpper();
      await tester.pumpAndSettle();
      expect(find.text('upper'), findsNothing);
      expect(find.text('lower'), findsOneWidget);
    });
  });
}
