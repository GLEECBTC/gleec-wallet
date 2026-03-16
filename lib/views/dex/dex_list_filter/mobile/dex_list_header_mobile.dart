import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/trading_entities_filter.dart';

class DexListHeaderMobile extends StatelessWidget {
  const DexListHeaderMobile({
    super.key,
    required this.listType,
    required this.entitiesFilterData,
    required this.onFilterPressed,
    required this.onFilterDataChange,
    required this.isFilterShown,
    this.centerWidget,
    this.onCancelAll,
  });
  final DexListType listType;
  final TradingEntitiesFilter? entitiesFilterData;
  final bool isFilterShown;
  final VoidCallback onFilterPressed;
  final void Function(TradingEntitiesFilter?) onFilterDataChange;
  final Widget? centerWidget;
  final VoidCallback? onCancelAll;

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    final List<Widget> filterElements = _getFilterElements(context);
    final filterData = entitiesFilterData;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildFilterButton(context),
            if (centerWidget != null) ...[
              const SizedBox(width: 8),
              Expanded(child: centerWidget!),
              const SizedBox(width: 8),
            ],
            if (listType == DexListType.orders)
              PopupMenuButton<_DexListHeaderAction>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (action) {
                  switch (action) {
                    case _DexListHeaderAction.cancelAll:
                      (onCancelAll ??
                          () => tradingEntitiesBloc.cancelAllOrders())();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _DexListHeaderAction.cancelAll,
                    child: Text(
                      LocaleKeys.cancelAll.tr(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (filterData != null)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: SingleChildScrollView(
              controller: ScrollController(),
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: filterElements,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _getFilterElements(BuildContext context) {
    final filterData = entitiesFilterData;

    final String? sellCoin = filterData?.sellCoin;
    final String? buyCoin = filterData?.buyCoin;

    final DateTime? startDate = filterData?.startDate;
    final DateTime? endDate = filterData?.endDate;
    final String? startDateString = startDate != null
        ? DateFormat('dd.MM.yyyy').format(startDate)
        : null;
    final String? endDateString = endDate != null
        ? DateFormat('dd.MM.yyyy').format(endDate)
        : null;

    final List<TradingStatus>? statuses = filterData?.statuses;
    final List<TradeSide>? shownSides = filterData?.shownSides;

    List<Widget> children = [];

    if (buyCoin != null) {
      children.add(
        _buildManageFilterItem(
          LocaleKeys.buy.tr(),
          buyCoin,
          () => onFilterDataChange(
            TradingEntitiesFilter(
              buyCoin: null,
              sellCoin: sellCoin,
              startDate: startDate,
              endDate: endDate,
              statuses: statuses,
              shownSides: shownSides,
            ),
          ),
          context,
        ),
      );
    }
    if (sellCoin != null) {
      children.add(
        _buildManageFilterItem(
          LocaleKeys.sell.tr(),
          sellCoin,
          () => onFilterDataChange(
            TradingEntitiesFilter(
              buyCoin: buyCoin,
              sellCoin: null,
              startDate: startDate,
              endDate: endDate,
              statuses: statuses,
              shownSides: shownSides,
            ),
          ),
          context,
        ),
      );
    }
    if (statuses != null) {
      children.addAll(
        statuses.map(
          (s) => _buildManageFilterItem(
            LocaleKeys.status.tr(),
            s == TradingStatus.successful
                ? LocaleKeys.successful.tr()
                : LocaleKeys.failed.tr(),
            () => onFilterDataChange(
              TradingEntitiesFilter(
                buyCoin: buyCoin,
                sellCoin: sellCoin,
                startDate: startDate,
                endDate: endDate,
                statuses: statuses.where((e) => e != s).toList(),
                shownSides: shownSides,
              ),
            ),
            context,
          ),
        ),
      );
    }
    if (shownSides != null) {
      children.addAll(
        shownSides.map(
          (s) => _buildManageFilterItem(
            LocaleKeys.type.tr(),
            s == TradeSide.taker
                ? LocaleKeys.taker.tr()
                : LocaleKeys.maker.tr(),
            () => onFilterDataChange(
              TradingEntitiesFilter(
                buyCoin: buyCoin,
                sellCoin: sellCoin,
                startDate: startDate,
                endDate: endDate,
                statuses: statuses,
                shownSides: filterData?.shownSides
                    ?.where((e) => e != s)
                    .toList(),
              ),
            ),
            context,
          ),
        ),
      );
    }
    if (startDateString != null) {
      children.add(
        _buildManageFilterItem(
          LocaleKeys.fromDate.tr(),
          startDateString,
          () => onFilterDataChange(
            TradingEntitiesFilter(
              buyCoin: buyCoin,
              sellCoin: sellCoin,
              startDate: null,
              endDate: endDate,
              statuses: statuses,
              shownSides: shownSides,
            ),
          ),
          context,
        ),
      );
    }
    if (endDateString != null) {
      children.add(
        _buildManageFilterItem(
          LocaleKeys.toDate.tr(),
          endDateString,
          () => onFilterDataChange(
            TradingEntitiesFilter(
              buyCoin: buyCoin,
              sellCoin: sellCoin,
              startDate: startDate,
              endDate: null,
              statuses: statuses,
              shownSides: shownSides,
            ),
          ),
          context,
        ),
      );
    }

    if (children.length > 1) {
      children = [_buildResetAllButton(context), ...children];
    }

    return children;
  }

  Widget _buildFilterButton(BuildContext context) {
    return InkWell(
      radius: 18,
      borderRadius: BorderRadius.circular(18),
      onTap: onFilterPressed,
      child: Container(
        width: 100,
        height: 30,
        decoration: BoxDecoration(
          border: Border.all(color: theme.custom.specificButtonBorderColor),
          color: theme.custom.specificButtonBackgroundColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              isFilterShown
                  ? Icon(
                      Icons.close,
                      color: Theme.of(context).textTheme.labelLarge?.color,
                      size: 14,
                    )
                  : SvgPicture.asset(
                      '$assetsPath/ui_icons/filters.svg',
                      colorFilter: ColorFilter.mode(
                        Theme.of(context).textTheme.labelLarge?.color ??
                            Colors.white,
                        BlendMode.srcIn,
                      ),
                      width: 14,
                    ),
              Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: Text(
                  isFilterShown
                      ? LocaleKeys.close.tr()
                      : LocaleKeys.filters.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManageFilterItem(
    String text,
    String value,
    VoidCallback removeFilter,
    BuildContext context,
  ) {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: removeFilter,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: theme.custom.specificButtonBackgroundColor,
              border: Border.all(color: const Color.fromRGBO(237, 237, 237, 1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$text: $value',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6.0),
                  child: Icon(
                    Icons.close,
                    color: Theme.of(context).textTheme.labelLarge?.color,
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetAllButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => onFilterDataChange(null),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).colorScheme.primary,
          ),
          child: Text(
            LocaleKeys.resetAll.tr(),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

enum _DexListHeaderAction { cancelAll }
