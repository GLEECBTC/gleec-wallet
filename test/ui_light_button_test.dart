import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/ui/ui_light_button.dart';

void main() {
  testWidgets('keeps its action target and grows safely at 200% text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var presses = 0;
    const buttonKey = Key('scaled-light-button');

    Future<Size> pumpAtScale(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: false,
            extensions: const <ThemeExtension<dynamic>>[GleecGeometry.standard],
          ),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Center(
                child: UiLightButton(
                  key: buttonKey,
                  width: 112,
                  height: 48,
                  text: 'Recover',
                  onPressed: () => presses += 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byKey(buttonKey));
    }

    final normalSize = await pumpAtScale(1);
    final scaledSize = await pumpAtScale(2);

    expect(normalSize.width, 112);
    expect(normalSize.height, greaterThanOrEqualTo(48));
    expect(scaledSize.width, 112);
    expect(scaledSize.height, greaterThan(normalSize.height));

    await tester.tap(find.byKey(buttonKey));
    await tester.pump();
    expect(presses, 1);
  });
}
