import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/trading_entities_filter.dart';
import 'package:web_dex/views/dex/common/dex_confirmation_dialog.dart';

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
                onSelected: (action) async {
                  switch (action) {
                    case _DexListHeaderAction.cancelAll:
                      final confirmed = await showDexActionConfirmation(
                        context: context,
                        actionLabel: LocaleKeys.cancelAll.tr(),
                        confirmButtonKey: const Key(
                          'dex-mobile-cancel-all-confirm',
                        ),
                      );
                      if (!confirmed || !context.mounted) return;
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
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    return SizedBox(
      width: 120,
      child: OutlinedButton.icon(
        onPressed: onFilterPressed,
        icon: isFilterShown
            ? const Icon(Icons.close, size: 18)
            : SvgPicture.asset(
                '$assetsPath/ui_icons/filters.svg',
                colorFilter: ColorFilter.mode(
                  colors.textSecondary,
                  BlendMode.srcIn,
                ),
                width: 18,
              ),
        label: Text(
          isFilterShown ? LocaleKeys.close.tr() : LocaleKeys.filters.tr(),
          maxLines: 2,
          textAlign: TextAlign.center,
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: Size(120, geometry.minimumTapTarget),
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
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    final typography = GleecTypography.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, minHeight: 48),
        child: Material(
          color: colors.surfaceHigh,
          borderRadius: geometry.borderRadius16,
          child: InkWell(
            onTap: removeFilter,
            borderRadius: geometry.borderRadius16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: geometry.borderRadius16,
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '$text: $value',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: typography.bodyMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 6.0),
                    child: Icon(
                      Icons.close,
                      color: colors.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResetAllButton(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ElevatedButton(
        onPressed: () => onFilterDataChange(null),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.brand,
          minimumSize: Size(96, geometry.minimumTapTarget),
        ),
        child: Text(LocaleKeys.resetAll.tr()),
      ),
    );
  }
}

enum _DexListHeaderAction { cancelAll }
