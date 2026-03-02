import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rational/rational.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/focusable_widget.dart';
import 'package:web_dex/views/dex/entities_list/common/buy_price_mobile.dart';
import 'package:web_dex/views/dex/entities_list/common/coin_amount_mobile.dart';
import 'package:web_dex/views/dex/entities_list/common/count_down_timer.dart';
import 'package:web_dex/views/dex/entities_list/common/trade_amount_desktop.dart';

class OrderItem extends StatefulWidget {
  const OrderItem(this.order, {super.key, this.actions = const []});

  final MyOrder order;
  final List<Widget> actions;

  @override
  State<OrderItem> createState() => _OrderItemState();
}

class _OrderItemState extends State<OrderItem> {
  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final String sellCoin = order.base;
    final Rational sellAmount = order.baseAmount;
    final String buyCoin = order.rel;
    final Rational buyAmount = order.relAmount;
    final bool isTaker = order.orderType == TradeSide.taker;
    final String date = getFormattedDate(order.createdAt);
    final int orderMatchingTime = order.orderMatchingTime;
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    final double fillProgress = tradingEntitiesBloc.getProgressFillSwap(order);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile)
          Text(
            tradingEntitiesBloc.getTypeString(isTaker),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _protocolColor,
            ),
          ),
        FocusableWidget(
          onTap: () {
            routingState.dexState.setDetailsAction(order.uuid);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.onSurface,
            ),
            child: isMobile
                ? _OrderItemMobile(
                    uuid: order.uuid,
                    buyAmount: buyAmount,
                    buyCoin: buyCoin,
                    sellCoin: sellCoin,
                    sellAmount: sellAmount,
                    date: date,
                    isTaker: isTaker,
                    fillProgress: fillProgress,
                    orderMatchingTime: orderMatchingTime,
                    actions: widget.actions,
                  )
                : _OrderItemDesktop(
                    buyAmount: buyAmount,
                    buyCoin: buyCoin,
                    sellCoin: sellCoin,
                    sellAmount: sellAmount,
                    date: date,
                    isTaker: isTaker,
                    fillProgress: fillProgress,
                    orderMatchingTime: orderMatchingTime,
                    actions: widget.actions,
                  ),
          ),
        ),
      ],
    );
  }

  Color get _protocolColor => widget.order.orderType == TradeSide.taker
      ? const Color.fromRGBO(47, 179, 239, 1)
      : const Color.fromRGBO(106, 77, 227, 1);
}

class _OrderItemDesktop extends StatelessWidget {
  const _OrderItemDesktop({
    required this.buyCoin,
    required this.buyAmount,
    required this.sellCoin,
    required this.sellAmount,
    required this.date,
    required this.fillProgress,
    required this.isTaker,
    required this.orderMatchingTime,
    this.actions = const [],
  });
  final String buyCoin;
  final Rational buyAmount;
  final String sellCoin;
  final Rational sellAmount;
  final String date;
  final double fillProgress;
  final bool isTaker;
  final int orderMatchingTime;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: TradeAmountDesktop(coinAbbr: sellCoin, amount: sellAmount),
        ),
        Expanded(
          child: TradeAmountDesktop(coinAbbr: buyCoin, amount: buyAmount),
        ),
        Expanded(
          child: Text(
            formatAmt(
              tradingEntitiesBloc.getPriceFromAmount(sellAmount, buyAmount),
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: Text(
            date,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          flex: 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tradingEntitiesBloc.getTypeString(isTaker),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isTaker
                      ? const Color.fromRGBO(47, 179, 239, 1)
                      : const Color.fromRGBO(106, 77, 227, 1),
                ),
              ),
              if (isTaker)
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: CountDownTimer(orderMatchingTime: orderMatchingTime),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 4.0),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CustomPaint(
                      painter: _FillPainter(
                        context: context,
                        fillProgress: fillProgress,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6.0),
          child: actions.isNotEmpty
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [...actions],
                )
              : const SizedBox(width: 80),
        ),
      ],
    );
  }
}

class _FillPainter extends CustomPainter {
  _FillPainter({required this.context, required this.fillProgress});

  final BuildContext context;
  final double fillProgress;

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final theme = Theme.of(context);

    final Paint paint = Paint()
      ..color = Theme.of(context).highlightColor
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    final Offset center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width / 2, paint);

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color =
          theme.progressIndicatorTheme.color ?? theme.colorScheme.secondary
      ..strokeWidth = size.width * 1.1 / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: size.width / 4),
      vector_math.radians(0),
      vector_math.radians(fillProgress * 360),
      false,
      fillPaint,
    );
  }
}

class _OrderItemMobile extends StatelessWidget {
  const _OrderItemMobile({
    required this.uuid,
    required this.buyCoin,
    required this.buyAmount,
    required this.sellCoin,
    required this.sellAmount,
    required this.date,
    required this.fillProgress,
    required this.isTaker,
    required this.orderMatchingTime,
    this.actions = const [],
  });

  final String uuid;
  final String buyCoin;
  final Rational buyAmount;
  final String sellCoin;
  final Rational sellAmount;
  final String date;
  final double fillProgress;
  final bool isTaker;
  final int orderMatchingTime;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleKeys.send.tr(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: CoinAmountMobile(
                      coinAbbr: sellCoin,
                      amount: sellAmount,
                    ),
                  ),
                ],
              ),
            ),
            if (isTaker)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color.fromRGBO(255, 255, 255, 1),
                ),
                child: CountDownTimer(orderMatchingTime: orderMatchingTime),
              )
            else
              BuyPriceMobile(
                buyCoin: buyCoin,
                sellAmount: sellAmount,
                buyAmount: buyAmount,
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocaleKeys.receive.tr(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 5.0),
                      child: CoinAmountMobile(
                        coinAbbr: buyCoin,
                        amount: buyAmount,
                      ),
                    ),
                  ],
                ),
              ),
              ...actions,
              const SizedBox(width: 4),
              _OrderActionsMenu(uuid: uuid),
            ],
          ),
        ),
        if (!isTaker)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CustomPaint(
                    painter: _FillPainter(
                      context: context,
                      fillProgress: fillProgress,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10.0),
                  child: Text(
                    LocaleKeys.percentFilled.tr(
                      args: [(fillProgress * 100).toStringAsFixed(0)],
                    ),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OrderActionsMenu extends StatelessWidget {
  const _OrderActionsMenu({required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_OrderAction>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (action) {
        switch (action) {
          case _OrderAction.copyUuid:
            copyToClipBoard(
              context,
              uuid,
              LocaleKeys.copiedUuidToClipboard.tr(),
            );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _OrderAction.copyUuid,
          child: Text(LocaleKeys.copyUuid.tr()),
        ),
      ],
    );
  }
}

enum _OrderAction { copyUuid }
