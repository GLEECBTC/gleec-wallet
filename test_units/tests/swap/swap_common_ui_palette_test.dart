import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

import 'swap_accessibility_checks.dart';
import 'swap_common_ui_fakes.dart';

/// The swap surface's colours, type scale and text measurement.
void main() {
  const label = 'Best net return';
  const bold = (
    textScale: 1.0,
    boldText: true,
    reduceMotion: false,
    announces: false,
  );

  group('swap palette', () {
    useSwapUi();

    testWidgets('follows the theme brightness', (tester) async {
      late SwapPalette palette;
      Widget probe() => Builder(
        builder: (context) {
          palette = SwapPalette.of(context);
          return const SizedBox();
        },
      );

      await pumpSwapUi(tester, probe());
      expect(palette, same(SwapPalette.dark));
      await pumpSwapUi(tester, probe(), dark: false);
      expect(palette, same(SwapPalette.light));
    });

    test('each tone maps to its foreground, background and border', () {
      for (final palette in [SwapPalette.dark, SwapPalette.light]) {
        Map<SwapTone, List<Color>> tones() => {
          for (final tone in SwapTone.values)
            tone: [
              palette.toneColor(tone),
              palette.toneBackground(tone),
              palette.toneBorder(tone),
            ],
        };
        expect(tones(), {
          SwapTone.neutral: [
            palette.textSecondary,
            palette.surfaceHigh,
            palette.border,
          ],
          SwapTone.brand: [palette.text, palette.selected, palette.brand],
          SwapTone.success: [
            palette.success,
            palette.successBg,
            palette.success,
          ],
          SwapTone.warning: [
            palette.warning,
            palette.warningBg,
            palette.warning,
          ],
          SwapTone.pending: [
            palette.pending,
            palette.pendingBg,
            palette.pending,
          ],
          SwapTone.danger: [palette.danger, palette.dangerBg, palette.danger],
          SwapTone.info: [palette.info, palette.infoBg, palette.info],
        });
      }
    });

    test('the two palettes share the brand but not the surfaces', () {
      expect(SwapPalette.light.brand, SwapPalette.dark.brand);
      expect(SwapPalette.dark.canvas, const Color(0xFF0A0C15));
      expect(SwapPalette.light.canvas, const Color(0xFFFAFAFD));
      expect(SwapPalette.light.text, SwapPalette.dark.canvas);
    });

    test('shared geometry', () {
      expect(SwapGeometry.contentWidth, 576);
      expect(SwapGeometry.panelWidth, 520);
      expect(SwapGeometry.sidePanelBreakpoint, 960);
      expect(SwapGeometry.touchTarget, 48);
    });
  });

  group('swap type scale', () {
    useSwapUi();

    testWidgets('builds on the theme font, in the palette colours', (
      tester,
    ) async {
      late Map<String, TextStyle> built;
      await pumpSwapUi(
        tester,
        Builder(
          builder: (context) {
            built = {
              'title': SwapText.title(context),
              'heading': SwapText.heading(context),
              'amount': SwapText.amount(context),
              'body': SwapText.body(context),
              'strong': SwapText.strong(context),
              'small': SwapText.small(context),
              'eyebrow': SwapText.eyebrow(context),
              'code': SwapText.code(context),
            };
            return const SizedBox();
          },
        ),
        dark: false,
      );
      const light = SwapPalette.light;

      final expected = <String, (double, FontWeight?, double?, Color)>{
        'title': (28, FontWeight.w800, -0.4, light.text),
        'heading': (20, FontWeight.w800, null, light.text),
        'amount': (32, FontWeight.w800, -1.1, light.text),
        'body': (15, null, null, light.textSecondary),
        'strong': (15, FontWeight.w700, null, light.text),
        'small': (13, null, null, light.textTertiary),
        'eyebrow': (11, FontWeight.w800, 0.8, light.textTertiary),
      };
      for (final MapEntry(key: name, value: (size, weight, spacing, color))
          in expected.entries) {
        final style = built[name]!;
        expect(style.fontSize, size, reason: name);
        expect(style.color, color, reason: name);
        expect(style.fontFamily, swapFont, reason: name);
        expect(style.inherit, isFalse, reason: name);
        if (weight != null) expect(style.fontWeight, weight, reason: name);
        if (spacing != null) expect(style.letterSpacing, spacing, reason: name);
      }

      final code = built['code']!;
      expect(code.fontFamily, 'monospace');
      expect(code.fontFamilyFallback, ['Courier New', 'Courier']);
      expect(code.fontSize, 13);
      expect(code.color, light.text);
    });
  });

  group('swap text width', () {
    useSwapUi();

    Future<double> measure(
      WidgetTester tester,
      TextStyle Function(BuildContext context) styleOf, {
      String text = label,
      SwapMedia media = swapDefaultMedia,
      bool longestWord = false,
      Widget Function(Widget child)? wrap,
    }) async {
      late double measured;
      final probe = Builder(
        builder: (context) {
          final style = styleOf(context);
          measured = SwapText.widthOf(
            context,
            text,
            style,
            longestWord: longestWord,
          );
          return Align(
            alignment: Alignment.topLeft,
            child: Text(text, style: style),
          );
        },
      );
      await pumpSwapUi(tester, wrap?.call(probe) ?? probe, media: media);
      return measured;
    }

    double rendered(WidgetTester tester, [String text = label]) =>
        tester.getSize(find.text(text)).width;

    testWidgets('matches a rendered Text on one line', (tester) async {
      final measured = await measure(tester, SwapText.body);

      expect(measured, closeTo(rendered(tester), 0.01));
    });

    testWidgets('matches with bold text on, which widens it', (tester) async {
      final plain = await measure(tester, SwapText.body);
      final boldWidth = await measure(tester, SwapText.body, media: bold);

      expect(boldWidth, closeTo(rendered(tester), 0.01));
      expect(boldWidth, greaterThan(plain + 1));
    });

    testWidgets('matches at 200% text', (tester) async {
      final measured = await measure(
        tester,
        SwapText.small,
        media: (
          textScale: 2,
          boldText: false,
          reduceMotion: false,
          announces: false,
        ),
      );

      expect(measured, closeTo(rendered(tester), 0.01));
    });

    testWidgets('merges an inheriting style with the ambient default', (
      tester,
    ) async {
      final measured = await measure(
        tester,
        (_) => const TextStyle(fontWeight: FontWeight.w700),
        wrap: (child) => DefaultTextStyle(
          style: const TextStyle(
            fontFamily: swapFont,
            fontSize: 22,
            letterSpacing: 1.5,
          ),
          child: child,
        ),
      );

      final bare = TextPainter(
        text: const TextSpan(
          text: label,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(measured, closeTo(rendered(tester), 0.01));
      expect(measured, isNot(closeTo(bare.maxIntrinsicWidth, 1)));
      bare.dispose();
    });

    testWidgets('matches the platform letter and word spacing overrides', (
      tester,
    ) async {
      final plain = await measure(tester, SwapText.body);
      final spaced = await measure(
        tester,
        SwapText.body,
        wrap: (child) => Builder(
          builder: (context) => MediaQuery(
            data: const MediaQueryData(
              letterSpacingOverride: 2,
              wordSpacingOverride: 6,
            ),
            child: child,
          ),
        ),
      );

      expect(spaced, closeTo(rendered(tester), 0.01));
      expect(spaced, greaterThan(plain + 2 * label.length));
    });

    testWidgets('finds the longest unbreakable run', (tester) async {
      final longest = await measure(tester, SwapText.body, longestWord: true);

      final paragraph = tester.renderObject<RenderBox>(
        find.descendant(of: find.text(label), matching: find.byType(RichText)),
      );
      expect(
        longest,
        closeTo(paragraph.getMinIntrinsicWidth(double.infinity), 0.01),
      );
      final word = await measure(tester, SwapText.body, text: 'return');
      expect(longest, closeTo(word, 0.01));
      expect(word, closeTo(rendered(tester, 'return'), 0.01));
    });
  });
}
