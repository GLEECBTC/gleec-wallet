import 'package:flutter/material.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

/// How a [SwapButton] is drawn.
enum SwapButtonVariant { primary, secondary, danger }

/// The swap surface's full-width action button.
class SwapButton extends StatelessWidget {
  const SwapButton({
    required this.label,
    required this.onPressed,
    this.variant = SwapButtonVariant.primary,
    this.busy = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final SwapButtonVariant variant;

  /// Shows a spinner and ignores presses until the work is done. It keeps
  /// its enabled colours, as its label is the status to read, and stays
  /// focusable: disabling a focused button moves keyboard focus elsewhere.
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final pressable = onPressed != null && !busy;
    final (background, foreground, border) = switch (variant) {
      SwapButtonVariant.primary => (
        palette.brand,
        palette.onBrand,
        palette.brand,
      ),
      SwapButtonVariant.secondary => (
        palette.surfaceHigh,
        palette.text,
        palette.controlBorder,
      ),
      SwapButtonVariant.danger => (
        palette.dangerBg,
        palette.danger,
        palette.danger,
      ),
    };
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
      shape: WidgetStateProperty.resolveWith(
        (states) => RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: states.contains(WidgetState.disabled)
                ? palette.borderStrong
                : border,
          ),
        ),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return palette.disabled;
        if (pressable &&
            variant == SwapButtonVariant.primary &&
            states.contains(WidgetState.pressed)) {
          return palette.brandPressed;
        }
        return background;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? palette.onDisabled
            : foreground,
      ),
      overlayColor: WidgetStatePropertyAll(
        pressable ? foreground.withValues(alpha: 0.08) : Colors.transparent,
      ),
      mouseCursor: busy
          ? const WidgetStatePropertyAll(SystemMouseCursors.basic)
          : null,
      elevation: const WidgetStatePropertyAll(0),
      textStyle: WidgetStatePropertyAll(
        SwapText.strong(context).copyWith(fontWeight: FontWeight.w800),
      ),
    );
    // The two equal slots keep the label centred when work starts. Only the
    // busy indicator changes; its arrival never moves the button or its text.
    final leading = busy
        ? SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foreground,
              value: SwapMotion.enabled(context) ? null : 0.75,
            ),
          )
        : icon == null
        ? null
        : Icon(icon, size: 18);
    // One node in every state, so a screen reader's focus stays on the
    // button as it turns busy, and hears it as unavailable until it is done.
    return SwapButtonSemantics(
      label: label,
      onTap: pressable ? onPressed : null,
      child: SwapPressScale(
        enabled: pressable,
        child: TextButton(
          style: style,
          onPressed: busy ? () {} : onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                child: Align(
                  alignment: Alignment.centerLeft,
                  heightFactor: 1,
                  child: leading ?? const SizedBox(),
                ),
              ),
              Flexible(child: Text(label, textAlign: TextAlign.center)),
              const SizedBox(width: 26),
            ],
          ),
        ),
      ),
    );
  }
}

/// A text-only action in the brand colour, at least 48 dp square.
class SwapLinkButton extends StatelessWidget {
  const SwapLinkButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Shows a spinner, and ignores presses until the work is done. It stays
  /// enabled: disabling a focused button moves keyboard focus elsewhere.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return TextButton(
      onPressed: busy && onPressed != null ? () {} : onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(SwapGeometry.touchTarget, 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        foregroundColor: palette.brandHover,
        textStyle: SwapText.strong(context).copyWith(fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.brandHover,
              ),
            ),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 6),
          ],
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

/// A 48 dp square icon action: close, back.
class SwapIconButton extends StatelessWidget {
  const SwapIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return SwapButtonSemantics(
      label: label,
      onTap: onPressed,
      child: Tooltip(
        message: label,
        child: Material(
          color: palette.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: SizedBox.square(
              dimension: SwapGeometry.touchTarget,
              child: Icon(icon, color: palette.text, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// Announces [child] as one button named [label].
///
/// Replacing the child's semantics also drops its tap, so the tap is given
/// here again; without it a screen reader can focus the button but not press
/// it.
class SwapButtonSemantics extends StatelessWidget {
  const SwapButtonSemantics({
    required this.label,
    required this.onTap,
    required this.child,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    enabled: onTap != null,
    label: label,
    onTap: onTap,
    excludeSemantics: true,
    child: child,
  );
}
