import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/best_orders/best_orders.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/views/dex/simple/form/tables/coins_table/coins_table_item.dart';

class GroupedListView<T> extends StatelessWidget {
  const GroupedListView({
    required this.items,
    required this.onSelect,
    required this.maxHeight,
    required this.itemKeyPrefix,
    super.key,
  });

  final List<T> items;
  final void Function(T) onSelect;
  final double maxHeight;

  /// Names the table, for each row's widget key. See [CoinsTableItem].
  final String itemKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    final groupedItems = _groupList(context, items);

    // Add right padding to the last column if there are grouped items
    // to align the grouped and non-grouped
    final areGroupedItemsPresent =
        groupedItems.isNotEmpty &&
        groupedItems.entries
            .where((element) => element.value.length > 1)
            .isNotEmpty;
    final rightPadding = areGroupedItemsPresent
        ? const EdgeInsets.only(right: 52)
        : EdgeInsets.zero;

    return Flexible(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DexScrollbar(
          isMobile: isMobile,
          scrollController: scrollController,
          child: ListView.builder(
            controller: scrollController,
            primary: false,
            shrinkWrap: true,
            itemCount: groupedItems.length,
            itemBuilder: (BuildContext context, int index) {
              final group = groupedItems.entries.elementAt(index);
              return group.value.length > 1
                  ? ExpansionTile(
                      tilePadding: const EdgeInsets.fromLTRB(0, 0, 16, 0),
                      childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                      initiallyExpanded: false,
                      title: CoinsTableItem<T>(
                        itemKeyPrefix: itemKeyPrefix,
                        data: group.value.first,
                        coin: _createHeaderCoinData(context, group.value),
                        onSelect: onSelect,
                        isGroupHeader: true,
                        subtitleText: LocaleKeys.nNetworks.tr(
                          args: [group.value.length.toString()],
                        ),
                        trailing: _GroupedCoinBalance(
                          coins: group.value
                              .map((item) => getCoin(context, item))
                              .toList(),
                        ),
                      ),
                      children: group.value
                          .map((item) => buildItem(context, item, onSelect))
                          .toList(),
                    )
                  : buildItem(
                      context,
                      group.value.first,
                      onSelect,
                      padding: rightPadding,
                    );
            },
          ),
        ),
      ),
    );
  }

  Widget buildItem(
    BuildContext context,
    T item,
    void Function(T) onSelect, {
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return Padding(
      padding: padding,
      child: CoinsTableItem<T>(
        itemKeyPrefix: itemKeyPrefix,
        data: item,
        coin: getCoin(context, item),
        onSelect: onSelect,
      ),
    );
  }

  Coin _createHeaderCoinData(BuildContext context, List<T> list) {
    final firstCoin = getCoin(context, list.first);

    final coin = firstCoin.dummyCopyWithoutProtocolData();
    // Since we can't use 'balance' property directly anymore, we need to
    // construct the coin without using the balance property
    return coin;
  }

  Map<String, List<T>> _groupList(BuildContext context, List<T> list) {
    final Map<String, List<T>> grouped = {};
    for (final item in list) {
      final coin = getCoin(context, item);
      grouped.putIfAbsent(coin.displayName, () => []).add(item);
    }
    return grouped;
  }

  Coin getCoin(BuildContext context, T item) {
    final coinsState = RepositoryProvider.of<CoinsBloc>(context).state;
    if (item is Coin) {
      return item as Coin;
    } else if (item is SelectItem) {
      return (coinsState.walletCoins[item.id] ?? coinsState.coins[item.id])!;
    } else {
      final String coinId = (item as BestOrder).coin;
      return (coinsState.walletCoins[coinId] ?? coinsState.coins[coinId])!;
    }
  }
}

class _GroupedCoinBalance extends StatelessWidget {
  const _GroupedCoinBalance({required this.coins});

  final List<Coin> coins;

  @override
  Widget build(BuildContext context) {
    final baseFont = Theme.of(context).textTheme.bodySmall;
    final balanceStyle = baseFont?.copyWith(fontWeight: FontWeight.w500);

    // Sum on-chain spendable balances for all variants
    double totalSpendable = 0.0;
    for (final coin in coins) {
      totalSpendable +=
          context.sdk.balances.lastKnown(coin.id)?.spendable.toDouble() ?? 0.0;
    }

    // Sum USD balances (uses cached lastKnown data)
    double totalUsd = 0.0;
    for (final coin in coins) {
      totalUsd += coin.lastKnownUsdBalance(context.sdk) ?? 0.0;
    }

    // Show base ticker without protocol/segwit suffixes in group header
    final abbr = abbr2Ticker(coins.first.abbr);

    final children = [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AutoScrollText(
              text: doubleToString(totalSpendable),
              style: balanceStyle,
              textAlign: TextAlign.right,
            ),
          ),
          Text(' $abbr', style: balanceStyle),
        ],
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 100),
        child: Text(
          totalUsd > 0 ? ' (${formatUsdValue(totalUsd)})' : '',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}
