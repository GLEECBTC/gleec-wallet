import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_sheet.dart';

import 'swap_common_ui_fakes.dart';

/// The one sheet every swap picker, option and evidence view opens in.
void main() {
  const dark = SwapPalette.dark;
  const content = Key('sheet-content');
  const phone = Size(390, 844);
  const wide = Size(1024, 768);

  group('swap sheet', () {
    useSwapUi();

    late List<Object?> results;
    setUp(() => results = []);

    Widget opener({WidgetBuilder? builder}) => Builder(
      builder: (context) => TextButton(
        onPressed: () async => results.add(
          await showSwapSheet<String>(
            context: context,
            label: 'Choose asset',
            builder:
                builder ??
                (_) => const SwapSheetScaffold(
                  key: content,
                  title: 'You pay',
                  body: Text('ETH'),
                ),
          ),
        ),
        child: const Text('Open'),
      ),
    );

    Future<void> open(
      WidgetTester tester, {
      Size size = phone,
      SwapMedia media = swapDefaultMedia,
      WidgetBuilder? builder,
    }) async {
      await pumpSwapUi(
        tester,
        opener(builder: builder),
        size: size,
        media: media,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    Material surfaceOf(WidgetTester tester) => tester.widget<Material>(
      find
          .ancestor(of: find.byKey(content), matching: find.byType(Material))
          .first,
    );

    ModalRoute<Object?> routeOf(WidgetTester tester) =>
        ModalRoute.of(tester.element(find.byKey(content)))!;

    group('on a phone', () {
      testWidgets('covers the screen on the canvas colour', (tester) async {
        await open(tester);

        expect(tester.getRect(find.byKey(content)), Offset.zero & phone);
        expect(surfaceOf(tester).color, dark.canvas);
        expect(routeOf(tester).barrierColor, Colors.transparent);
        expect(routeOf(tester).barrierDismissible, isTrue);
        expect(
          routeOf(tester).transitionDuration,
          const Duration(milliseconds: 220),
        );
      });

      testWidgets('the close button dismisses it with nothing chosen', (
        tester,
      ) async {
        await open(tester);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();

        expect(find.byKey(content), findsNothing);
        expect(results, [null]);
      });

      testWidgets('Escape dismisses it with nothing chosen', (tester) async {
        await open(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(find.byKey(content), findsNothing);
        expect(results, [null]);
      });

      testWidgets('returns what the sheet chose', (tester) async {
        await open(
          tester,
          builder: (context) => TextButton(
            key: content,
            onPressed: () => Navigator.of(context).pop('ETH'),
            child: const Text('ETH'),
          ),
        );
        await tester.tap(find.text('ETH'));
        await tester.pumpAndSettle();

        expect(results, ['ETH']);
      });

      testWidgets('rises and fades in over 220 ms', (tester) async {
        await pumpSwapUi(tester, opener(), size: phone);
        await tester.tap(find.text('Open'));
        await tester.pump();

        SlideTransition slide() => tester.widget<SlideTransition>(
          find
              .ancestor(
                of: find.byKey(content),
                matching: find.byType(SlideTransition),
              )
              .first,
        );
        FadeTransition fade() => tester.widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(content),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(slide().position.value, const Offset(0, 0.06));
        expect(fade().opacity.value, 0);
        await tester.pump(const Duration(milliseconds: 110));
        expect(fade().opacity.value, inExclusiveRange(0, 1));
        await tester.pump(const Duration(milliseconds: 110));
        expect(slide().position.value, Offset.zero);
        expect(fade().opacity.value, 1);
      });

      testWidgets('appears at once when less motion is asked for', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          opener(),
          size: phone,
          media: (
            textScale: 1,
            boldText: false,
            reduceMotion: true,
            announces: false,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump();

        final fade = tester.widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(content),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(fade.opacity.value, 1);
        expect(routeOf(tester).transitionDuration, Duration.zero);
      });
    });

    group('on a wide screen', () {
      testWidgets('slides in as a bordered panel on the right', (tester) async {
        await open(tester, size: wide);

        expect(
          tester.getRect(find.byKey(content)),
          const Rect.fromLTWH(504, 0, 520, 768),
        );
        expect(surfaceOf(tester).color, dark.surfaceRaised);
        final panel =
            tester
                    .widget<DecoratedBox>(
                      find
                          .ancestor(
                            of: find.byKey(content),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(panel.border, Border(left: BorderSide(color: dark.border)));
        expect(panel.boxShadow!.single.color, dark.shadow);
        expect(
          routeOf(tester).barrierColor,
          Colors.black.withValues(alpha: 0.45),
        );
        expect(routeOf(tester).barrierLabel, 'Choose asset');
      });

      testWidgets('a tap on the scrim dismisses it with nothing chosen', (
        tester,
      ) async {
        await open(tester, size: wide);
        await tester.tapAt(const Offset(100, 300));
        await tester.pumpAndSettle();

        expect(find.byKey(content), findsNothing);
        expect(results, [null]);
      });

      testWidgets('slides in from the right', (tester) async {
        await pumpSwapUi(tester, opener(), size: wide);
        await tester.tap(find.text('Open'));
        await tester.pump();

        expect(
          tester
              .widget<SlideTransition>(
                find
                    .ancestor(
                      of: find.byKey(content),
                      matching: find.byType(SlideTransition),
                    )
                    .first,
              )
              .position
              .value,
          const Offset(0.12, 0),
        );
        await tester.pumpAndSettle();
      });
    });
  });
}
