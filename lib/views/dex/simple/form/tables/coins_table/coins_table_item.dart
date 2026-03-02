import 'package:flutter/material.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/shared/widgets/coin_balance.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/views/dex/simple/form/taker/coin_item/item_decoration.dart';

class CoinsTableItem<T> extends StatelessWidget {
  const CoinsTableItem({
    super.key,
    required this.data,
    required this.onSelect,
    required this.coin,
    this.isGroupHeader = false,
    this.subtitleText,
    this.trailing,
  });

  final T? data;
  final Coin coin;
  final Function(T) onSelect;
  final bool isGroupHeader;
  final String? subtitleText;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bool isMobileLayout = isMobile;
    final CoinItemSize itemSize = isMobileLayout
        ? CoinItemSize.medium
        : CoinItemSize.large;
    final double spacerWidth = isMobileLayout ? 6 : 8;
    final BoxConstraints trailingConstraints = BoxConstraints(
      minWidth: isMobileLayout ? 90 : 110,
      maxWidth: isMobileLayout ? 120 : 160,
    );
    final child = ItemDecoration(
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: CoinItem(
              coin: coin,
              size: itemSize,
              subtitleText: subtitleText,
              showNetworkLogo: !isGroupHeader,
            ),
          ),
          SizedBox(width: spacerWidth),
          ConstrainedBox(
            constraints: trailingConstraints,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  trailing ??
                  (coin.isActive
                      ? CoinBalance(coin: coin, isVertical: true)
                      : const SizedBox.shrink()),
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: isGroupHeader
          ? child
          : InkWell(
              key: Key('${T.toString()}-table-item-${coin.abbr}'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelect(data as T),
              child: child,
            ),
    );
  }
}
