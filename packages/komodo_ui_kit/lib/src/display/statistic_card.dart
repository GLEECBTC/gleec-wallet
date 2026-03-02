import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'auto_scroll_text.dart';

class StatisticCard extends StatelessWidget {
  // Text shown under the stat value title. Uses default of bodySmall style.
  final Widget caption;

  // The value of the stat used for the title. If null, shows a skeleton placeholder
  final double? value;
  final String? valueText;

  // The formatter used to format the value for the title
  final NumberFormat _valueFormatter;

  /// Callback when the card is tapped.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  // Widget shown in the top right corner (typically TrendPercentageText)
  final Widget? trendWidget;

  // Optional action widget (button or text) shown in the middle-right area
  final Widget? actionWidget;

  StatisticCard({
    super.key,
    this.value,
    this.valueText,
    required this.caption,
    this.trendWidget,
    this.actionWidget,
    NumberFormat? valueFormatter,
    this.onTap,
    this.onLongPress,
  }) : _valueFormatter = valueFormatter ?? NumberFormat.currency(symbol: '\$');

  // TODO! Refactor to theme and/or re-usable widget
  static LinearGradient containerGradient(ThemeData theme) {
    final cardColor = theme.cardColor;

    return LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: (theme.brightness == Brightness.light)
          ? [cardColor, cardColor]
          : [Color.fromRGBO(23, 24, 28, 1), theme.cardColor],
      stops: const [0.0, 1.0],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: containerGradient(Theme.of(context)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left side: Value and Caption
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Value or skeleton placeholder
                    value != null
                        ? AutoScrollText(
                            text: valueText ?? _valueFormatter.format(value!),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          )
                        : _ValuePlaceholder(),
                    const SizedBox(height: 4),
                    // Caption
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.bodySmall!,
                      child: caption,
                    ),
                    if (actionWidget != null) ...[
                      const SizedBox(height: 8),
                      actionWidget!,
                    ],
                  ],
                ),
              ),
              // Right side: Trend widget (vertically centered)
              if (trendWidget != null) ...[
                const SizedBox(width: 8),
                trendWidget!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ValuePlaceholder extends StatelessWidget {
  const _ValuePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 120,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
