import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/blocs/trading_entities_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/swap.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/focusable_widget.dart';
import 'package:web_dex/views/dex/entities_list/common/buy_price_mobile.dart';
import 'package:web_dex/views/dex/entities_list/common/coin_amount_mobile.dart';
import 'package:web_dex/views/dex/entities_list/common/entity_item_status_wrapper.dart';
import 'package:web_dex/views/dex/entities_list/common/swap_actions_menu.dart';
import 'package:web_dex/views/dex/entities_list/common/trade_amount_desktop.dart';

class InProgressItem extends StatelessWidget {
  const InProgressItem(this.swap, {Key? key, required this.onClick})
    : super(key: key);
  final Swap swap;
  final VoidCallback onClick;

  @override
  Widget build(BuildContext context) {
    final String sellCoin = swap.sellCoin;
    final Rational sellAmount = swap.sellAmount;
    final String buyCoin = swap.buyCoin;
    final Rational buyAmount = swap.buyAmount;
    final String date = swap.myInfo != null
        ? getFormattedDate(swap.myInfo!.startedAt)
        : '-';
    final bool isTaker = swap.isTaker;
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    final String typeText = tradingEntitiesBloc.getTypeString(isTaker);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isMobile)
          Text(
            typeText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _protocolColor,
            ),
          ),
        FocusableWidget(
          borderRadius: BorderRadius.circular(10),
          onTap: onClick,
          child: Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.onSurface,
            ),
            child: isMobile
                ? _InProgressItemMobile(
                    swap: swap,
                    buyAmount: buyAmount,
                    buyCoin: buyCoin,
                    date: date,
                    sellAmount: sellAmount,
                    sellCoin: sellCoin,
                    status: swap.status,
                    statusStep: swap.statusStep,
                  )
                : _InProgressItemDesktop(
                    buyAmount: buyAmount,
                    buyCoin: buyCoin,
                    date: date,
                    protocolColor: _protocolColor,
                    sellAmount: sellAmount,
                    sellCoin: sellCoin,
                    status: swap.status,
                    statusStep: swap.statusStep,
                    typeText: typeText,
                  ),
          ),
        ),
      ],
    );
  }

  Color get _protocolColor => swap.isTaker
      ? const Color.fromRGBO(47, 179, 239, 1)
      : const Color.fromRGBO(106, 77, 227, 1);
}

class _InProgressItemDesktop extends StatelessWidget {
  const _InProgressItemDesktop({
    Key? key,
    required this.sellCoin,
    required this.sellAmount,
    required this.buyCoin,
    required this.buyAmount,
    required this.status,
    required this.statusStep,
    required this.date,
    required this.typeText,
    required this.protocolColor,
  }) : super(key: key);
  final String sellCoin;
  final Rational sellAmount;
  final String buyCoin;
  final Rational buyAmount;
  final SwapStatus status;
  final int statusStep;
  final String date;
  final String typeText;
  final Color protocolColor;

  @override
  Widget build(BuildContext context) {
    final tradingEntitiesBloc = RepositoryProvider.of<TradingEntitiesBloc>(
      context,
    );
    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: EntityItemStatusWrapper(
                  textColor: null,
                  text:
                      '${Swap.getSwapStatusString(status)} $statusStep/${Swap.statusSteps}',
                  width: 110,
                  icon: SvgPicture.asset(
                    '$assetsPath/others/swap.svg',
                    width: 12,
                    height: 12,
                    colorFilter: ColorFilter.mode(
                      Theme.of(context).colorScheme.secondary,
                      BlendMode.srcIn,
                    ),
                  ),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TradeAmountDesktop(coinAbbr: sellCoin, amount: sellAmount),
        ),
        Expanded(
          child: TradeAmountDesktop(coinAbbr: buyCoin, amount: buyAmount),
        ),
        Expanded(
          child: Text(
            formatDexAmt(
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
          child: Text(
            typeText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: protocolColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _InProgressItemMobile extends StatelessWidget {
  const _InProgressItemMobile({
    Key? key,
    required this.swap,
    required this.sellCoin,
    required this.sellAmount,
    required this.buyCoin,
    required this.buyAmount,
    required this.status,
    required this.statusStep,
    required this.date,
  }) : super(key: key);
  final Swap swap;
  final String sellCoin;
  final Rational sellAmount;
  final String buyCoin;
  final Rational buyAmount;
  final SwapStatus status;
  final int statusStep;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BuyPriceMobile(
                  buyCoin: buyCoin,
                  buyAmount: buyAmount,
                  sellAmount: sellAmount,
                ),
                const SizedBox(width: 4),
                SwapActionsMenu(swap: swap),
              ],
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            LocaleKeys.receive.tr(),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: CoinAmountMobile(coinAbbr: buyCoin, amount: buyAmount),
              ),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: Theme.of(context).colorScheme.onSurface,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                '$assetsPath/others/swap.svg',
                width: 12,
                height: 12,
                colorFilter: ColorFilter.mode(
                  Theme.of(context).colorScheme.secondary,
                  BlendMode.srcIn,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Text(
                  '${Swap.getSwapStatusString(status)} $statusStep/${Swap.statusSteps}',
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
