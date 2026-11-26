import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/src/design_system/app_palette_scope.dart';

class UiCheckbox extends StatelessWidget {
  const UiCheckbox({
    required this.value,
    this.checkboxKey,
    this.onChanged,
    this.text = '',
    this.textWidget,
    this.size = 18,
    this.textColor,
    this.borderColor,
    super.key,
  });

  final Key? checkboxKey;
  final bool value;
  final String text;
  final Text? textWidget;
  final double size;
  final Color? borderColor;
  final Color? textColor;
  final void Function(bool)? onChanged;

  @override
  Widget build(BuildContext context) {
    final onTap = onChanged;
    final borderRadius = BorderRadius.circular(size / 3.6);
    final palette = AppPaletteScope.maybeOf(context);
    final fill = palette?.brand ?? theme.custom.defaultCheckboxColor;
    final outline = palette?.controlBorder ?? theme.custom.borderCheckboxColor;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onTap != null ? () => onTap(!value) : null,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: checkboxKey,
                constraints: BoxConstraints.tightFor(width: size, height: size),
                decoration: BoxDecoration(
                  color: value ? fill : theme.custom.noColor,
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: borderColor ?? (value ? fill : outline),
                  ),
                ),
                child: value
                    ? Center(
                        child: Icon(
                          Icons.check,
                          size: size * 0.8,
                          color:
                              palette?.onBrand ??
                              theme.custom.checkCheckboxColor,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (textWidget != null || text.isNotEmpty)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 2),
                    child: textWidget ??
                        Text(
                          text,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontSize: 14, color: textColor),
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
