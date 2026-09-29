// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

part of 'swap_accessibility_test.dart';

/// Swap sheets opened over a page, as the app opens them.
void _sheetCases(
  _Layout layout, {
  required Future<void> Function(WidgetTester, _Layout, Widget) pump,
  required SwapServices Function() services,
}) {
  testWidgets('picker: searching with the keyboard up', (tester) async {
    const keyboard = 336.0;
    final catalog = SwapCatalog(
      sources: [
        SwapSourceAssets(
          source: SwapLiquiditySource.routed,
          quotable: {
            eth,
            for (var i = 0; i < 6; i++) assetOf('TK$i-ERC20', parent: eth),
          },
        ),
      ],
    );
    final open = find.text('Open');
    await pump(
      tester,
      layout,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showSwapAssetPicker(
            context: context,
            side: SwapPickerSide.pay,
            bloc: context.read<UnifiedSwapBloc>(),
            selected: eth,
            other: null,
            services: services(),
            isBlocked: (_) => false,
          ),
          child: const Text('Open'),
        ),
      ),
    );
    tester
        .element(open)
        .read<UnifiedSwapBloc>()
        .emit(UnifiedSwapState(loadingAssets: false, catalog: catalog));
    await tester.tap(open);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'TK');
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    // Even with ETH's row searched out, its identity block ends the list.
    final end = find
        .ancestor(
          of: find.text('Full asset identity'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(
      tester.getRect(end).bottom,
      lessThanOrEqualTo(layout.size.height - keyboard),
    );
    await expectSwapAccessible(tester, largeText: layout.textScale > 1);
  });

  testWidgets('evidence: a copy confirmation on the sheet', (tester) async {
    final platform = tester.binding.defaultBinaryMessenger;
    platform.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    addTearDown(
      () => platform.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pump(
      tester,
      layout,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showSwapEvidenceSheet(
            context,
            snapshot: snapshotOf(approvalTxHashes: const ['0xapprove1']),
            services: services(),
          ),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // The approval's, the last line: the longest label the sheet copies.
    final copy = find.text('Copy').last;
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();

    expect(
      find.text('Approval transactions copied').hitTestable(),
      findsOneWidget,
    );
    await expectSwapAccessible(tester, largeText: layout.textScale > 1);
  });

  testWidgets('slippage: a custom value typed with the keyboard up', (
    tester,
  ) async {
    const keyboard = 336.0;
    await pump(
      tester,
      layout,
      Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showSwapSlippageSheet(context, context.read<UnifiedSwapBloc>()),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField), '3');
    await tester.pumpAndSettle();

    final use = find.ancestor(
      of: find.text('Use 3%'),
      matching: find.byType(TextButton),
    );
    expect(
      tester.getBottomLeft(use).dy,
      lessThanOrEqualTo(layout.size.height - keyboard),
    );
    await expectSwapAccessible(tester, largeText: layout.textScale > 1);
  });
}
