import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class BorderLessSearchField extends StatelessWidget {
  const BorderLessSearchField({
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
    final themeData = Theme.of(context);

    return SizedBox(
      height: height,
      child: TextField(
        key: const Key('search-field'),
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        autofocus: true,
        decoration: InputDecoration(
          hintText: LocaleKeys.search.tr(),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(height * 0.5),
          ),
          prefixIcon: Icon(
            Icons.search,
            size: height * 0.6,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        style: themeData.textTheme.bodyMedium?.copyWith(fontSize: 14),
      ),
    );
  }
}
