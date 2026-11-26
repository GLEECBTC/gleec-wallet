import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/src/buttons/ui_base_button.dart';
import 'package:komodo_ui_kit/src/design_system/app_palette_scope.dart';

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
    return UIBaseButton(
      isEnabled: widget.onPressed != null,
      width: widget.width,
      height: widget.height,
      border: widget.border,
      child: ElevatedButton(
        focusNode: widget.focusNode,
        onFocusChange: (value) {
          setState(() {
            _hasFocus = value;
          });
        },
        onPressed: widget.onPressed ?? () {},
        key: widget.buttonKey,
        style: ElevatedButton.styleFrom(
          shape: _shape,
          side: BorderSide(
            color: _borderColor,
            width: 1,
          ),
          shadowColor: _shadowColor,
          elevation: 1,
          backgroundColor: Colors.transparent,
          foregroundColor: _borderColor,
          padding: EdgeInsets.zero,
        ),
        child: widget.child ??
            _ButtonContent(
              text: widget.text,
              textStyle: widget.textStyle,
              prefix: widget.prefix,
            ),
      ),
    );
  }

  // The label is drawn in this colour too; brandHover keeps it at 4.5:1 on
  // the palette's page, card and dialog surfaces, where brand is not.
  Color get _borderColor {
    return widget.borderColor ??
        AppPaletteScope.maybeOf(context)?.brandHover ??
        Theme.of(context).colorScheme.secondary;
  }

  Color get _shadowColor {
    return _hasFocus
        ? widget.shadowColor ?? Theme.of(context).colorScheme.primary
        : Colors.transparent;
  }

  OutlinedBorder get _shape => const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      );
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
        if (prefix != null) prefix!,
        Text(text, style: textStyle ?? _defaultTextStyle(context)),
      ],
    );
  }

  TextStyle? _defaultTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color:
          AppPaletteScope.maybeOf(context)?.brandHover ??
          Theme.of(context).colorScheme.secondary,
    );
  }
}
