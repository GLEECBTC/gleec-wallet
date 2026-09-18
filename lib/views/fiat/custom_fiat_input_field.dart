import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class CustomFiatInputField extends StatefulWidget {
  const CustomFiatInputField({
    required this.controller,
    required this.hintText,
    required this.onTextChanged,
    required this.assetButton,
    super.key,
    this.label,
    this.readOnly = false,
    this.inputError,
    this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final Widget? label;
  final void Function(String?) onTextChanged;
  final bool readOnly;
  final Widget assetButton;
  final String? inputError;
  final FocusNode? focusNode;
  final void Function(String)? onSubmitted;

  @override
  State<CustomFiatInputField> createState() => _CustomFiatInputFieldState();
}

class _CustomFiatInputFieldState extends State<CustomFiatInputField> {
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurfaceVariant;

    final inputStyle = Theme.of(context).textTheme.headlineLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w300,
      color: textColor,
      letterSpacing: 1.1,
    );

    final InputDecoration inputDecoration = InputDecoration(
      label: widget.label,
      labelStyle: inputStyle,
      fillColor: Theme.of(context).scaffoldBackgroundColor,
      floatingLabelStyle: Theme.of(
        context,
      ).inputDecorationTheme.floatingLabelStyle,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      hintText: widget.hintText,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(4),
          topLeft: Radius.circular(4),
          bottomRight: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      errorText: widget.inputError,
      errorMaxLines: 1,
      helperText: '',
    );

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerRight,
      children: [
        TextField(
          autofocus: false,
          controller: widget.controller,
          focusNode: _focusNode,
          style: inputStyle,
          decoration: inputDecoration,
          readOnly: widget.readOnly,
          onChanged: widget.onTextChanged,
          onSubmitted: (value) {
            _focusNode.unfocus();
            widget.onSubmitted?.call(value);
          },
          inputFormatters: [
            FilteringTextInputFormatter.allow(numberRegExp),
            DecimalTextInputFormatter(decimalRange: 2),
          ],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
        ),
        Positioned(right: 16, bottom: 26, top: 2, child: widget.assetButton),
      ],
    );
  }
}
