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
  const GleecDexLogo({super.key, this.height = 32, this.forceThemeMode});

  /// The height of the logo. Width scales proportionally.
  final double height;

  /// If set, forces the logo to display in the specified theme mode
  /// regardless of the current app theme. Useful for theme previews.
  final ThemeMode? forceThemeMode;

  @override
  Widget build(BuildContext context) {
    // Calculate proportional sizes based on height
    // Icon and text should be the same visual height (matching GLEEC BTC style)
    final double textHeight = height * 0.6;
    final double iconSize = height;
    final double spacing = height * 0.3;

    // Determine if we should use dark theme styling
    final bool isDarkTheme = forceThemeMode != null
        ? forceThemeMode == ThemeMode.dark
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
          SizedBox(width: spacing),
          // GLEEC wordmark (theme-aware)
          SvgPicture.asset(
            '$assetsPath/logo/logo$themePostfix.svg',
            height: textHeight,
          ),
          SizedBox(width: spacing * 0.75),
          Transform.translate(
            offset: Offset(0, textHeight * 0.25),
            child: Text(
              'DEX',
              strutStyle: const StrutStyle(height: 1.0, forceStrutHeight: true),
              style: TextStyle(
                fontFamily: 'Rubik',
                fontSize: textHeight * 1.32,
                fontVariations: const [
                  FontVariation('wght', 600),
                ], // Use this for variable fonts
                letterSpacing: textHeight * 0.09,
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
