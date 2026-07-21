part of 'gnosis_card_page_test.dart';

void _registerGnosisCardPrivacyTest() {
  testWidgets('card page remains screenshot-sensitive around secure details', (
    tester,
  ) async {
    _setViewSize(tester, const Size(1280, 900));
    final sensitivity = ScreenshotSensitivityController();
    addTearDown(sensitivity.dispose);
    final bloc = GnosisCardBloc(
      config: _mockConfig,
      coordinator: null,
      initialState: GnosisCardState(
        status: GnosisCardLoadStatus.ready,
        snapshot: gnosisCardPreviewSnapshot(),
      ),
    );
    addTearDown(bloc.close);
    final dependencies = GnosisCardDependencies.forAdapters(
      config: _mockConfig,
      secureElement: const SyntheticSecureElementGateway(),
    );

    await tester.pumpWidget(
      _pageApp(
        bloc,
        dependencies,
        sensitivity: sensitivity,
        manageLifecycle: false,
      ),
    );
    await tester.pump();
    expect(sensitivity.isSensitive, isTrue);
    await tester.tap(find.text('Details'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(sensitivity.isSensitive, isTrue);
    expect(
      find.text(
        'This opens securely outside Gleec Wallet. Return here when you are finished.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(sensitivity.isSensitive, isTrue);
  });
}
