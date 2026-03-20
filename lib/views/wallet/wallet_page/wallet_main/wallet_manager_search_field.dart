import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class WalletManagerSearchField extends StatelessWidget {
  const WalletManagerSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChange,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const Key('wallet-page-search-field'),
      controller: controller,
      focusNode: focusNode,
      autocorrect: false,
      textInputAction: TextInputAction.search,
      enableInteractiveSelection: true,
      inputFormatters: [LengthLimitingTextInputFormatter(40)],
      onChanged: (value) => onChange(value.trim()),
      decoration: InputDecoration(
        filled: true,
        hintText: LocaleKeys.search.tr(),
        prefixIcon: Icon(Icons.search, size: 20),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
