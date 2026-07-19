import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// A reusable text form field widget with customizable validation modes.
///
/// This widget provides several validation modes to control when validation
/// errors are shown. It also allows customization of its appearance and behavior.
///
/// The supported validation modes are:
/// - `aggressive`: Validate on every input change.
/// - `passive`: Validate on focus loss and form submission.
/// - `lazy`: Validate only on form submission.
/// - `eager`: Validate on focus loss and subsequent input changes.
///
/// The `UiTextFormField` can be customized using various parameters such as
/// `hintText`, `controller`, `inputFormatters`, `textInputAction`, and more.

class UiTextFormField extends StatefulWidget {
  const UiTextFormField({
    super.key,
    this.initialValue,
    this.hintText,
    this.labelText,
    this.controller,
    this.inputFormatters,
    this.textInputAction,
    this.style,
    this.hintTextStyle,
    this.labelStyle,
    this.inputContentPadding,
    this.keyboardType,
    this.validator,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.errorMaxLines,
    this.enableInteractiveSelection = true,
    this.autocorrect = true,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.enabled = true,
    this.focusNode,
    this.onFocus,
    this.fillColor,
    this.onFieldSubmitted,
    this.onChanged,
    this.suffix,
    this.maxLength,
    this.maxLengthEnforcement,
    this.counterText,
    this.helperText,
    this.enabledBorder,
    this.focusedBorder,
    this.errorStyle,
    this.validationMode = InputValidationMode.eager,
    this.autofillHints,
  });

  final String? initialValue;
  final String? hintText;
  final String? labelText;
  final String? helperText;
  final TextEditingController? controller;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final TextStyle? hintTextStyle;
  final TextStyle? labelStyle;
  final TextInputType? keyboardType;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int? maxLines;
  final int? errorMaxLines;
  final bool obscureText;
  final bool autocorrect;
  final bool enabled;
  final bool enableInteractiveSelection;
  final bool autofocus;
  final bool readOnly;
  final EdgeInsets? inputContentPadding;
  final FocusNode? focusNode;
  final void Function(FocusNode)? onFocus;
  final Color? fillColor;
  final void Function(String?)? onChanged;
  final void Function(String)? onFieldSubmitted;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final int? maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final String? counterText;
  final InputBorder? enabledBorder;
  final InputBorder? focusedBorder;
  final TextStyle? errorStyle;
  final InputValidationMode validationMode;
  final Iterable<String>? autofillHints;

  @override
  State<UiTextFormField> createState() => _UiTextFormFieldState();
}

class _UiTextFormFieldState extends State<UiTextFormField> {
  late FocusNode _focusNode;
  bool _shouldValidate = false;
  TextEditingController? _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
    if (widget.validationMode == InputValidationMode.aggressive) {
      _shouldValidate = true;
    }

    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant UiTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialValue != oldWidget.initialValue &&
        widget.controller == null) {
      _controller?.text = widget.initialValue ?? '';
    }
  }

  void _handleFocusChange() {
    if (!mounted) return;

    final shouldUpdate =
        !_focusNode.hasFocus &&
        (widget.validationMode == InputValidationMode.eager ||
            widget.validationMode == InputValidationMode.passive);

    if (shouldUpdate) {
      _shouldValidate = true;
    }

    setState(() {
      if (widget.onFocus != null) {
        widget.onFocus!(_focusNode);
      }

      if (_focusNode.hasFocus &&
          widget.validationMode == InputValidationMode.aggressive) {
        _shouldValidate = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final defaultStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: theme.textTheme.bodyMedium?.color,
    );
    final style = widget.style?.merge(defaultStyle) ?? defaultStyle;

    final defaultLabelStyle =
        theme.inputDecorationTheme.labelStyle ??
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
        );
    final labelStyle =
        widget.labelStyle?.merge(defaultLabelStyle) ?? defaultLabelStyle;

    final defaultHintStyle =
        theme.inputDecorationTheme.hintStyle ??
        TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
        );
    final hintStyle =
        widget.hintTextStyle?.merge(defaultHintStyle) ?? defaultHintStyle;

    final defaultErrorStyle =
        theme.inputDecorationTheme.errorStyle ??
        TextStyle(fontSize: 12, color: theme.colorScheme.error);
    final errorStyle =
        widget.errorStyle?.merge(defaultErrorStyle) ?? defaultErrorStyle;

    final fillColor = widget.fillColor ?? theme.inputDecorationTheme.fillColor;

    final AutovalidateMode autovalidateMode;
    switch (widget.validationMode) {
      case InputValidationMode.aggressive:
        autovalidateMode = AutovalidateMode.always;
        break;
      case InputValidationMode.eager:
      case InputValidationMode.passive:
        autovalidateMode = _shouldValidate
            ? AutovalidateMode.always
            : AutovalidateMode.disabled;
        break;
      case InputValidationMode.lazy:
        autovalidateMode = AutovalidateMode.disabled;
        break;
    }

    final geometry = theme.extension<GleecGeometry>() ?? GleecGeometry.standard;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: geometry.inputHeight),
      child: TextFormField(
        controller: _controller,
        maxLength: widget.maxLength,
        maxLengthEnforcement: widget.maxLengthEnforcement,
        inputFormatters: widget.inputFormatters,
        autofillHints: widget.autofillHints,
        validator: (value) {
          // Always return the validator result so FormState.validate() reflects correctness
          final error = widget.validator?.call(value) ?? widget.errorText;
          return error;
        },
        onChanged: (value) {
          widget.onChanged?.call(value);
        },
        onFieldSubmitted: widget.onFieldSubmitted,
        enableInteractiveSelection: widget.enableInteractiveSelection,
        textInputAction: widget.textInputAction,
        style: style,
        autovalidateMode: autovalidateMode,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        autocorrect: widget.autocorrect,
        autofocus: widget.autofocus,
        maxLines: widget.maxLines,
        readOnly: widget.readOnly,
        focusNode: _focusNode,
        enabled: widget.enabled,
        decoration: InputDecoration(
          fillColor: fillColor,
          filled: fillColor != null,
          hintText: widget.hintText,
          hintStyle: hintStyle,
          contentPadding:
              widget.inputContentPadding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          counterText: widget.counterText,
          labelText: widget.labelText ?? widget.hintText,
          labelStyle: labelStyle,
          helperText: widget.helperText,
          // If an external errorText provided, show it; otherwise let Form/validator drive error display
          errorText: widget.errorText,
          errorStyle: errorStyle,
          prefixIcon: widget.prefixIcon,
          suffixIcon: widget.suffixIcon,
          errorMaxLines: widget.errorMaxLines,
          suffix: widget.suffix,
          enabledBorder: widget.enabledBorder,
          focusedBorder: widget.focusedBorder,
        ),
      ),
    );
  }
}
