import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';

import 'swap_common_ui_fakes.dart';

/// The inside of a swap sheet: a heading with a close action, a body and a
/// pinned footer.
void main() {
  const dark = SwapPalette.dark;
  const body = Text('Body');

  Finder inScroll(Finder finder) =>
      find.descendant(of: find.byType(SingleChildScrollView), matching: finder);

  group('swap sheet scaffold', () {
    useSwapUi();

    testWidgets('heads with its title and a labelled close action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpSwapUi(
        tester,
        SwapSheetScaffold(title: 'You pay', body: body, onClose: () {}),
      );

      final title = tester
          .getSemantics(find.text('You pay'))
          .getSemanticsData();
      expect(title.flagsCollection.isHeader, isTrue);
      expect(tester.widget<Text>(find.text('You pay')).style!.fontSize, 20);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a scrolling body carries the subtitle above it', (
      tester,
    ) async {
      await pumpSwapUi(
        tester,
        SwapSheetScaffold(
          title: 'You pay',
          subtitle: 'Assets you can swap',
          body: body,
          onClose: () {},
        ),
      );

      expect(inScroll(find.text('Assets you can swap')), findsOneWidget);
      expect(inScroll(find.text('Body')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Body')).dy,
        tester.getBottomLeft(find.text('Assets you can swap')).dy + 12,
      );
      expect(tester.getTopLeft(find.text('Body')).dx, 18);
    });

    testWidgets('a scrolling body without a subtitle starts at the top', (
      tester,
    ) async {
      await pumpSwapUi(
        tester,
        SwapSheetScaffold(title: 'You pay', body: body, onClose: () {}),
      );

      expect(inScroll(find.text('Body')), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Body')).dy,
        tester.getTopLeft(find.byType(SingleChildScrollView)).dy,
      );
    });

    testWidgets('a body that scrolls itself keeps the subtitle pinned', (
      tester,
    ) async {
      await pumpSwapUi(
        tester,
        SwapSheetScaffold(
          title: 'You pay',
          subtitle: 'Assets you can swap',
          scrollable: false,
          body: body,
          onClose: () {},
        ),
      );

      expect(find.byType(SingleChildScrollView), findsNothing);
      final title = tester.getRect(find.text('You pay'));
      final subtitle = tester.getRect(find.text('Assets you can swap'));
      expect(subtitle.top, title.bottom + 4);
      expect(tester.getTopLeft(find.text('Body')).dx, 18);
    });

    testWidgets('pins a footer under a hairline', (tester) async {
      await pumpSwapUi(
        tester,
        SwapSheetScaffold(
          title: 'Evidence',
          body: body,
          footer: const Text('Copy details'),
          onClose: () {},
        ),
      );

      expect(inScroll(find.text('Copy details')), findsNothing);
      final footer = tester.getRect(find.text('Copy details'));
      expect(footer.bottom, 900 - 16);
      expect(footer.left, 18);
      final hairline = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('Copy details'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (hairline.decoration as BoxDecoration).border,
        Border(top: BorderSide(color: dark.border)),
      );
    });

    testWidgets('without a footer, nothing is pinned below the body', (
      tester,
    ) async {
      await pumpSwapUi(
        tester,
        SwapSheetScaffold(title: 'Evidence', body: body, onClose: () {}),
      );

      expect(tester.getBottomLeft(find.byType(SingleChildScrollView)).dy, 900);
    });

    testWidgets('closing calls its own handler when given one', (tester) async {
      var closes = 0;
      await pumpSwapUi(
        tester,
        SwapSheetScaffold(
          title: 'You pay',
          body: body,
          onClose: () => closes++,
        ),
      );

      await tester.tap(find.byTooltip('Close'));
      expect(closes, 1);
    });

    testWidgets('closing pops the route otherwise', (tester) async {
      await pumpSwapUi(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Material(
                  child: SwapSheetScaffold(title: 'You pay', body: body),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('You pay'), findsOneWidget);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('You pay'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });
  });
}
