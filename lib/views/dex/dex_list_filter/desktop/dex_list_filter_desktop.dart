import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/views/dex/dex_list_filter/common/dex_list_filter_type.dart';
import 'package:web_dex/views/dex/dex_list_filter/desktop/dex_list_filter_coin_desktop.dart';

class DexListFilterDesktop extends StatefulWidget {
  const DexListFilterDesktop({
    Key? key,
    this.filterData,
    required this.onApplyFilter,
    required this.listType,
  }) : super(key: key);
  final TradingEntitiesFilter? filterData;
  final DexListType listType;
  final void Function(TradingEntitiesFilter?) onApplyFilter;

  @override
  State<DexListFilterDesktop> createState() => _DexListFilterDesktopState();
}

const double _itemHeight = 48;

class _DexListFilterDesktopState extends State<DexListFilterDesktop> {
  late TradingEntitiesFilter _filterData;

  @override
  void initState() {
    _update();

    super.initState();
  }

  @override
  void didUpdateWidget(covariant DexListFilterDesktop oldWidget) {
    if (oldWidget.filterData != widget.filterData) _update();

    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    return Container(
      padding: EdgeInsets.all(geometry.space16),
      decoration: BoxDecoration(
        borderRadius: geometry.borderRadius20,
        color: colors.surfaceRaised,
        border: Border.all(color: colors.border),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 18,
          children: [
            Wrap(
              runSpacing: 8,
              spacing: 6,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints.tightFor(
                    width: 130,
                    height: _itemHeight,
                  ),
                  child: DexListFilterCoinDesktop(
                    label: LocaleKeys.buyAsset.tr(),
                    coinAbbr: _filterData.buyCoin,
                    isSellCoin: false,
                    listType: widget.listType,
                    anotherCoinAbbr: widget.filterData?.sellCoin,
                    onCoinSelect: (String? coin) {
                      setState(() {
                        _filterData.buyCoin = coin;
                      });
                      _applyFiltersData();
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints.tightFor(
                    width: 130,
                    height: _itemHeight,
                  ),
                  child: DexListFilterCoinDesktop(
                    label: LocaleKeys.sellAsset.tr(),
                    coinAbbr: _filterData.sellCoin,
                    isSellCoin: true,
                    listType: widget.listType,
                    anotherCoinAbbr: widget.filterData?.buyCoin,
                    onCoinSelect: (String? coin) {
                      setState(() {
                        _filterData.sellCoin = coin;
                      });
                      _applyFiltersData();
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 113,
                    maxHeight: _itemHeight,
                  ),
                  child: UiDatePicker(
                    formatter: DateFormat('dd.MM.yyyy').format,
                    date: _filterData.startDate,
                    text: LocaleKeys.fromDate.tr(),
                    endDate: _filterData.endDate,
                    onDateSelect: (time) {
                      setState(() {
                        _filterData.startDate = time;
                      });
                      _applyFiltersData();
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 113,
                    maxHeight: _itemHeight,
                  ),
                  child: UiDatePicker(
                    formatter: DateFormat('dd.MM.yyyy').format,
                    date: _filterData.endDate,
                    text: LocaleKeys.toDate.tr(),
                    startDate: _filterData.startDate,
                    onDateSelect: (time) {
                      setState(() {
                        _filterData.endDate = time;
                      });
                      _applyFiltersData();
                    },
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _itemHeight),
                  child: DexListFilterType<TradeSide>(
                    titile: '${LocaleKeys.taker.tr()}/${LocaleKeys.maker.tr()}',
                    values: [
                      DexListFilterTypeValue<TradeSide>(
                        label: LocaleKeys.taker.tr(),
                        value: TradeSide.taker,
                      ),
                      DexListFilterTypeValue<TradeSide>(
                        label: LocaleKeys.maker.tr(),
                        value: TradeSide.maker,
                      ),
                    ],
                    selectedValues: _filterData.shownSides,
                    onChange: (shownSides) {
                      setState(() {
                        _filterData.shownSides = shownSides;
                      });
                      _applyFiltersData();
                    },
                    label: '${LocaleKeys.taker.tr()}/${LocaleKeys.maker.tr()}',
                    isMobile: false,
                  ),
                ),
                if (widget.listType == DexListType.history)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: _itemHeight),
                    child: DexListFilterType<TradingStatus>(
                      titile: LocaleKeys.status.tr(),
                      values: [
                        DexListFilterTypeValue<TradingStatus>(
                          label: LocaleKeys.successful.tr(),
                          value: TradingStatus.successful,
                        ),
                        DexListFilterTypeValue<TradingStatus>(
                          label: LocaleKeys.failed.tr(),
                          value: TradingStatus.failed,
                        ),
                      ],
                      selectedValues: _filterData.statuses,
                      onChange: (statuses) {
                        setState(() {
                          _filterData.statuses = statuses;
                        });
                        _applyFiltersData();
                      },
                      label: LocaleKeys.status.tr(),
                      isMobile: false,
                    ),
                  ),
              ],
            ),
            OutlinedButton(
              onPressed: () {
                _reset();
                _applyFiltersData();
              },
              child: Text(LocaleKeys.clearFilter.tr()),
            ),
          ],
        ),
      ),
    );
  }

  void _applyFiltersData() => widget.onApplyFilter(_filterData);

  void _reset() => setState(() {
    _filterData = TradingEntitiesFilter();
  });

  void _update() => setState(() {
    _filterData = TradingEntitiesFilter.from(widget.filterData);
  });
}
