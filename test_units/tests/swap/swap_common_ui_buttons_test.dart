import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';

import 'swap_common_ui_fakes.dart';

/// The swap surface's buttons: what each variant looks like, when it can be
/// pressed, and how a screen reader presses it.
void main() {
  const dark = SwapPalette.dark;

  group('swap buttons', () {
    useSwapUi();

    Material materialOf(WidgetTester tester, Type button) =>
        tester.widget<Material>(
          find
              .descendant(
                of: find.byType(button),
                matching: find.byType(Material),
              )
              .first,
        );

    Color borderOf(Material material) =>
        (material.shape! as RoundedRectangleBorder).side.color;

    group('full-width button', () {
      testWidgets('each variant has its colours', (tester) async {
        for (final (variant, background, foreground, border) in [
          (SwapButtonVariant.primary, dark.brand, dark.onBrand, dark.brand),
          (
            SwapButtonVariant.secondary,
            dark.surfaceHigh,
            dark.text,
            dark.controlBorder,
          ),
          (SwapButtonVariant.danger, dark.dangerBg, dark.danger, dark.danger),
        ]) {
          await pumpSwapUi(
            tester,
            SwapButton(label: 'Go', variant: variant, onPressed: () {}),
          );
          final material = materialOf(tester, SwapButton);
          expect(material.color, background, reason: variant.name);
          expect(material.textStyle!.color, foreground, reason: variant.name);
          expect(borderOf(material), border, reason: variant.name);
        }
      });

      testWidgets('is at least 52 tall and presses once per tap', (
        tester,
      ) async {
        var presses = 0;
        await pumpSwapUi(
          tester,
          SwapButton(label: 'Review swap', onPressed: () => presses++),
        );

        expect(tester.getSize(find.byType(SwapButton)).height, 52);
        await tester.tap(find.text('Review swap'));
        expect(presses, 1);
      });

      testWidgets('the primary button darkens while pressed', (tester) async {
        await pumpSwapUi(tester, SwapButton(label: 'Go', onPressed: () {}));

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(SwapButton)),
        );
        await tester.pump();
        expect(materialOf(tester, SwapButton).color, dark.brandPressed);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(materialOf(tester, SwapButton).color, dark.brand);
      });

      testWidgets('other variants keep their colour while pressed', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          SwapButton(
            label: 'Go',
            variant: SwapButtonVariant.secondary,
            onPressed: () {},
          ),
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(SwapButton)),
        );
        await tester.pump();
        expect(materialOf(tester, SwapButton).color, dark.surfaceHigh);
        await gesture.up();
      });

      testWidgets('without an action it is neutral, readable and inert', (
        tester,
      ) async {
        var presses = 0;
        await pumpSwapUi(
          tester,
          const SwapButton(label: 'Enter amount', onPressed: null),
        );

        final material = materialOf(tester, SwapButton);
        expect(material.color, dark.disabled);
        expect(material.textStyle!.color, dark.onDisabled);
        expect(borderOf(material), dark.borderStrong);
        await tester.tap(find.text('Enter amount'), warnIfMissed: false);
        expect(presses, 0);
      });

      // The label of a disabled or busy button is the form's status.
      test('its label keeps text contrast when it cannot be pressed', () {
        double contrast(Color a, Color b) {
          final (la, lb) = (a.computeLuminance(), b.computeLuminance());
          return (la > lb ? la + 0.05 : lb + 0.05) /
              (la > lb ? lb + 0.05 : la + 0.05);
        }

        for (final palette in [SwapPalette.light, SwapPalette.dark]) {
          expect(
            contrast(palette.onDisabled, palette.disabled),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(palette.onBrand, palette.brand),
            greaterThanOrEqualTo(4.5),
          );
        }
      });

      testWidgets('busy, it spins in its own colours and ignores presses', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        var presses = 0;
        await pumpSwapUi(
          tester,
          SwapButton(
            label: 'Starting',
            icon: Icons.bolt,
            busy: true,
            onPressed: () => presses++,
          ),
          settle: false,
        );

        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(spinner.color, dark.onBrand);
        expect(
          tester.getSize(find.byType(CircularProgressIndicator)),
          const Size.square(16),
        );
        expect(find.byIcon(Icons.bolt), findsNothing);
        final material = materialOf(tester, SwapButton);
        expect(material.color, dark.brand);
        expect(material.textStyle!.color, dark.onBrand);
        await tester.tap(find.text('Starting'), warnIfMissed: false);
        expect(presses, 0);
        final data = tester
            .getSemantics(find.byType(SwapButton))
            .getSemanticsData();
        expect(data.label, 'Starting');
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        semantics.dispose();
      });

      testWidgets('keeps keyboard focus as it turns busy and back', (
        tester,
      ) async {
        Widget button({required bool busy}) =>
            SwapButton(label: 'Confirm swap', busy: busy, onPressed: () {});
        await pumpSwapUi(tester, button(busy: false));
        Focus.of(tester.element(find.text('Confirm swap'))).requestFocus();
        await tester.pump();
        bool focused() =>
            Focus.of(tester.element(find.text('Confirm swap'))).hasFocus;
        expect(focused(), isTrue);

        await pumpSwapUi(tester, button(busy: true), settle: false);
        expect(focused(), isTrue);
        await pumpSwapUi(tester, button(busy: false), settle: false);
        expect(focused(), isTrue);
      });

      testWidgets('an icon leads the label', (tester) async {
        await pumpSwapUi(
          tester,
          Center(
            child: SwapButton(
              label: 'Copy',
              icon: Icons.content_copy_rounded,
              onPressed: () {},
            ),
          ),
        );

        final icon = find.byIcon(Icons.content_copy_rounded);
        expect(tester.getSize(icon), const Size.square(18));
        expect(
          tester.getTopLeft(find.text('Copy')).dx,
          tester.getTopRight(icon).dx + 8,
        );
      });

      testWidgets('follows the light theme', (tester) async {
        await pumpSwapUi(
          tester,
          SwapButton(
            label: 'Go',
            variant: SwapButtonVariant.secondary,
            onPressed: () {},
          ),
          dark: false,
        );

        expect(
          materialOf(tester, SwapButton).textStyle!.color,
          SwapPalette.light.text,
        );
      });
    });

    group('link button', () {
      testWidgets('is a 48 dp target in the brand colour, icon first', (
        tester,
      ) async {
        var presses = 0;
        await pumpSwapUi(
          tester,
          Center(
            child: SwapLinkButton(
              label: 'Details',
              icon: Icons.info_outline,
              onPressed: () => presses++,
            ),
          ),
        );

        final size = tester.getSize(find.byType(SwapLinkButton));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(
          materialOf(tester, SwapLinkButton).textStyle!.color,
          dark.brandHover,
        );
        expect(
          tester.getSize(find.byIcon(Icons.info_outline)),
          const Size.square(16),
        );
        await tester.tap(find.text('Details'));
        expect(presses, 1);
      });

      testWidgets('without an action it cannot be pressed', (tester) async {
        await pumpSwapUi(
          tester,
          const SwapLinkButton(label: 'Details', onPressed: null),
        );

        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          isNull,
        );
        expect(find.byType(Icon), findsNothing);
      });

      testWidgets('busy without an action still cannot be pressed', (
        tester,
      ) async {
        await pumpSwapUi(
          tester,
          const SwapLinkButton(label: 'Details', onPressed: null, busy: true),
          settle: false,
        );

        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          isNull,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
    });

    group('icon button', () {
      testWidgets('is one labelled, pressable 48 dp button', (tester) async {
        final semantics = tester.ensureSemantics();
        var presses = 0;
        await pumpSwapUi(
          tester,
          Center(
            child: SwapIconButton(
              icon: Icons.close_rounded,
              label: 'Close',
              onPressed: () => presses++,
            ),
          ),
        );

        expect(
          tester.getSize(find.byType(SwapIconButton)),
          const Size.square(48),
        );
        expect(find.byTooltip('Close'), findsOneWidget);
        final node = tester.getSemantics(find.byType(SwapIconButton));
        final data = node.getSemanticsData();
        expect(data.label, 'Close');
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        tester.semantics.tap(find.semantics.byLabel('Close'));
        expect(presses, 1);
        await tester.tap(find.byType(SwapIconButton));
        expect(presses, 2);
        semantics.dispose();
      });

      testWidgets('without an action it reads as disabled', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpSwapUi(
          tester,
          const Center(
            child: SwapIconButton(
              icon: Icons.close_rounded,
              label: 'Close',
              onPressed: null,
            ),
          ),
        );

        final data = tester
            .getSemantics(find.byType(SwapIconButton))
            .getSemanticsData();
        expect(data.flagsCollection.isEnabled, Tristate.isFalse);
        expect(data.hasAction(SemanticsAction.tap), isFalse);
        semantics.dispose();
      });
    });
  });
}
