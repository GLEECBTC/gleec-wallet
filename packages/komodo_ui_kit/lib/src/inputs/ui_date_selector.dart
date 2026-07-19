import 'package:app_theme/app_theme.dart';

import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class UiDatePicker extends StatelessWidget {
  const UiDatePicker({
    Key? key,
    required this.date,
    required this.text,
    required this.onDateSelect,
    required this.formatter,
    this.startDate,
    this.endDate,
    this.isMobileAlternative = false,
  }) : super(key: key);
  final String text;
  final DateTime? date;
  final DateTime? startDate;
  final DateTime? endDate;
  final void Function(DateTime?) onDateSelect;
  final bool isMobileAlternative;
  final String Function(DateTime) formatter;

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final DateTime now = DateTime.now();
    final DateTime? selectedTime = date;
    final DateTime initialDate = selectedTime ?? startDate ?? endDate ?? now;
    final DateTime firstDate = startDate ?? DateTime(2010);
    final DateTime lastDate = endDate ?? now.add(const Duration(days: 1));

    return InkWell(
      radius: 18,
      onTap: () async {
        final DateTime? time = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          builder: (BuildContext context, Widget? child) {
            return Theme(
              data: ThemeData(
                useMaterial3: false,
                dialogTheme: themeData.dialogTheme.copyWith(
                  backgroundColor: themeData.colorScheme.onSurface,
                ),
                colorScheme: themeData.colorScheme.copyWith(
                  surface: themeData.colorScheme.onSurface,
                  onSurface: themeData.textTheme.bodyMedium?.color,
                ),
              ),
              child: child ?? const SizedBox(),
            );
          },
        );
        onDateSelect(time);
      },
      child: Theme(
        data: Theme.of(context),
        child: Builder(
          builder: (context) {
            final ext = Theme.of(context).extension<ColorSchemeExtension>();
            return isMobileAlternative
                ? _AlternativeMobileCard(
                    title: selectedTime != null
                        ? formatter(selectedTime)
                        : text,
                    selectedCardColor: ext?.primary,
                    selectedTextColor: ext?.surf,
                    unselectedCardColor: ext?.surfCont,
                    unselectedTextColor: ext?.s70,
                    isSelected: selectedTime != null,
                  )
                : UIChip(
                    title: selectedTime != null
                        ? formatter(selectedTime)
                        : text,
                    colorScheme: UIChipColorScheme(
                      emptyContainerColor: ext?.surfCont,
                      emptyTextColor: ext?.s70,
                      pressedContainerColor: ext?.surfContLowest,
                      selectedContainerColor: ext?.primary,
                      selectedTextColor: ext?.surf,
                    ),
                    status: selectedTime != null
                        ? UIChipState.selected
                        : UIChipState.empty,
                  );
          },
        ),
      ),
    );
  }
}

class _AlternativeMobileCard extends StatelessWidget {
  final String title;
  final Color? selectedCardColor;
  final Color? selectedTextColor;
  final Color? unselectedCardColor;
  final Color? unselectedTextColor;
  final bool isSelected;

  const _AlternativeMobileCard({
    required this.title,
    required this.selectedCardColor,
    required this.selectedTextColor,
    required this.unselectedCardColor,
    required this.unselectedTextColor,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.center,
      height: 56,
      constraints: const BoxConstraints(maxHeight: 56),
      decoration: BoxDecoration(
        color: isSelected ? selectedCardColor : unselectedCardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isSelected ? selectedTextColor : unselectedTextColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
