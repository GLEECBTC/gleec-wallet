import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/models/price_chart_data.dart';

class PriceChartTooltip extends StatelessWidget {
  final Map<PriceChartSeriesPoint, CoinPriceInfo> dataPointCoinMap;

  PriceChartTooltip({Key? key, required this.dataPointCoinMap})
    : super(key: key);

  late final double? commonX =
      dataPointCoinMap.keys.every(
        (element) =>
            element.unixTimestamp == dataPointCoinMap.keys.first.unixTimestamp,
      )
      ? dataPointCoinMap.keys.first.unixTimestamp
      : null;

  String valueToString(double value) {
    if (!value.isFinite) {
      return '--';
    }
    if (value.abs() > 1000) {
      return '\$${value.toStringAsFixed(2)}';
    } else {
      return '\$${value.toStringAsPrecision(4)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMultipleCoins = dataPointCoinMap.length > 1;
    return ChartTooltipContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (commonX != null) ...[
            Text(
              // TODO! Dynamic based on selected period. Try share logic
              // with parent widget.

              // For 1M, use format with example of "June 12, 2023"
              DateFormat(
                'MMMM d, y',
              ).format(DateTime.fromMillisecondsSinceEpoch(commonX!.toInt())),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
          ],
          if (isMultipleCoins)
            ...dataPointCoinMap.entries.map((entry) {
              final data = entry.key;
              final coin = entry.value;
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  AssetIcon.ofTicker(coin.id),
                  const SizedBox(width: 4),
                  Text(
                    '${coin.name}: ${valueToString(data.usdValue)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              );
            }).toList()
          else
            Text(
              valueToString(dataPointCoinMap.keys.first.usdValue),
              style: Theme.of(context).textTheme.labelLarge,
            ),
        ],
      ),
    );
  }
}
