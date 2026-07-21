import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class AmountInputField extends StatefulWidget {
  const AmountInputField({
    super.key,
    required this.stream,
    required this.initialData,
    required this.isEnabled,
    this.height = 44,
    this.contentPadding = const EdgeInsets.fromLTRB(12, 0, 12, 0),
    this.hint,
    this.suffix,
    this.onChanged,
    this.background,
    this.textAlign,
    this.textStyle,
  });

  final Stream<Rational?> stream;
  final Rational? initialData;
  final bool isEnabled;
  final Widget? suffix;
  final String? hint;
  final Function(String)? onChanged;
  final Color? background;
  final TextAlign? textAlign;
  final double height;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? contentPadding;

  @override
  State<AmountInputField> createState() => _AmountInputFieldState();
}

class _AmountInputFieldState extends State<AmountInputField> {
  final _controller = TextEditingController();
  StreamSubscription? _dataListener;

  @override
  void initState() {
    super.initState();

    _dataListener = widget.stream.listen(_onDataChange, onError: (_) {});
    _onDataChange(widget.initialData);
  }

  @override
  void dispose() {
    _dataListener?.cancel();
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final InputBorder border = OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.circular(18),
    );

    return SizedBox(
      height: widget.height,
      child: TextFormField(
        key: const Key('amount-input'),
        inputFormatters: currencyInputFormatters,
        controller: _controller,
        enabled: widget.isEnabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontSize: 14).merge(widget.textStyle),
        textInputAction: TextInputAction.done,
        onChanged: widget.onChanged,
        textAlign: widget.textAlign ?? TextAlign.left,
        decoration: InputDecoration(
          contentPadding: widget.contentPadding,
          suffix: widget.suffix,
          suffixStyle: widget.textStyle,
          hintText: widget.hint ?? 'Enter an amount',
          border: border,
          fillColor: widget.background,
          hoverColor: widget.background,
          focusColor: widget.background,
        ),
      ),
    );
  }

  void _onDataChange(Rational? value) {
    if (!mounted) return;
    final String currentText = _controller.text;
    if (currentText.isNotEmpty) {
      try {
        if (parseLocaleAwareRational(currentText) == value) return;
      } catch (_) {
        // Replace malformed or partial input with the canonical bloc value.
      }
    }

    final String newText = value == null ? '' : formatDexAmt(value);

    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
      composing: TextRange.empty,
    );
  }
}
