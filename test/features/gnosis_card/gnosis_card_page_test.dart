import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/gnosis_card/application/gnosis_card_bloc.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_config.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/gnosis_card_dependencies.dart';
import 'package:web_dex/features/gnosis_card/infrastructure/synthetic_secure_element_gateway.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_page.dart';
import 'package:web_dex/features/gnosis_card/presentation/gnosis_card_preview.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

void main() {
  for (final size in <Size>[const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('disabled card recovers cleanly at ${size.width}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final config = const GnosisCardConfig(
        mode: GnosisCardMode.disabled,
        scenario: GnosisCardScenario.happyPath,
        failureReason: 'Cards are disabled in this build.',
      );
      final dependencies = GnosisCardDependencies.forAdapters(
        config: config,
        secureElement: const SyntheticSecureElementGateway(),
      );
      final bloc = GnosisCardBloc(config: config, coordinator: null)
        ..add(const GnosisCardStarted());
      addTearDown(bloc.close);

      await tester.pumpWidget(
        RepositoryProvider.value(
          value: dependencies,
          child: BlocProvider.value(
            value: bloc,
            child: MaterialApp(
              theme: ThemeData.light(useMaterial3: true),
              home: const Scaffold(body: GnosisCardPage()),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Cards are unavailable'), findsOneWidget);
      expect(find.text('Cards are disabled in this build.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dashboard tolerates large text, reduced motion, and keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_readyApp(accessible: true));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);

    expect(find.text('Available to spend'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secure element marks card details screenshot-sensitive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sensitivity = ScreenshotSensitivityController();
    addTearDown(sensitivity.dispose);

    await tester.pumpWidget(_readyApp(sensitivity: sensitivity));
    await tester.pump();
    await tester.tap(find.text('Details'));
    await tester.pump();

    expect(find.text('Card details'), findsOneWidget);
    expect(sensitivity.isSensitive, isTrue);
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(sensitivity.isSensitive, isFalse);
  });
}

Widget _readyApp({
  ScreenshotSensitivityController? sensitivity,
  bool accessible = false,
}) {
  const config = GnosisCardConfig(
    mode: GnosisCardMode.mock,
    scenario: GnosisCardScenario.happyPath,
    failureReason: null,
  );
  final dependencies = GnosisCardDependencies.forAdapters(
    config: config,
    secureElement: const SyntheticSecureElementGateway(),
  );
  Widget child = RepositoryProvider.value(
    value: dependencies,
    child: BlocProvider(
      create: (_) => GnosisCardBloc(
        config: config,
        coordinator: null,
        initialState: GnosisCardState(
          status: GnosisCardLoadStatus.ready,
          snapshot: gnosisCardPreviewSnapshot(),
        ),
      ),
      child: MaterialApp(
        builder: accessible
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              )
            : null,
        home: const Scaffold(body: GnosisCardPage()),
      ),
    ),
  );
  if (sensitivity != null) {
    child = ScreenshotSensitivity(controller: sensitivity, child: child);
  }
  return child;
}
