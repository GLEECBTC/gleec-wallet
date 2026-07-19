import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

class DexListFilterCoinDesktop extends StatelessWidget {
  const DexListFilterCoinDesktop({
    Key? key,
    required this.label,
    required this.coinAbbr,
    required this.anotherCoinAbbr,
    required this.isSellCoin,
    required this.listType,
    required this.onCoinSelect,
  }) : super(key: key);
  final String label;
  final String? coinAbbr;
  final String? anotherCoinAbbr;
  final bool isSellCoin;
  final DexListType listType;
  final void Function(String?) onCoinSelect;

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    switch (listType) {
      case DexListType.orders:
        return StreamBuilder<List<MyOrder>>(
          stream: tradingEntitiesBloc.outMyOrders,
          initialData: tradingEntitiesBloc.myOrders,
          builder: (context, snapshot) {
            final list = snapshot.data ?? [];
            final Map<String, List<String>> coinAbbrMap =
                getCoinAbbrMapFromOrderList(list, isSellCoin);

            return _DropDownButton(
              label: label,
              onCoinSelect: onCoinSelect,
              value: coinAbbr,
              items: _getItems(context, coinAbbrMap),
              selectedItemBuilder: (context) =>
                  _getItems(context, coinAbbrMap, selected: true),
            );
          },
        );
      case DexListType.inProgress:
      case DexListType.history:
        return StreamBuilder<List<Swap>>(
          stream: tradingEntitiesBloc.outSwaps,
          initialData: tradingEntitiesBloc.swaps,
          builder: (context, snapshot) {
            final list = snapshot.data ?? [];
            final filtered = listType == DexListType.history
                ? list.where((s) => s.isCompleted).toList()
                : list.where((s) => !s.isCompleted).toList();
            final Map<String, List<String>> coinAbbrMap =
                getCoinAbbrMapFromSwapList(filtered, isSellCoin);

            return _DropDownButton(
              label: label,
              onCoinSelect: onCoinSelect,
              value: coinAbbr,
              items: _getItems(context, coinAbbrMap),
              selectedItemBuilder: (context) =>
                  _getItems(context, coinAbbrMap, selected: true),
            );
          },
        );
      case DexListType.swap:
        return const SizedBox();
    }
  }

  List<DropdownMenuItem<String>> _getItems(
    BuildContext context,
    Map<String, List<String>> coinAbbrMap, {
    bool selected = false,
  }) {
    final Iterable<String> coinAbbrList = coinAbbrMap.keys.where(
      (abbr) => abbr != anotherCoinAbbr,
    );

    return selected
        ? coinAbbrList.map((abbr) {
            return _buildSelectedItem(context, abbr);
          }).toList()
        : coinAbbrList.map((abbr) {
            final int pairsCount = getCoinPairsCountFromCoinAbbrMap(
              coinAbbrMap,
              abbr,
              anotherCoinAbbr,
            );
            return _buildItem(context, abbr, pairsCount);
          }).toList();
  }

  DropdownMenuItem<String> _buildItem(
    BuildContext context,
    String coinAbbr,
    int pairsCount,
  ) {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final Coin? coin = coinsRepository.getCoin(coinAbbr);
    if (coin == null) return const DropdownMenuItem<String>(child: SizedBox());

    return DropdownMenuItem<String>(
      value: coinAbbr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.max,
        children: [
          Flexible(
            child: CoinItem(coin: coin, size: CoinItemSize.small),
          ),
          const SizedBox(width: 4),
          Text(
            '($pairsCount)',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyMedium?.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<String> _buildSelectedItem(
    BuildContext context,
    String coinAbbr,
  ) {
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final Coin? coin = coinsRepository.getCoin(coinAbbr);
    if (coin == null) return const DropdownMenuItem<String>(child: SizedBox());

    return DropdownMenuItem<String>(
      value: coinAbbr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
        child: CoinItem(coin: coin, size: CoinItemSize.small),
      ),
    );
  }

  String get innerText {
    return coinAbbr ?? label;
  }
}

class _DropDownButton extends StatelessWidget {
  const _DropDownButton({
    required this.label,
    required this.onCoinSelect,
    required this.value,
    required this.items,
    required this.selectedItemBuilder,
  });

  final String label;
  final void Function(String? p1) onCoinSelect;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final List<Widget> Function(BuildContext)? selectedItemBuilder;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context),
      child: Builder(
        builder: (context) {
          final ext = Theme.of(context).extension<ColorSchemeExtension>();
          return Container(
            padding: value != null && value!.isNotEmpty
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: value != null && value!.isNotEmpty
                  ? ext?.primary
                  : ext?.surfCont,
              borderRadius: BorderRadius.circular(15),
            ),
            constraints: const BoxConstraints(maxHeight: 50),
            child: DropdownButton<String>(
              hint: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: value != null && value!.isNotEmpty
                      ? ext?.surf
                      : ext?.s70,
                ),
              ),
              iconSize: 12,
              value: value,
              items: items,
              onChanged: onCoinSelect,
              focusColor: Colors.transparent,
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: value != null && value!.isNotEmpty
                    ? ext?.surf
                    : ext?.s70,
              ),
              underline: const SizedBox(),
              isExpanded: true,
              selectedItemBuilder: selectedItemBuilder,
            ),
          );
        },
      ),
    );
  }
}
