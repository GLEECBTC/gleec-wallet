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
    required this.itemKeyPrefix,
    this.isGroupHeader = false,
    this.subtitleText,
    this.trailing,
  });

  final T? data;
  final Coin coin;
  final Function(T) onSelect;

  /// Names the table this row belongs to, for the row's widget key.
  ///
  /// Spelled out by the caller rather than taken from `T.toString()`: dart2js
  /// minifies type names in a release build, so the type answered
  /// `minified:c9` there and `Coin` everywhere else. The key silently changed
  /// shape between build modes, which is why the DEX coin row was unreachable
  /// in the release web build while every other mode found it.
  final String itemKeyPrefix;

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
              key: Key('$itemKeyPrefix-table-item-${coin.abbr}'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelect(data as T),
              child: child,
            ),
    );
  }
}
