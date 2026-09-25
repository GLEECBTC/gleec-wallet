import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Semantic tone of a [NoticeBanner].
enum NoticeBannerVariant { info, warning, success, critical }

/// GLEEC brand red, mirroring [ColorSchemeExtension.error] and
/// `theme.custom.warningColor`.
///
/// Held locally rather than read from the theme singleton so [NoticeBanner]
/// keeps working under nested `Theme` scopes and in bare-`MaterialApp` widget
/// tests, matching how the other variants fall back. Deliberately *not*
/// `colorScheme.errorContainer`, which the light scheme still carries as the
/// Material 2 `#B00020` block.
const Color _brandCritical = Color(0xFFE52167);

/// Resolved palette: a tinted background plus a foreground that is legible on
/// it in the active theme.
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
    this.title,
    this.footer,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    super.key,
  });

  /// Main content, laid out to the right of [icon].
  ///
  /// Text inside inherits the variant foreground through a merged
  /// [DefaultTextStyle], so a plain [Text] is legible on the banner tint
  /// without the caller re-deriving the palette. Children that set their own
  /// colour still win.
  final Widget child;

  final NoticeBannerVariant variant;

  /// Optional bold headline above [child], coloured with the variant
  /// foreground. Use it when the banner needs to state its point before the
  /// reader commits to the paragraph.
  final String? title;

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
        // `secondaryContainer` is Material 2's teal in the light scheme - an
        // accident of `ColorScheme.copyWith`, not a brand colour - so this
        // draws on the neutral surface tokens instead. `bodyMedium` is the
        // foreground both global themes already use for body copy.
        final neutral = theme.textTheme.bodyMedium?.color ?? theme.hintColor;
        return NoticeBannerStyle(
          background: scheme?.s10 ?? theme.colorScheme.surfaceContainerHigh,
          foreground: neutral,
          accent: scheme?.secondary ?? neutral,
        );
      case NoticeBannerVariant.warning:
        // Brand warning hue, falling back to Material amber when the theme
        // extension is absent (bare-MaterialApp widget tests, and the global
        // themes, which do not register it). Both paths go through
        // [_legibleShade]: the fallback previously used `amber.shade900`
        // directly, which is only 2.49:1 on its own tint in light mode.
        final orange = scheme?.orange ?? Colors.amber;
        return NoticeBannerStyle(
          background: orange.withValues(alpha: isDark ? 0.22 : 0.16),
          foreground: _legibleShade(orange, isDark: isDark),
          accent: _legibleShade(orange, isDark: isDark),
        );
      case NoticeBannerVariant.critical:
        // Highest severity. Severity must not rest on hue alone - `build`
        // gives this variant a border so it still outranks `warning` for
        // anyone who cannot separate red from amber.
        return NoticeBannerStyle(
          background: (scheme?.error ?? _brandCritical).withValues(
            alpha: isDark ? 0.22 : 0.12,
          ),
          foreground: _legibleShade(
            scheme?.error ?? _brandCritical,
            isDark: isDark,
          ),
          accent: _legibleShade(
            scheme?.error ?? _brandCritical,
            isDark: isDark,
          ),
        );
      case NoticeBannerVariant.success:
        final green = scheme?.green ?? Colors.green;
        return NoticeBannerStyle(
          background:
              scheme?.g20 ?? green.withValues(alpha: isDark ? 0.22 : 0.16),
          foreground: _legibleShade(green, isDark: isDark),
          accent: _legibleShade(green, isDark: isDark),
        );
    }
  }

  /// Shifts a brand hue to a lightness that clears WCAG contrast on the
  /// banner's tinted background: lighter on dark surfaces, darker on light
  /// ones. Keeps the token as the single source of hue.
  static Color _legibleShade(Color color, {required bool isDark}) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(isDark ? 0.75 : 0.20).toColor();
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
        border: switch (variant) {
          NoticeBannerVariant.info => Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
          ),
          // Weight, not just hue, so the highest severity reads as the
          // highest severity without relying on colour vision.
          NoticeBannerVariant.critical => Border.all(
            color: style.accent.withValues(alpha: 0.5),
          ),
          _ => null,
        },
      ),
      // Merged rather than replaced so callers keep their own sizes and
      // weights, and any explicit colour still overrides this one.
      child: DefaultTextStyle.merge(
        style: TextStyle(color: style.foreground),
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
                Expanded(
                  child: title == null
                      ? child
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title!,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: style.foreground,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            child,
                          ],
                        ),
                ),
              ],
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
