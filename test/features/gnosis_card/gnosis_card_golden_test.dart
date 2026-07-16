import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await EasyLocalization.ensureInitialized();
    final manrope = FontLoader('Manrope');
    for (final asset in const [
      'assets/fonts/Manrope-ExtraLight.ttf',
      'assets/fonts/Manrope-Light.ttf',
      'assets/fonts/Manrope-Regular.ttf',
      'assets/fonts/Manrope-Medium.ttf',
      'assets/fonts/Manrope-SemiBold.ttf',
      'assets/fonts/Manrope-Bold.ttf',
      'assets/fonts/Manrope-ExtraBold.ttf',
    ]) {
      manrope.addFont(rootBundle.load(asset));
    }
    await manrope.load();
  });

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
