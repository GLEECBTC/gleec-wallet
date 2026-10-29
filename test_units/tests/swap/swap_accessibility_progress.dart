part of 'swap_accessibility_test.dart';

/// The swap screen while the engine has yet to answer for the swap.
void _progressCases(
  _Layout layout, {
  required Future<void> Function(WidgetTester, _Layout, Widget) pump,
}) {
  for (final (name, initial) in [
    ('with nothing to show yet', null),
    (
      'from Activity',
      snapshotOf(
        id: 'a-1',
        source: SwapLiquiditySource.atomic,
        routeKind: SwapRouteKind.direct,
        stage: SwapProgressStage.exchanging,
      ),
    ),
  ]) {
    testWidgets('progress: a swap the engine has yet to answer for, $name', (
      tester,
    ) async {
      final registry = SwapExecutionRegistry(
        executors: [
          FakeExecutor(SwapLiquiditySource.atomic)
            ..resumeError = TimeoutException('no answer from KDF'),
        ],
        inFlight: () async => const [],
      );
      addTearDown(registry.dispose);
      await pump(
        tester,
        layout,
        RepositoryProvider<SwapServices>.value(
          value: _Services(registry, {eth, usdc}),
          child: SwapExecutionView(
            id: 'a-1',
            context: SwapExecutionContext.activity,
            source: SwapLiquiditySource.atomic,
            initial: initial,
          ),
        ),
      );
      expect(find.text('Status update delayed'), findsOneWidget);
      await expectSwapAccessible(tester, largeText: layout.textScale > 1);
    });
  }
}
