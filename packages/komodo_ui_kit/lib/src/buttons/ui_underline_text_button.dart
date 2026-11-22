import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class UiUnderlineTextButton extends StatefulWidget {
  const UiUnderlineTextButton({
    required this.text,
    required this.onPressed,
    this.width = double.infinity,
    this.height = 48,
    this.textFontWeight = FontWeight.w700,
    this.textFontSize = 14,
    this.expandForText = false,
    super.key,
  });
  final String text;
  final double width;
  final double height;
  final FontWeight textFontWeight;
  final double? textFontSize;
  final void Function()? onPressed;

  /// Treat [height] as a minimum and wrap the complete label at large text
  /// sizes. Existing callers retain their fixed-height layout unless they opt
  /// in.
  final bool expandForText;

  @override
  State<UiUnderlineTextButton> createState() => _UiUnderlineTextButtonState();
}

class _UiUnderlineTextButtonState extends State<UiUnderlineTextButton> {
  @override
  Widget build(BuildContext context) {
    final buttonTextStyle = Theme.of(context).textTheme.labelLarge;

    return Container(
      constraints: widget.expandForText
          ? BoxConstraints(
              minWidth: widget.width,
              maxWidth: widget.width,
              minHeight: widget.height,
            )
          : BoxConstraints.tightFor(width: widget.width, height: widget.height),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      child: ElevatedButton(
        onPressed: widget.onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          // The app theme fills every disabled elevated button with grey,
          // which would turn this text-only button into a solid block.
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Opacity(
          // The label keeps its own colour, so dim it to show it is disabled.
          opacity: widget.onPressed == null ? 0.4 : 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 0.7,
                  color: buttonTextStyle?.color ?? theme.custom.noColor,
                ),
              ),
            ),
            child: Text(
              widget.text,
              textAlign: TextAlign.center,
              style: buttonTextStyle?.copyWith(
                fontWeight: widget.textFontWeight,
                fontSize: widget.textFontSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
