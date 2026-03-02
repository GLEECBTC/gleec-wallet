import 'package:flutter/material.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:app_theme/src/dark/theme_custom_dark.dart';
import 'package:app_theme/src/light/theme_custom_light.dart';

class SelectedCoinGraphControl extends StatelessWidget {
  const SelectedCoinGraphControl({
    required this.centreAmount,
    required this.percentageIncrease,
    this.onCoinSelected,
    this.emptySelectAllowed = true,
    this.selectedCoinId,
    this.availableCoins,
    this.customCoinItemBuilder,
    super.key,
  });

  final Function(String?)? onCoinSelected;
  final bool emptySelectAllowed;
  final String? selectedCoinId;
  final double centreAmount;
  final double percentageIncrease;

  /// A list of coin IDs that are available for selection.
  ///
  /// Must be non-null and not empty if [onCoinSelected] is non-null.
  final List<AssetId>? availableCoins;

  final DropdownMenuItem<AssetId> Function(AssetId)? customCoinItemBuilder;

  @override
  Widget build(BuildContext context) {
    // assert(onCoinSelected != null || emptySelectAllowed);

    // If onCoinSelected is non-null, then availableCoins must be non-null
    assert(onCoinSelected == null || availableCoins != null);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 600;

        final themeCustom = Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).extension<ThemeCustomDark>()!
            : Theme.of(context).extension<ThemeCustomLight>()!;
        final bool isCentreAmountValid = centreAmount.isFinite;
        final double safeCentreAmount = isCentreAmountValid
            ? centreAmount
            : 0.0;
        final double safePercentage = percentageIncrease.isFinite
            ? percentageIncrease
            : 0.0;
        final String centreAmountText = isCentreAmountValid
            ? (NumberFormat.currency(symbol: "\$")
                    ..minimumSignificantDigits = 3
                    ..minimumFractionDigits = 2)
                  .format(safeCentreAmount)
            : '--';

        return ClipRect(
          child: Container(
            alignment: Alignment.center,
            height: 40,
            child: DividedButton(
              onPressed: onCoinSelected == null
                  ? null
                  : () async {
                      final selectedCoin = await showCoinSearch(
                        context,
                        coins: availableCoins!,
                        customCoinItemBuilder: customCoinItemBuilder,
                      );
                      if (selectedCoin != null) {
                        onCoinSelected?.call(selectedCoin.id);
                      }
                    },
              children: [
                Container(
                  // Min width of 48
                  constraints: const BoxConstraints(minWidth: 48),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 8),

                  child: selectedCoinId != null
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            AssetIcon.ofTicker(selectedCoinId!, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              selectedCoinId!,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            if (emptySelectAllowed &&
                                selectedCoinId != null) ...[
                              const SizedBox(width: 4),
                              SizedBox(
                                width: 16,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.clear),
                                  iconSize: 16,
                                  splashRadius: 20,
                                  onPressed: () => onCoinSelected?.call(null),
                                ),
                              ),
                            ],
                          ],
                        )
                      : Text(
                          'All',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                ),
                if (isWideScreen)
                  Text(
                    centreAmountText,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      // TODO: Incorporate into theme and remove duplication accross charts
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TrendPercentageText(
                      percentage: safePercentage,
                      upColor: themeCustom.increaseColor,
                      downColor: themeCustom.decreaseColor,
                    ),
                    if (onCoinSelected != null) ...[
                      const SizedBox(width: 2),
                      const Icon(Icons.expand_more),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
