import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Semantic tone of a [NoticeBanner].
enum NoticeBannerVariant { info, warning, success }

/// Resolved banner palette: a tinted background plus a foreground that is
/// legible on it in the active theme.
class NoticeBannerStyle {
  const NoticeBannerStyle({
    required this.background,
    required this.foreground,
    required this.accent,
  });

  final Color background;
  final Color foreground;

  /// Brand accent for icons/highlights; may be lower-contrast than
  /// [foreground] (never use it for body text).
  final Color accent;
}

/// Rounded inline notice used across the wallet for warnings, success states
/// and informational callouts.
///
/// Centralizes the tinted-container pattern that was previously copy-pasted
/// (hardcoded `Colors.amber`/`Colors.green` with per-site brightness checks)
/// so every notice draws from the theme's [ColorSchemeExtension] tokens and
/// stays consistent in both brightness modes.
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.child,
    this.variant = NoticeBannerVariant.warning,
    this.icon,
    this.footer,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    super.key,
  });

  /// Main content, laid out to the right of [icon]. The child owns its text
  /// styles; use [styleOf] to color text with the variant foreground.
  final Widget child;

  final NoticeBannerVariant variant;

  /// Optional leading icon, tinted with the variant accent.
  final IconData? icon;

  /// Optional full-width row below the content (e.g. a retry button).
  final Widget? footer;

  final EdgeInsetsGeometry padding;

  /// Palette for [variant] in the current theme. Exposed so banner contents
  /// (and sibling affordances like chips) can match without re-deriving
  /// colors locally.
  static NoticeBannerStyle styleOf(
    BuildContext context,
    NoticeBannerVariant variant,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.extension<ColorSchemeExtension>();

    switch (variant) {
      case NoticeBannerVariant.info:
        return NoticeBannerStyle(
          background: theme.colorScheme.secondaryContainer.withValues(
            alpha: 0.35,
          ),
          foreground: theme.colorScheme.onSecondaryContainer,
          accent: theme.colorScheme.onSecondaryContainer,
        );
      case NoticeBannerVariant.warning:
        // Brand warning hue with a legible shade per brightness; falls back
        // to the Material amber pairing when the theme extension is absent
        // (e.g. bare-MaterialApp widget tests).
        final orange = scheme?.orange;
        return NoticeBannerStyle(
          background: (orange ?? Colors.amber).withValues(
            alpha: isDark ? 0.22 : 0.16,
          ),
          foreground: orange != null
              ? _legibleShade(orange, isDark: isDark)
              : (isDark ? Colors.amber.shade200 : Colors.amber.shade900),
          accent: orange ?? (isDark ? Colors.amber.shade200 : Colors.amber),
        );
      case NoticeBannerVariant.success:
        final green = scheme?.green;
        return NoticeBannerStyle(
          background:
              scheme?.g20 ??
              (isDark
                  ? Colors.green.withValues(alpha: 0.22)
                  : Colors.green.withValues(alpha: 0.16)),
          foreground: green != null
              ? _legibleShade(green, isDark: isDark)
              : (isDark ? Colors.green.shade200 : Colors.green.shade900),
          accent: green ?? theme.colorScheme.primary,
        );
    }
  }

  /// Shifts a brand hue to a lightness that clears WCAG contrast on the
  /// banner's tinted background: lighter on dark surfaces, darker on light
  /// ones. Keeps the token as the single source of hue.
  static Color _legibleShade(Color color, {required bool isDark}) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(isDark ? 0.75 : 0.28).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final style = styleOf(context, variant);

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(12),
        border: variant == NoticeBannerVariant.info
            ? Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: style.accent),
                const SizedBox(width: 12),
              ],
              Expanded(child: child),
            ],
          ),
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
