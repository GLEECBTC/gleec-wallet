import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class DexListFilterType<T> extends StatelessWidget {
  const DexListFilterType({
    Key? key,
    required this.values,
    required this.selectedValues,
    required this.onChange,
    required this.label,
    required this.isMobile,
    required this.titile,
  }) : super(key: key);

  final Function(List<T>?) onChange;
  final List<DexListFilterTypeValue<T>> values;
  final List<T>? selectedValues;
  final String label;
  final bool isMobile;
  final String titile;

  @override
  Widget build(BuildContext context) {
    return isMobile
        ? _DexListFilterTypeMobile<T>(
            label: label,
            selectedValues: selectedValues,
            values: values,
            onChange: onChange,
          )
        : _DexListFilterTypeDesktop<T>(
            title: titile,
            selectedValues: selectedValues,
            onChange: onChange,
            values: values,
          );
  }
}

class _DexListFilterTypeDesktop<T> extends StatelessWidget {
  const _DexListFilterTypeDesktop({
    Key? key,
    required this.values,
    required this.selectedValues,
    required this.onChange,
    required this.title,
  }) : super(key: key);

  final List<DexListFilterTypeValue<T>> values;
  final List<T>? selectedValues;
  final Function(List<T>) onChange;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context),
      child: Builder(
        builder: (context) {
          final ext = Theme.of(context).extension<ColorSchemeExtension>();
          return MultiSelectDropdownButton<T>(
            title: title,
            items: values.map((e) => e.value).toList(),
            displayItem: (p0) =>
                values.firstWhere((element) => element.value == p0).label,
            selectedItems: selectedValues,
            onChanged: onChange,
            colorScheme: UIChipColorScheme(
              emptyContainerColor: ext?.surfCont,
              emptyTextColor: ext?.s70,
              pressedContainerColor: ext?.surfContLowest,
              selectedContainerColor: ext?.primary,
              selectedTextColor: ext?.surf,
            ),
          );
        },
      ),
    );
  }
}

class _DexListFilterTypeMobile<T> extends StatelessWidget {
  const _DexListFilterTypeMobile({
    Key? key,
    required this.label,
    required this.values,
    required this.selectedValues,
    required this.onChange,
  }) : super(key: key);

  final List<DexListFilterTypeValue<T>> values;
  final List<T>? selectedValues;
  final String label;

  final Function(List<T>?) onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          flex: 2,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              _buildItem(values, LocaleKeys.all.tr(), context),
              ...values.map((v) => _buildItem([v], v.label, context)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItem(
    final List<DexListFilterTypeValue<T>> values,
    String label,
    BuildContext context,
  ) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    final typography = GleecTypography.of(context);
    const double borderWidth = 2.0;
    const double topPadding = 6.0;
    final selectedValues = this.selectedValues;
    final bool isSelected =
        selectedValues != null &&
        selectedValues.length == values.length &&
        selectedValues.every(
          (sv) => values.where((v) => v.value == sv).isNotEmpty,
        );

    return Padding(
      padding: isSelected
          ? const EdgeInsets.only(top: topPadding)
          : const EdgeInsets.fromLTRB(
              borderWidth,
              topPadding + borderWidth,
              borderWidth,
              borderWidth,
            ),
      child: InkWell(
        onTap: () => onChange(values.map((e) => e.value).toList()),
        child: Container(
          constraints: BoxConstraints(minHeight: geometry.minimumTapTarget),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.selected : colors.surfaceHigh,
            borderRadius: geometry.borderRadius16,
            border: isSelected
                ? Border.all(color: colors.brand, width: 2)
                : Border.all(color: colors.border),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: typography.labelMedium.copyWith(
              color: isSelected ? colors.brand : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class DexListFilterTypeValue<T> {
  DexListFilterTypeValue({required this.label, required this.value});
  final String label;
  final T value;
}
