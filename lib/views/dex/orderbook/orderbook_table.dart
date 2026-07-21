import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/orderbook/order.dart';
import 'package:web_dex/model/orderbook/orderbook.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/views/dex/orderbook/orderbook_table_item.dart';
import 'package:web_dex/views/dex/orderbook/orderbook_table_title.dart';

class OrderbookTable extends StatelessWidget {
  const OrderbookTable(
    this.orderbook, {
    Key? key,
    this.myOrder,
    this.selectedOrderUuid,
    this.onAskClick,
    this.onBidClick,
  }) : super(key: key);

  final Orderbook orderbook;
  final Order? myOrder;
  final String? selectedOrderUuid;
  final Function(Order)? onAskClick;
  final Function(Order)? onBidClick;

  @override
  Widget build(BuildContext context) {
    final highestVolume = _getHighestVolume();
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);

    return Container(
      key: const Key('orderbook-asks-bids-container'),
      constraints: const BoxConstraints(maxHeight: 480),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        border: Border.all(color: colors.border),
        borderRadius: geometry.borderRadius16,
      ),
      child: ClipRRect(
        borderRadius: geometry.borderRadius16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(child: _buildAsks(context, highestVolume)),
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.centerLeft,
              color: colors.surfaceHighest,
              child: _buildSpotPrice(context),
            ),
            Flexible(child: _buildBids(context, highestVolume)),
          ],
        ),
      ),
    );
  }

  Widget _buildSpotPrice(BuildContext context) {
    const TextStyle style = TextStyle(fontSize: 11);
    final coinsRepository = RepositoryProvider.of<CoinsRepo>(context);
    final Coin? baseCoin = coinsRepository.getCoin(orderbook.base);
    final Coin? relCoin = coinsRepository.getCoin(orderbook.rel);
    if (baseCoin == null || relCoin == null) return const SizedBox.shrink();

    final double? baseUsdPrice = baseCoin.usdPrice?.price?.toDouble();
    final double? relUsdPrice = relCoin.usdPrice?.price?.toDouble();
    if (baseUsdPrice == null || relUsdPrice == null) {
      return const SizedBox.shrink();
    }
    if (baseUsdPrice == 0 || relUsdPrice == 0) {
      return const SizedBox.shrink();
    }

    final double spotPrice = baseUsdPrice / relUsdPrice;

    return Row(
      children: [
        const SizedBox(width: 10),
        Text(
          formatAmt(spotPrice),
          style: style.copyWith(fontWeight: FontWeight.w500),
        ),
        const Text(' ≈ ', style: style),
        Text('\$$baseUsdPrice', style: style),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 0, 0),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OrderbookTableTitle(
                LocaleKeys.price.tr(),
                suffix: Coin.normalizeAbbr(orderbook.rel),
              ),
              OrderbookTableTitle(
                LocaleKeys.volume.tr(),
                suffix: Coin.normalizeAbbr(orderbook.base),
              ),
            ],
          ),
          const SizedBox(height: 1),
          const UiDivider(),
          const SizedBox(height: 0),
        ],
      ),
    );
  }

  Widget _buildAsks(BuildContext context, Rational highestVolume) {
    final List<Order> asks = List.from(orderbook.asks);
    if (myOrder?.direction == OrderDirection.ask) {
      asks.add(myOrder!);
    }

    asks.sort((a, b) {
      if (a.price > b.price) return 1;
      if (a.price < b.price) return -1;

      if (a.maxVolume > b.maxVolume) return -1;
      if (a.maxVolume < b.maxVolume) return 1;

      return 0;
    });

    if (asks.isEmpty) {
      return Row(
        children: [
          const SizedBox(width: 4),
          Text(
            LocaleKeys.orderBookNoAsks.tr(),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).calmCoreCompatibility.asksColor,
            ),
          ),
        ],
      );
    }
    final scrollController = ScrollController();
    return DexScrollbar(
      isMobile: isMobile,
      scrollController: scrollController,
      child: ListView.builder(
        key: const Key('orderbook-asks-list'),
        controller: scrollController,
        reverse: true,
        primary: false,
        shrinkWrap: true,
        itemCount: asks.length,
        itemBuilder: (context, i) {
          final Order ask = asks[i];
          late double volFraction;
          try {
            volFraction = (ask.maxVolume / highestVolume).toDouble();
          } catch (_) {
            volFraction = 1;
          }

          return OrderbookTableItem(
            ask,
            key: Key('orderbook-ask-item-${ask.uuid ?? 'target'}'),
            volumeFraction: volFraction,
            onClick: onAskClick,
            isSelected: ask.uuid == selectedOrderUuid,
          );
        },
      ),
    );
  }

  Widget _buildBids(BuildContext context, Rational highestVolume) {
    final List<Order> bids = List.from(orderbook.bids);
    if (myOrder?.direction == OrderDirection.bid) {
      bids.add(myOrder!);
    }

    bids.sort((a, b) {
      if (a.price > b.price) return -1;
      if (a.price < b.price) return 1;

      if (a.maxVolume > b.maxVolume) return -1;
      if (a.maxVolume < b.maxVolume) return 1;

      return 0;
    });

    if (bids.isEmpty) {
      return Row(
        children: [
          const SizedBox(width: 4),
          Text(
            LocaleKeys.orderBookNoBids.tr(),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).calmCoreCompatibility.bidsColor,
            ),
          ),
        ],
      );
    }
    final scrollController = ScrollController();
    return DexScrollbar(
      isMobile: isMobile,
      scrollController: scrollController,
      child: ListView.builder(
        key: const Key('orderbook-bids-list'),
        controller: scrollController,
        primary: false,
        shrinkWrap: true,
        itemCount: bids.length,
        itemBuilder: (context, i) {
          final Order bid = bids[i];
          late double volFraction;
          try {
            volFraction = (bid.maxVolume / highestVolume).toDouble();
          } catch (_) {
            volFraction = 1;
          }

          return OrderbookTableItem(
            bid,
            key: Key('orderbook-bid-item-${bid.uuid}'),
            volumeFraction: volFraction,
            onClick: onBidClick,
            isSelected: bid.uuid == selectedOrderUuid,
          );
        },
      ),
    );
  }

  Rational _getHighestVolume() {
    final List<Order> allOrders = [...orderbook.asks, ...orderbook.bids];
    Rational highest = Rational.zero;

    for (Order order in allOrders) {
      if (order.maxVolume > highest) highest = order.maxVolume;
    }

    return highest;
  }
}
