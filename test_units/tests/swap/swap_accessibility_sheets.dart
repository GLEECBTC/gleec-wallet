part of 'swap_accessibility_test.dart';

/// Swap sheets opened over a page, as the app opens them.
void _sheetCases(
  _Layout layout, {
  required Future<void> Function(WidgetTester, _Layout, Widget) pump,
  required SwapServices Function() services,
}) {
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
}
