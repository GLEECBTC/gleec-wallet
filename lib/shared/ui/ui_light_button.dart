import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class UiLightButton extends StatelessWidget {
  const UiLightButton({
    super.key,
    this.text = '',
    this.width = double.infinity,
    this.height = 48.0,
    this.prefix,
    this.backgroundColor,
    this.border,
    this.textStyle,
    required this.onPressed,
  });

  final String text;
  final TextStyle? textStyle;
  final double width;
  final double height;
  final Widget? prefix;
  final Color? backgroundColor;
  final BoxBorder? border;
  final void Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final geometry =
        Theme.of(context).extension<GleecGeometry>() ?? GleecGeometry.standard;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final scaledHeight =
        (height < geometry.minimumTapTarget
            ? geometry.minimumTapTarget
            : height) +
        ((textScale - 1).clamp(0.0, 1.0).toDouble() * 32);
    final TextStyle? style = Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontWeight: FontWeight.w500, fontSize: 14)
        .merge(textStyle);

    return SizedBox(
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: geometry.minimumTapTarget,
          minHeight: scaledHeight,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(18)),
            border: border,
          ),
          child: TextButton(
            onPressed: onPressed,
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll<Size>(
                Size(geometry.minimumTapTarget, scaledHeight),
              ),
              padding: const WidgetStatePropertyAll<EdgeInsets>(
                EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18.0),
                ),
              ),
              backgroundColor: WidgetStatePropertyAll<Color?>(
                backgroundColor ?? Theme.of(context).colorScheme.surface,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (prefix != null) ...[prefix!, const SizedBox(width: 8)],
                Flexible(
                  child: Text(text, textAlign: TextAlign.center, style: style),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
