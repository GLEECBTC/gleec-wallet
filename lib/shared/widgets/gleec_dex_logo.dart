import 'dart:ui' show FontVariation;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/app_config/app_config.dart';

/// The brand purple color used for the icon and "DEX" text.
const Color gleecPurple = Color(0xFF8C41FF);

/// A widget that displays the GLEEC DEX logo consisting of:
/// - Purple G icon on the left
/// - "GLEEC" wordmark (theme-aware color)
/// - "DEX" text in purple
class GleecDexLogo extends StatelessWidget {
  const GleecDexLogo({
    super.key,
    this.height = 32,
    this.themeMode,
    this.isDense = false,
  });

  /// The height of the logo. Width scales proportionally.
  final double height;

  /// If set, forces the logo to display in the specified theme mode
  /// regardless of the current app theme. Useful for theme previews.
  final ThemeMode? themeMode;

  /// If true, uses tighter spacing between elements.
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    // Calculate proportional sizes based on height
    final double textHeight = height * 0.55;
    final double iconSize = height;

    // Spacing tweaks (based on current-state comparison to BTC reference):
    // - icon → GLEEC gap: +~12%
    // - GLEEC → DEX gap: keep as-is
    final double iconTextSpacingBase = isDense ? 13.0 : 17.4;
    final double iconTextSpacing = iconTextSpacingBase * 1.12;

    final double wordmarkDexSpacing = isDense ? 5.0 : 7.4;
    final double letterSpacing = textHeight * (isDense ? 0.058 : 0.060);
    // Determine if we should use dark theme styling
    final bool isDarkTheme = themeMode != null
        ? themeMode == ThemeMode.dark
        : Theme.of(context).brightness == Brightness.dark;

    final String themePostfix = isDarkTheme ? '_dark' : '';

    // Use FittedBox to scale the entire logo to fit within available width
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Purple G Icon
          Image.asset(
            '$assetsPath/logo/icon.png',
            width: iconSize,
            height: iconSize,
          ),
          SizedBox(width: iconTextSpacing),

          // GLEEC wordmark (theme-aware)
          SvgPicture.asset(
            '$assetsPath/logo/logo$themePostfix.svg',
            height: textHeight,
          ),
          SizedBox(width: wordmarkDexSpacing),

          // Small offset to align DEX baseline with GLEEC wordmark
          Transform.translate(
            offset: Offset(0, textHeight * 0.08),
            child: Text(
              'DEX',
              style: TextStyle(
                fontFamily: 'Rubik',
                fontSize: textHeight * 1.43,

                // Reduce perceived weight (DEX was reading heavier than BTC suffix)
                fontVariations: const [FontVariation('wght', 450)],

                // Slight tracking bump helps soften perceived heaviness (esp. in purple)
                letterSpacing: letterSpacing,

                color: gleecPurple,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
