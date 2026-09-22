import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/shared/widgets/need_attention_mark.dart';

class DesktopMenuDesktopItem extends StatelessWidget {
  const DesktopMenuDesktopItem({
    Key? key,
    required this.menu,
    required this.isSelected,
    required this.onTap,
    this.needAttention = false,
    this.enabled = true,
  }) : super(key: key);

  final MainMenuValue menu;
  final bool isSelected;
  final bool enabled;
  final bool needAttention;
  final Function(MainMenuValue) onTap;

  @override
  Widget build(BuildContext context) {
    final TextStyle? textStyle = _getTextStyle(context);

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: _getBackgroundColor(context),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? () => onTap(menu) : null,
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            mouseCursor: enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.forbidden,
            child: Row(
              children: [
                NeedAttentionMark(needAttention),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        NavIcon(item: menu, isActive: isSelected),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: AutoScrollText(
                                  text: menu.title,
                                  style: textStyle,
                                ),
                              ),
                              if (menu.isNew)
                                const SizedBox(width: 6), // Add some spacing
                              if (menu.isNew) const _LabelNew(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle? _getTextStyle(BuildContext context) {
    final ThemeData themeData = Theme.of(context);

    if (enabled) {
      return themeData.textTheme.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isSelected
            ? theme.custom.mainMenuSelectedItemColor
            : theme.custom.mainMenuItemColor,
      );
    }

    return Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14);
  }

  Color _getBackgroundColor(BuildContext context) {
    return enabled && isSelected
        ? theme.custom.selectedMenuBackgroundColor
        : Theme.of(context).scaffoldBackgroundColor;
  }
}

class _LabelNew extends StatelessWidget {
  const _LabelNew();

  @override
  Widget build(BuildContext context) {
    final themeData = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            themeData.colorScheme.primary,
            themeData.colorScheme.inversePrimary,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 1, 5, 1),
        child: Text(
          LocaleKeys.newText.tr(),
          style: TextStyle(
            color: theme.custom.defaultGradientButtonTextColor,
            fontSize: 11,
            height: 1,
          ),
        ),
      ),
    );
  }
}
