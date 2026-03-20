import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class TableSearchField extends StatelessWidget {
  const TableSearchField({
    super.key,
    required this.onChanged,
    this.height = 44,
    this.controller,
    this.focusNode,
  });
  final ValueChanged<String> onChanged;
  final double height;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(fontSize: 12);

    return SizedBox(
      height: height,
      child: TextField(
        key: const Key('search-field'),
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        autofocus: isDesktop,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.zero,
          hintText: LocaleKeys.searchCoin.tr(),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(height * 0.5),
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 12,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        style: style,
      ),
    );
  }
}
