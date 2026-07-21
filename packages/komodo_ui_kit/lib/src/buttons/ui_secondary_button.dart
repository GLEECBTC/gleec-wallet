import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/src/buttons/ui_base_button.dart';

class UiSecondaryButton extends StatefulWidget {
  const UiSecondaryButton({
    required this.onPressed,
    this.buttonKey,
    this.text = '',
    this.width = double.infinity,
    this.height = 48.0,
    this.borderColor,
    this.textStyle,
    this.prefix,
    this.border,
    this.focusNode,
    this.shadowColor,
    this.child,
    super.key,
  });

  final String text;
  final TextStyle? textStyle;
  final double width;
  final double height;
  final Color? borderColor;
  final Widget? prefix;
  final Key? buttonKey;
  final BoxBorder? border;
  final void Function()? onPressed;
  final FocusNode? focusNode;
  final Color? shadowColor;
  final Widget? child;

  @override
  State<UiSecondaryButton> createState() => _UiSecondaryButtonState();
}

class _UiSecondaryButtonState extends State<UiSecondaryButton> {
  bool _hasFocus = false;
  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final colors = Theme.of(context).extension<GleecColorTokens>();
    final geometry = Theme.of(context).extension<GleecGeometry>();
    return UIBaseButton(
      isEnabled: widget.onPressed != null,
      width: widget.width,
      height: widget.height + ((textScale - 1).clamp(0.0, 1.0).toDouble() * 32),
      border:
          widget.border ??
          (_hasFocus
              ? Border.all(
                  color: colors?.brand ?? Theme.of(context).colorScheme.primary,
                  width: geometry?.focusRingWidth ?? 3,
                )
              : null),
      child: ElevatedButton(
        focusNode: widget.focusNode,
        onFocusChange: (value) {
          setState(() {
            _hasFocus = value;
          });
        },
        onPressed: widget.onPressed,
        key: widget.buttonKey,
        style: ElevatedButton.styleFrom(
          shape: _shape,
          side: BorderSide(color: _borderColor, width: 1),
          shadowColor: _shadowColor,
          elevation: 1,
          backgroundColor:
              colors?.surfaceHigh ?? Theme.of(context).colorScheme.surface,
          foregroundColor:
              colors?.textPrimary ?? Theme.of(context).colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child:
            widget.child ??
            _ButtonContent(
              text: widget.text,
              textStyle: widget.textStyle,
              prefix: widget.prefix,
            ),
      ),
    );
  }

  Color get _borderColor {
    return widget.borderColor ??
        Theme.of(context).extension<GleecColorTokens>()?.controlBorder ??
        Theme.of(context).colorScheme.outline;
  }

  Color get _shadowColor {
    return _hasFocus ? widget.shadowColor ?? _borderColor : Colors.transparent;
  }

  OutlinedBorder get _shape {
    final geometry = Theme.of(context).extension<GleecGeometry>();
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(geometry?.radius16 ?? 16)),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.text,
    required this.textStyle,
    required this.prefix,
  });

  final String text;
  final TextStyle? textStyle;
  final Widget? prefix;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (prefix != null) ...[prefix!, const SizedBox(width: 8)],
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: textStyle ?? _defaultTextStyle(context),
          ),
        ),
      ],
    );
  }

  TextStyle? _defaultTextStyle(BuildContext context) {
    return Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 14);
  }
}
