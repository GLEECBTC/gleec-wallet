import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// The surface every Security settings section sits on, so the page reads as
/// one list whatever a section holds.
class SecuritySectionCard extends StatelessWidget {
  const SecuritySectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: AppSurface.card(palette),
      child: child,
    );
  }
}

/// The three text weights a section uses: its title, its body one step
/// lighter, and supporting detail.
abstract final class SecuritySectionText {
  static TextStyle? title(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 16);

  /// A heading inside a section, below its title.
  static TextStyle? label(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium
          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 14);

  static TextStyle? body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      );

  // The theme draws small text at 80% opacity, which falls under 4.5:1 on
  // this surface in the light theme.
  static TextStyle? supporting(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurface);
}

/// The quieter action beside a section's primary one.
class SecuritySecondaryButton extends StatelessWidget {
  const SecuritySecondaryButton({
    required this.text,
    required this.onPressed,
    this.icon,
    this.width = double.infinity,
    super.key,
  });

  final String text;
  final VoidCallback? onPressed;
  final Widget? icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      // A node of its own: merged upwards, the button would take the section
      // text beside it as its name and lose its own label.
      container: true,
      // The kit's border button is an ink well, which reports a tap but not
      // that it is a button.
      button: true,
      enabled: onPressed != null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: UiBorderButton(
          width: width,
          allowMultiline: true,
          borderWidth: 2,
          borderColor: palette.border,
          backgroundColor: palette.surfaceHigh,
          prefix: icon == null
              ? null
              : IconTheme.merge(
                  data: IconThemeData(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: icon!,
                ),
          text: text,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
