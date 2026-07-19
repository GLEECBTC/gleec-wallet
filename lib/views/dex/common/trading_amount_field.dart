import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class TradingAmountField extends StatelessWidget {
  const TradingAmountField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onChanged,
    this.height = 52,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 12),
    this.inputKey = const Key('amount-input'),
  });

  final TextEditingController controller;
  final bool enabled;
  final Function(String)? onChanged;
  final double height;
  final EdgeInsetsGeometry contentPadding;
  final Key inputKey;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final typography = GleecTypography.of(context);
    return SizedBox(
      height: height,
      child: TextFormField(
        key: inputKey,
        controller: controller,
        enabled: enabled,
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.end,
        inputFormatters: currencyInputFormatters,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: typography.tabularAmountCompact.copyWith(
          fontSize: 16,
          color: colors.textPrimary,
          decoration: TextDecoration.none,
        ),
        decoration: InputDecoration(
          hintText: '0.00',
          contentPadding: contentPadding,
          filled: true,
          fillColor: colors.surfaceHighest,
        ),
        onChanged: onChanged,
      ),
    );
  }
}
