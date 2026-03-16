import 'package:dragon_charts_flutter/dragon_charts_flutter.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/models/price_chart_data.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/models/time_period.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/price_chart_bloc.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/price_chart_event.dart';
import 'package:web_dex/bloc/cex_market_data/price_chart/price_chart_state.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/coin_select_item_widget.dart';

import 'price_chart_tooltip.dart';

class PriceChartPage extends StatelessWidget {
  final List<TimePeriod> intervals = TimePeriod.values;

  const PriceChartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        height: 340,
        padding: const EdgeInsets.all(16),
        child: BlocBuilder<PriceChartBloc, PriceChartState>(
          builder: (context, state) {
            final lastPoint = state.data.firstOrNull?.data.lastOrNull;
            final double? lastValue = lastPoint?.usdValue;
            final bool hasValidValue = lastValue != null && lastValue.isFinite;
            final double safeLastValue = hasValidValue ? lastValue : 0.0;
            final double safePercentageIncrease =
                (state
                            .data
                            .firstOrNull
                            ?.info
                            .selectedPeriodIncreasePercentage ??
                        0)
                    .isFinite
                ? (state
                          .data
                          .firstOrNull
                          ?.info
                          .selectedPeriodIncreasePercentage ??
                      0)
                : 0.0;
            return Column(
              children: [
                MarketChartHeaderControls(
                  title: Text(LocaleKeys.statistics.tr()),
                  leadingIcon: state.data.firstOrNull?.info.ticker == null
                      ? const Icon(Icons.attach_money, size: 22)
                      : AssetIcon.ofTicker(
                          state.data.firstOrNull?.info.ticker ?? '',
                          size: 22,
                        ),
                  leadingText: Text(
                    hasValidValue
                        ? NumberFormat.currency(
                            symbol: '\$',
                            decimalDigits: 4,
                          ).format(safeLastValue)
                        : '--',
                  ),
                  availableCoins: state.availableCoins.keys.toList(),
                  selectedCoinId: state.data.firstOrNull?.info.ticker,
                  onCoinSelected: (coinId) {
                    context.read<PriceChartBloc>().add(
                      PriceChartCoinsSelected(coinId == null ? [] : [coinId]),
                    );
                  },
                  centreAmount: safeLastValue,
                  percentageIncrease: safePercentageIncrease,
                  selectedPeriod: state.selectedPeriod,
                  onPeriodChanged: (newPeriod) {
                    context.read<PriceChartBloc>().add(
                      PriceChartPeriodChanged(newPeriod!),
                    );
                  },
                  customCoinItemBuilder: (coinId) {
                    final coin = state.availableCoins[coinId.symbol.common];

                    return CoinSelectItemWidget.dropdownMenuItem(
                      coinId,
                      trendPercentage: coin?.selectedPeriodIncreasePercentage,
                    );
                  },
                ),
                const Gap(16),
                Expanded(
                  child: BlocBuilder<PriceChartBloc, PriceChartState>(
                    builder: (context, state) {
                      if (state.status == PriceChartStatus.failure) {
                        return Center(child: Text('Error: ${state.error}'));
                      } else if (state.status == PriceChartStatus.loading &&
                          !state.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (state.status == PriceChartStatus.success ||
                          state.hasData) {
                        final coinsData = state.data;

                        final (labelCount, labelDateFormat) =
                            dateAxisLabelCountFormat(state.selectedPeriod);

                        return SizedBox(
                          width: double.infinity,
                          child: LineChart(
                            key: const Key('price_chart'),
                            domainExtent: const ChartExtent.tight(),
                            rangeExtent: const ChartExtent.tight(
                              paddingPortion: 0.1,
                            ),
                            elements: [
                              ChartAxisLabels(
                                isVertical: true,
                                count: 5,
                                labelBuilder: (value) {
                                  return NumberFormat.compact().format(value);
                                },
                              ),
                              ChartAxisLabels(
                                isVertical: false,
                                count: labelCount,
                                labelBuilder: (value) {
                                  return labelDateFormat.format(
                                    DateTime.fromMillisecondsSinceEpoch(
                                      value.toInt(),
                                    ),
                                  );
                                },
                              ),
                              for (var i = 0; i < coinsData.length; i++)
                                ChartDataSeries(
                                  data: coinsData[i].data.map((e) {
                                    return ChartData(
                                      x: e.unixTimestamp,
                                      y: e.usdValue,
                                    );
                                  }).toList(),
                                  color:
                                      getCoinColor(
                                        coinsData.elementAt(i).info.ticker,
                                      ) ??
                                      Theme.of(context).colorScheme.primary,
                                  strokeWidth: 3,
                                ),
                              ChartGridLines(isVertical: false, count: 5),
                            ],
                            backgroundColor: Colors.transparent,
                            tooltipBuilder: (context, dataPoints, dataColors) {
                              final Map<PriceChartSeriesPoint, CoinPriceInfo>
                              dataPointCoinMap = {
                                for (var i = 0; i < dataPoints.length; i++)
                                  PriceChartSeriesPoint(
                                    usdValue: dataPoints[i].y,
                                    unixTimestamp: dataPoints[i].x,
                                  ): coinsData[i].info,
                              };
                              return PriceChartTooltip(
                                dataPointCoinMap: dataPointCoinMap,
                              );
                            },
                            markerSelectionStrategy: CartesianSelectionStrategy(
                              snapToClosest: true,
                              lineWidth: 1,
                              dashSpace: 0.5,
                              verticalLineColor: const Color(0xFF45464E),
                            ),
                          ),
                        );
                      } else {
                        return Center(
                          child: Text(LocaleKeys.priceChartCenterText.tr()),
                        );
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Returns the count and format for the date axis labels based on the
  /// selected period.
  ///
  /// (int) count: The number of labels to show.
  /// (DateFormat) format: The format to use for the labels.
  ///
  /// Example usage:
  /// ```dart
  /// final (count, format) = dateAxisLabelCountFormat(Duration(days: 7));
  ///
  /// ```
  ///
  static (int, DateFormat) dateAxisLabelCountFormat(Duration period) {
    const averageDaysPerMonth = 30.437;

    int? count;
    DateFormat? format;

    // For more than 1 month, show one label for each month up to a max of
    // 12 labels. Include the abbreviated year if the period is more than 1 year.
    if (period.inDays >= 28) {
      final monthsCount = period.inDays ~/ averageDaysPerMonth;
      // 1 label for each month with minimum of 6 labels and max of 12 labels.
      count = monthsCount.clamp(6, 12);
      format = DateFormat("MMM"); // e.g. Jan

      // If the period is more than 1 year, include the year in the label.
      // e.g. Jan '21
      if (period.inDays >= 365) {
        format = DateFormat("MMM ''yy");
      }
      // If there are more than 1 label for each month, show the month and day.
      // e.g. Jan 1
      if (count > monthsCount) {
        format = DateFormat("MMM d");
      }
      return (count, format);
    }
    // Otherwise, if it's more than 1 week, but less than 1 month, show
    // 2 labels for each week.
    else if (period.inDays > 7) {
      count = (period.inDays ~/ 7) * 2;
      format = DateFormat("d"); // e.g. 1
      return (count, format);
    }
    // Otherwise if it's more than 3 days, but less than 1 week, show a label
    // for each day with the short day name.
    else if (period.inDays > 3) {
      count = period.inDays;
      format = DateFormat("EEE"); // e.g. Mon
      return (count, format);
    }
    // Otherwise if it's more than 24 hours, but less than 3 days, show 6
    // labels with the short day name and time.
    else if (period.inHours > 24) {
      count = 6;
      format = DateFormat("EEE HH:mm"); // e.g. Mon 12:00
      return (count, format);
    }

    // Otherwise if it's less than 24 hours, show 6 labels with the time.
    count = 6;
    format = DateFormat("HH:mm"); // e.g. 12:00

    return (count, format);
  }
}
