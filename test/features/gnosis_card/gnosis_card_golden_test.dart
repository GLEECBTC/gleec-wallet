import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(EasyLocalization.ensureInitialized);

  testWidgets('card dashboard phone light golden', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildGnosisCardPreview(
        themeMode: ThemeMode.light,
        fixture: GnosisCardPreviewFixture.dashboard,
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('gnosis-card-preview')),
      matchesGoldenFile('goldens/gnosis_card_phone_light.png'),
    );
  });

  testWidgets('card dashboard desktop dark golden', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildGnosisCardPreview(
        themeMode: ThemeMode.dark,
        fixture: GnosisCardPreviewFixture.dashboard,
      ),
    );
    await tester.pump();

    await expectLater(
      find.byKey(const Key('gnosis-card-preview')),
      matchesGoldenFile('goldens/gnosis_card_desktop_dark.png'),
    );
  });
}
