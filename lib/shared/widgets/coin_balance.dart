import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/coin_fiat_balance.dart';

// TODO! Integrate this widget directly to the SDK and make it subscribe to
// the balance changes of the coin.
class CoinBalance extends StatelessWidget {
  const CoinBalance({super.key, required this.coin, this.isVertical = false});

  final Coin coin;
  final bool isVertical;

  @override
  Widget build(BuildContext context) {
    final baseFont = Theme.of(context).textTheme.bodySmall;
    final balanceStyle = baseFont?.copyWith(fontWeight: FontWeight.w500);

    final balance = coin.balance(context.sdk) ?? 0.0;

    final children = [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AutoScrollText(
              key: Key('coin-balance-asset-${coin.abbr.toLowerCase()}'),
              text: doubleToString(balance),
              style: balanceStyle,
              textAlign: TextAlign.right,
            ),
          ),
          Text(' ${Coin.normalizeAbbr(coin.abbr)}', style: balanceStyle),
        ],
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 100),
        child: CoinFiatBalance(coin, isAutoScrollEnabled: true),
      ),
    ];

    return isVertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: children,
          );
  }
}
