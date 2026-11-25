import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/ui/gradient_border.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';
import 'package:web_dex/shared/ui/ui_tab_bar/ui_tab_bar.dart';
import 'package:web_dex/views/fiat/fiat_action_tab.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';

/// The legacy themes' neutral blacks: canvas, cards, panels and dividers.
const _legacyBlacks = [
  Color(0xFF000000),
  Color(0xFF141414),
  Color(0xFF0A0A0A),
  Color(0xFF1D1D1D),
];

/// The colour [text] is drawn in, after [DefaultTextStyle] is applied.
Color? _drawnColour(WidgetTester tester, String text) => tester
    .widget<RichText>(
      find.descendant(of: find.text(text), matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void _expectReadable(Color? text, Color? background, String what) {
  expect(text, isNotNull, reason: '$what has no colour');
  expect(background, isNotNull, reason: '$what has no background');
  expect(
    _contrast(text!, background!),
    greaterThanOrEqualTo(4.5),
    reason: '$what: $text on $background',
  );
}

void main() {
  group('shared design tokens', () {
    test('the swap names are the shared tokens', () {
      expect(SwapPalette, AppPalette);
      expect(identical(SwapPalette.dark, AppPalette.dark), isTrue);
      expect(identical(SwapPalette.light, AppPalette.light), isTrue);
      expect(SwapTone.success, AppTone.success);
      expect(SwapText, AppText);
      expect(SwapMotion.screen, AppMotion.screen);
      expect(SwapHaptics, AppHaptics);
    });
  });

  for (final (name, base, palette) in [
    ('dark', theme.global.dark, AppPalette.dark),
    ('light', theme.global.light, AppPalette.light),
  ]) {
    group('AppPaletteTheme ($name)', () {
      final mapped = AppPaletteTheme.of(base, palette);
      final surfaces = {
        'canvas': palette.canvas,
        'surface': palette.surface,
        'surfaceRaised': palette.surfaceRaised,
        'surfaceHigh': palette.surfaceHigh,
        'surfaceHighest': palette.surfaceHighest,
      };

      test('draws the legacy surfaces from the palette', () {
        expect(mapped.scaffoldBackgroundColor, palette.canvas);
        expect(mapped.canvasColor, palette.surface);
        expect(mapped.cardColor, palette.surface);
        expect(mapped.cardTheme.color, palette.surface);
        expect(mapped.colorScheme.surface, palette.surface);
        expect(mapped.dialogTheme.backgroundColor, palette.surfaceRaised);
        expect(mapped.bottomSheetTheme.backgroundColor, palette.surfaceRaised);
        expect(mapped.inputDecorationTheme.fillColor, palette.surfaceHigh);
        expect(mapped.dividerColor, palette.border);
        expect(mapped.colorScheme.tertiary, palette.surfaceHigh);
        for (final legacy in _legacyBlacks) {
          expect([
            mapped.scaffoldBackgroundColor,
            mapped.canvasColor,
            mapped.cardColor,
            mapped.colorScheme.surface,
            mapped.colorScheme.tertiary,
            mapped.dialogTheme.backgroundColor,
            mapped.dividerColor,
          ], isNot(contains(legacy)));
        }
      });

      test('keeps the base theme apart from its colours', () {
        expect(mapped.brightness, base.brightness);
        expect(mapped.useMaterial3, base.useMaterial3);
        expect(
          mapped.textTheme.bodyMedium?.fontSize,
          base.textTheme.bodyMedium?.fontSize,
        );
        expect(mapped.extensions, base.extensions);
        expect(identical(AppPaletteTheme.of(base, palette), mapped), isTrue);
      });

      test('every text style reads at 4.5:1 on every surface', () {
        final styles = {
          'displayLarge': mapped.textTheme.displayLarge,
          'headlineMedium': mapped.textTheme.headlineMedium,
          'headlineSmall': mapped.textTheme.headlineSmall,
          'titleLarge': mapped.textTheme.titleLarge,
          'titleMedium': mapped.textTheme.titleMedium,
          'titleSmall': mapped.textTheme.titleSmall,
          'bodyLarge': mapped.textTheme.bodyLarge,
          'bodyMedium': mapped.textTheme.bodyMedium,
          'bodySmall': mapped.textTheme.bodySmall,
          'labelLarge': mapped.textTheme.labelLarge,
          'labelMedium': mapped.textTheme.labelMedium,
          'labelSmall': mapped.textTheme.labelSmall,
        };
        for (final style in styles.entries) {
          for (final surface in surfaces.entries) {
            _expectReadable(
              style.value?.color,
              surface.value,
              '${style.key} on ${surface.key}',
            );
          }
        }
      });

      test('secondary text, hints and errors read on every surface', () {
        final inputs = mapped.inputDecorationTheme;
        final foregrounds = {
          'onSurface': mapped.colorScheme.onSurface,
          'onSurfaceVariant': mapped.colorScheme.onSurfaceVariant,
          'hint': mapped.hintColor,
          'disabled': mapped.disabledColor,
          'error': mapped.colorScheme.error,
          'input hint': inputs.hintStyle?.color,
          'input label': inputs.labelStyle?.color,
          'input error': inputs.errorStyle?.color,
        };
        for (final foreground in foregrounds.entries) {
          for (final surface in surfaces.entries) {
            _expectReadable(
              foreground.value,
              surface.value,
              '${foreground.key} on ${surface.key}',
            );
          }
        }
      });

      test('each on-colour reads on its container', () {
        final scheme = mapped.colorScheme;
        _expectReadable(scheme.onPrimary, scheme.primary, 'onPrimary');
        _expectReadable(scheme.onError, scheme.error, 'onError');
        _expectReadable(
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
          'onPrimaryContainer',
        );
        _expectReadable(
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
          'onSecondaryContainer',
        );
        _expectReadable(scheme.onTertiary, scheme.tertiary, 'onTertiary');
        _expectReadable(
          scheme.onErrorContainer,
          scheme.errorContainer,
          'onErrorContainer',
        );
      });

      test('buttons read in every state', () {
        Color? resolve(WidgetStateProperty<Color?>? p, Set<WidgetState> s) =>
            p?.resolve(s);
        final elevated = mapped.elevatedButtonTheme.style;
        for (final states in [
          <WidgetState>{},
          {WidgetState.disabled},
        ]) {
          _expectReadable(
            resolve(elevated?.foregroundColor, states),
            resolve(elevated?.backgroundColor, states),
            'elevated button $states',
          );
        }
        final link = resolve(mapped.textButtonTheme.style?.foregroundColor, {});
        // A text button sits on a page, a card or a dialog.
        for (final surface in ['canvas', 'surface', 'surfaceRaised']) {
          _expectReadable(link, surfaces[surface], 'text button on $surface');
        }
      });
    });
  }

  group('AppPaletteScope', () {
    Future<ThemeData> pumpScope(WidgetTester tester, ThemeData base) async {
      late ThemeData inside;
      await tester.pumpWidget(
        MaterialApp(
          theme: base,
          home: AppPaletteScope(
            child: Builder(
              builder: (context) {
                inside = Theme.of(context);
                return const Text('plain text');
              },
            ),
          ),
        ),
      );
      return inside;
    }

    testWidgets('paints the canvas and maps the theme below it', (
      tester,
    ) async {
      final inside = await pumpScope(tester, theme.global.dark);
      expect(inside.scaffoldBackgroundColor, AppPalette.dark.canvas);
      expect(inside.cardColor, AppPalette.dark.surface);
      final canvas = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('plain text'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(canvas.color, AppPalette.dark.canvas);
    });

    testWidgets('gives plain text the palette colour in the light theme', (
      tester,
    ) async {
      final inside = await pumpScope(tester, theme.global.light);
      expect(inside.brightness, Brightness.light);
      expect(inside.scaffoldBackgroundColor, AppPalette.light.canvas);
      expect(_drawnColour(tester, 'plain text'), AppPalette.light.text);
    });

    testWidgets('carries the palette into a dialog opened inside it', (
      tester,
    ) async {
      await pumpScope(tester, theme.global.dark);
      Color? dialogCanvas;
      showDialog<void>(
        context: tester.element(find.text('plain text')),
        builder: (context) {
          dialogCanvas = Theme.of(context).dialogTheme.backgroundColor;
          return const Dialog(child: Text('dialog'));
        },
      );
      await tester.pumpAndSettle();
      expect(dialogCanvas, AppPalette.dark.surfaceRaised);
      final dialog = tester.widget<Material>(
        find
            .ancestor(of: find.text('dialog'), matching: find.byType(Material))
            .first,
      );
      expect(dialog.color, AppPalette.dark.surfaceRaised);
    });

    testWidgets('can leave the canvas to the surface it sits on', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.global.dark,
          home: const Material(
            color: Colors.transparent,
            child: AppPaletteScope(paintCanvas: false, child: Text('on card')),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(AppPaletteScope),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
      expect(_drawnColour(tester, 'on card'), AppPalette.dark.text);
    });
  });

  group('shared widgets inside a scope', () {
    Future<void> pump(WidgetTester tester, Widget child, {bool scope = true}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: theme.global.dark,
            home: Scaffold(body: scope ? AppPaletteScope(child: child) : child),
          ),
        );

    testWidgets('read the palette inside a scope and its dialogs only', (
      tester,
    ) async {
      AppPalette? outside;
      AppPalette? inside;
      AppPalette? inDialog;
      await pump(
        tester,
        Builder(
          builder: (context) {
            outside = AppPaletteScope.maybeOf(context);
            return const SizedBox();
          },
        ),
        scope: false,
      );
      await pump(
        tester,
        Builder(
          builder: (context) {
            inside = AppPaletteScope.maybeOf(context);
            return const Text('host');
          },
        ),
      );
      showDialog<void>(
        context: tester.element(find.text('host')),
        builder: (context) {
          inDialog = AppPaletteScope.maybeOf(context);
          return const SizedBox();
        },
      );
      await tester.pumpAndSettle();
      expect(outside, isNull);
      expect(identical(inside, AppPalette.dark), isTrue);
      expect(identical(inDialog, AppPalette.dark), isTrue);
    });

    testWidgets('a ticked checkbox is the brand, not the old blue', (
      tester,
    ) async {
      Color? fill() =>
          (tester.widget<Container>(find.byKey(const Key('box'))).decoration
                  as BoxDecoration?)
              ?.color;
      const box = UiCheckbox(value: true, checkboxKey: Key('box'));
      await pump(tester, box);
      expect(fill(), AppPalette.dark.brand);
      await pump(tester, box, scope: false);
      expect(fill(), isNot(AppPalette.dark.brand));
    });

    testWidgets('a secondary button labels itself in brandHover', (
      tester,
    ) async {
      await pump(
        tester,
        UiSecondaryButton(text: 'Download', onPressed: () {}, width: 200),
      );
      final label = tester.widget<Text>(find.text('Download'));
      expect(label.style?.color, AppPalette.dark.brandHover);
      _expectReadable(
        label.style?.color,
        AppPalette.dark.surface,
        'secondary button label',
      );
    });

    testWidgets('notices draw in the palette tones, readable on their tint', (
      tester,
    ) async {
      final styles = <NoticeBannerVariant, NoticeBannerStyle>{};
      await pump(
        tester,
        Builder(
          builder: (context) {
            for (final variant in NoticeBannerVariant.values) {
              styles[variant] = NoticeBanner.styleOf(context, variant);
            }
            return const SizedBox();
          },
        ),
      );
      expect(
        styles[NoticeBannerVariant.warning]?.background,
        AppPalette.dark.warningBg,
      );
      expect(
        styles[NoticeBannerVariant.critical]?.foreground,
        AppPalette.dark.danger,
      );
      for (final entry in styles.entries) {
        _expectReadable(
          entry.value.foreground,
          entry.value.background,
          '${entry.key} notice',
        );
      }
    });
  });

  group('screens on the palette', () {
    testWidgets('Buy and Sell tabs sit in a palette frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.global.dark,
          home: AppPaletteScope(
            child: FiatActionTabBar(currentTabIndex: 0, onTabClick: (_) {}),
          ),
        ),
      );

      expect(find.byKey(const Key('fiat-buy-tab')), findsOneWidget);
      expect(find.byKey(const Key('fiat-sell-tab')), findsOneWidget);
      expect(find.byType(GradientBorder), findsNothing);
      final frame = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(UiTabBar),
              matching: find.byType(Container),
            ),
          )
          .map((container) => container.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(frame.color, AppPalette.dark.surface);
      expect(frame.border, Border.all(color: AppPalette.dark.border));
    });
  });
}
