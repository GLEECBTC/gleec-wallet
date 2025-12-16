import 'package:flutter/material.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:app_theme/src/dark/theme_custom_dark.dart';
import 'package:app_theme/src/light/theme_custom_light.dart';

/// A widget that displays a coin item with the same parameters as
/// CoinSelectItem. This will be removed in the future. Migrate to the Asset
/// selection widgets in the SDK's `komodo_ui` package.
class CoinSelectItemWidget extends StatelessWidget {
  const CoinSelectItemWidget({
    required this.name,
    required this.coinId,
    this.leading,
    this.trailing,
    this.title,
    this.onTap,
    super.key,
  });

  final String name;
  final String coinId;

  /// The widget to display on the right side of the list item.
  ///
  /// E.g. to show balance or price increase percentage.
  ///
  /// If null, nothing will be displayed.
  final Widget? trailing;

  /// The widget to display on the left side of the list item.
  ///
  /// E.g. to show the coin icon.
  ///
  /// If null, the CoinIcon will be displayed with a size of 20.
  final Widget? leading;

  /// The widget to display the title of the list item.
  ///
  /// If null, the [name] will be displayed.
  final Widget? title;

  /// Called when the item is tapped
  final VoidCallback? onTap;

  static DropdownMenuItem<AssetId> dropdownMenuItem(
    AssetId id, {
    double? trendPercentage,
  }) {
    return DropdownMenuItem<AssetId>(
      value: id,
      child: CoinSelectItemWidget(
        name: id.name,
        coinId: id.id,
        trailing: trendPercentage != null
            ? Builder(
                builder: (context) {
                  final themeCustom =
                      Theme.of(context).brightness == Brightness.dark
                      ? Theme.of(context).extension<ThemeCustomDark>()!
                      : Theme.of(context).extension<ThemeCustomLight>()!;
                  return TrendPercentageText(
                    percentage: trendPercentage,
                    upColor: themeCustom.increaseColor,
                    downColor: themeCustom.decreaseColor,
                  );
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Use the text color from textTheme since onSurface is misused as a
    // background color in this codebase.
    final textColor =
        theme.textTheme.bodyMedium?.color ??
        (theme.brightness == Brightness.dark ? Colors.white : Colors.black);

    final baseTextStyle =
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w300);

    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          if (leading != null)
            Padding(padding: const EdgeInsets.only(right: 12), child: leading!)
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AssetLogo.ofTicker(coinId, size: 20),
            ),
          Expanded(
            child: DefaultTextStyle(
              style: baseTextStyle.copyWith(color: textColor),
              child: title ?? Text(name),
            ),
          ),
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(left: 8), child: trailing!),
        ],
      ),
    );
  }
}
