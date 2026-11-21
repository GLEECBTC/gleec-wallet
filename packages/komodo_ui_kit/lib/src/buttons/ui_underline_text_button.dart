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
    super.key,
  });
  final String text;
  final double width;
  final double height;
  final FontWeight textFontWeight;
  final double? textFontSize;
  final void Function()? onPressed;

  @override
  State<UiUnderlineTextButton> createState() => _UiUnderlineTextButtonState();
}

class _UiUnderlineTextButtonState extends State<UiUnderlineTextButton> {
  @override
  Widget build(BuildContext context) {
    final buttonTextStyle = Theme.of(context).textTheme.labelLarge;

    return Container(
      constraints:
          BoxConstraints.tightFor(width: widget.width, height: widget.height),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      child: ElevatedButton(
        onPressed: widget.onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
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
            style: buttonTextStyle?.copyWith(
              fontWeight: widget.textFontWeight,
              fontSize: widget.textFontSize,
            ),
          ),
        ),
      ),
    );
  }
}
