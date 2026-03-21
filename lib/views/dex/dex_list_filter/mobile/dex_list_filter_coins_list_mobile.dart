import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/dex_list_type.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

class DexListFilterCoinsList extends StatefulWidget {
  const DexListFilterCoinsList({
    required this.isSellCoin,
    required this.anotherCoin,
    required this.onCoinSelect,
    required this.listType,
    super.key,
  });
  final DexListType listType;
  final bool isSellCoin;
  final String? anotherCoin;
  final void Function(String?) onCoinSelect;

  @override
  State<DexListFilterCoinsList> createState() => _DexListFilterCoinsListState();
}

class _DexListFilterCoinsListState extends State<DexListFilterCoinsList> {
  String _searchPhrase = '';
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          UiTextFormField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            hintText: LocaleKeys.searchAssets.tr(),
            autofocus: true,
            onChanged: (String? searchPhrase) {
              setState(() {
                _searchPhrase = searchPhrase ?? '';
              });
            },
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: widget.listType == DexListType.orders
                  ? _buildOrderCoinList()
                  : _buildSwapCoinList(),
            ),
          ),
          UiUnderlineTextButton(
            height: 62,
            text: LocaleKeys.cancel.tr(),
            onPressed: () => widget.onCoinSelect(null),
          ),
        ],
      ),
    );
  }

  Widget _buildSwapCoinList() {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return StreamBuilder<List<Swap>>(
      stream: tradingEntitiesBloc.outSwaps,
      initialData: tradingEntitiesBloc.swaps,
      builder: (context, snapshot) {
        final list = snapshot.data ?? [];
        final filtered = widget.listType == DexListType.history
            ? list.where((s) => s.isCompleted).toList()
            : list.where((s) => !s.isCompleted).toList();
        final Map<String, List<String>> coinAbbrMap =
            getCoinAbbrMapFromSwapList(filtered, widget.isSellCoin);

        return _buildCoinList(coinAbbrMap);
      },
    );
  }

  Widget _buildOrderCoinList() {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return StreamBuilder<List<MyOrder>>(
      stream: tradingEntitiesBloc.outMyOrders,
      initialData: tradingEntitiesBloc.myOrders,
      builder: (context, snapshot) {
        final list = snapshot.data ?? [];
        final Map<String, List<String>> coinAbbrMap =
            getCoinAbbrMapFromOrderList(list, widget.isSellCoin);

        return _buildCoinList(coinAbbrMap);
      },
    );
  }

  Widget _buildCoinList(Map<String, List<String>> coinAbbrMap) {
    final List<String> coinAbbrList =
        (_searchPhrase.isEmpty
                ? coinAbbrMap.keys.toList()
                : coinAbbrMap.keys.where(
                    (String coinAbbr) =>
                        coinAbbr.toLowerCase().contains(_searchPhrase),
                  ))
            .where((abbr) => abbr != widget.anotherCoin)
            .toList();

    final int lastIndex = coinAbbrList.length - 1;

    final scrollController = ScrollController();
    return DexScrollbar(
      isMobile: isMobile,
      scrollController: scrollController,
      child: ListView.builder(
        controller: scrollController,
        shrinkWrap: true,
        itemCount: coinAbbrList.length,
        itemBuilder: (BuildContext context, int i) {
          final coinAbbr = coinAbbrList[i];
          final String? anotherCoinAbbr = widget.anotherCoin;
          final coinPairsCount = getCoinPairsCountFromCoinAbbrMap(
            coinAbbrMap,
            coinAbbr,
            anotherCoinAbbr,
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              5.0,
              18,
              lastIndex == i ? 20.0 : 0.0,
            ),
            child: _buildCoinListItem(coinAbbr, coinPairsCount),
          );
        },
      ),
    );
  }

  Widget _buildCoinListItem(String coinAbbr, int pairCount) {
    final bool isSegwit = Coin.checkSegwitByAbbr(coinAbbr);
    return Material(
      borderRadius: BorderRadius.circular(15),
      color: Theme.of(context).cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => widget.onCoinSelect(coinAbbr),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
          child: Row(
            children: [
              AssetIcon.ofTicker(coinAbbr),
              Padding(
                padding: const EdgeInsets.only(left: 5.0),
                child: Text(
                  '${Coin.normalizeAbbr(coinAbbr)} ${isSegwit ? ' (segwit)' : ''}',
                ),
              ),
              const Spacer(),
              Text('($pairCount)'),
            ],
          ),
        ),
      ),
    );
  }
}
