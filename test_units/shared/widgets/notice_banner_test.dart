import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';

import '../../support/contrast.dart';

void main() => testNoticeBanner();

/// `NoticeBanner` is the app's shared callout, and its whole purpose is to be
/// readable. It had no tests; these pin the one property that matters - every
/// variant stays legible on its own tinted background, in both live themes and
/// in the bare-MaterialApp case where the theme extension is absent.
void testNoticeBanner() {
  group('NoticeBanner:', () {
    final themes = <String, ThemeData?>{
      'global light': theme.global.light,
      'global dark': theme.global.dark,
      'new light': newThemeLight,
      'new dark': newThemeDark,
      // The fallback path: no ColorSchemeExtension registered, which is what
      // most widget tests in this suite pump.
      'bare MaterialApp': null,
    };

    themes.forEach((themeName, themeData) {
      for (final variant in NoticeBannerVariant.values) {
        testWidgets('$themeName ${variant.name} text is legible', (
          tester,
        ) async {
          late NoticeBannerStyle style;
          await tester.pumpWidget(
            MaterialApp(
              theme: themeData,
              darkTheme: themeData,
              themeAnimationDuration: Duration.zero,
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    style = NoticeBanner.styleOf(context, variant);
                    return NoticeBanner(
                      variant: variant,
                      icon: Icons.info_outline,
                      title: 'Headline',
                      child: const Text('Body copy'),
                    );
                  },
                ),
              ),
            ),
          );

          final canvas = Theme.of(
            tester.element(find.byType(NoticeBanner)),
          ).scaffoldBackgroundColor;
          final painted = compositeOver(style.background, canvas);

          expectContrast(
            style.foreground,
            painted,
            because: '$themeName ${variant.name}: body on the banner tint',
          );
          expectContrast(
            style.accent,
            painted,
            atLeast: wcagAaNonText,
            because: '$themeName ${variant.name}: icon on the banner tint',
          );
        });
      }
    });

    testWidgets('critical carries a border so severity is not hue alone', (
      tester,
    ) async {
      final borders = <NoticeBannerVariant, BoxBorder?>{};
      for (final variant in NoticeBannerVariant.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.global.dark,
            home: Scaffold(
              body: NoticeBanner(variant: variant, child: const Text('x')),
            ),
          ),
        );
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(NoticeBanner),
                matching: find.byType(Container),
              )
              .first,
        );
        borders[variant] = (container.decoration! as BoxDecoration).border;
      }
      expect(borders[NoticeBannerVariant.critical], isNotNull);
      expect(borders[NoticeBannerVariant.warning], isNull);
      expect(borders[NoticeBannerVariant.success], isNull);
    });

    testWidgets('title is optional and renders above the body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.global.dark,
          home: const Scaffold(
            body: NoticeBanner(
              variant: NoticeBannerVariant.critical,
              child: Text('Body copy'),
            ),
          ),
        ),
      );
      expect(find.text('Body copy'), findsOneWidget);
      expect(find.text('Headline'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme.global.dark,
          home: const Scaffold(
            body: NoticeBanner(
              variant: NoticeBannerVariant.critical,
              title: 'Headline',
              child: Text('Body copy'),
            ),
          ),
        ),
      );
      expect(find.text('Headline'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Headline')).dy,
        lessThan(tester.getTopLeft(find.text('Body copy')).dy),
      );
    });
  });
}
