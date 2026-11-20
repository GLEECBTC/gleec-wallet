import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 320,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    // The app theme paints disabled elevated buttons grey.
    theme: theme.global.light,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Column(mainAxisSize: MainAxisSize.min, children: [child]),
          ),
        ),
      ),
    ),
  ),
);

Color? _fill(WidgetTester tester) => tester
    .widget<Material>(
      find.descendant(
        of: find.byType(ElevatedButton),
        matching: find.byType(Material),
      ),
    )
    .color;

void main() {
  group('UiPrimaryButton', () {
    testWidgets('takes focus only when asked, so Enter activates it', (
      tester,
    ) async {
      var presses = 0;
      await _pump(
        tester,
        UiPrimaryButton(text: 'Continue', onPressed: () => presses++),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(presses, 0);

      await _pump(
        tester,
        UiPrimaryButton(
          key: const Key('focused'),
          autofocus: true,
          text: 'Continue',
          onPressed: () => presses++,
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(presses, 2);
    });
  });

  group('UiUnderlineTextButton', () {
    testWidgets('disabled, it dims its label instead of filling with grey', (
      tester,
    ) async {
      await _pump(
        tester,
        UiUnderlineTextButton(text: 'Cancel', onPressed: () {}),
      );
      expect(_fill(tester), Colors.transparent);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      expect(tester.getSize(find.byType(UiUnderlineTextButton)).height, 48);

      await _pump(
        tester,
        const UiUnderlineTextButton(text: 'Cancel', onPressed: null),
      );
      expect(_fill(tester), Colors.transparent);
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.4);
      expect(tester.getSize(find.byType(UiUnderlineTextButton)).height, 48);
    });

    testWidgets('grows with its label only when asked', (tester) async {
      const label = 'Unlock with this device';
      await _pump(
        tester,
        UiUnderlineTextButton(text: label, onPressed: () {}),
        width: 200,
        textScale: 2,
      );
      expect(tester.getSize(find.byType(UiUnderlineTextButton)).height, 48);

      await _pump(
        tester,
        UiUnderlineTextButton(
          key: const Key('expanding'),
          expandForText: true,
          text: label,
          onPressed: () {},
        ),
        width: 200,
        textScale: 2,
      );
      final button = find.byType(UiUnderlineTextButton);
      expect(tester.getSize(button).height, greaterThan(48));
      expect(tester.getSize(button).width, 200);
      expect(
        tester
            .getRect(button)
            .inflate(1)
            .contains(tester.getRect(find.text(label)).bottomRight),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
