import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/forms/coin_select_input.dart';
import 'package:web_dex/model/forms/coin_trade_amount_input.dart';
import 'package:web_dex/views/market_maker_bot/coin_selection_and_amount_input.dart';
import 'package:web_dex/views/market_maker_bot/coin_trade_amount_label.dart' show CoinTradeAmountLabel;
import 'package:web_dex/views/market_maker_bot/market_maker_form_error_message_extensions.dart';
import 'package:web_dex/shared/utils/utils.dart';

class BuyCoinSelectDropdown extends StatelessWidget {
  const BuyCoinSelectDropdown({
    required this.buyCoin,
    required this.buyAmount,
    required this.coins,
    this.onItemSelected,
    super.key,
  });
  final CoinSelectInput buyCoin;
  final CoinTradeAmountInput buyAmount;
  final List<Coin> coins;
  final Function(Coin?)? onItemSelected;

  @override
  Widget build(BuildContext context) {
    return CoinSelectionAndAmountInput(
      coins: coins,
      refine: (list) {
        // Order: active with balance (top), active without balance (middle), inactive (bottom)
        final sdk = context.sdk;
        int rank(Coin c) {
          final hasBalance = (c.lastKnownUsdBalance(sdk) ?? 0) > 0;
          if (c.isActive && hasBalance) return 0;
          if (c.isActive) return 1;
          return 2;
        }
        final sorted = List<Coin>.from(list);
        sorted.sort((a, b) {
          final ra = rank(a);
          final rb = rank(b);
          if (ra != rb) return ra - rb;
          // Within rank, keep existing priority/balance sorting from upstream by
          // comparing their current position heuristically via usd balance desc then abbr
          final ba = a.lastKnownUsdBalance(sdk) ?? 0.0;
          final bb = b.lastKnownUsdBalance(sdk) ?? 0.0;
          if (ba != bb) return bb.compareTo(ba);
          return a.abbr.compareTo(b.abbr);
        });
        return sorted;
      },
      title: LocaleKeys.buy.tr(),
      selectedCoin: buyCoin.value,
      onItemSelected: onItemSelected,
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CoinTradeAmountLabel(
            coin: buyCoin.value,
            value: buyAmount.valueAsRational,
            errorText: buyCoin.displayError?.text(buyCoin.value),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Text(
              '* ${LocaleKeys.mmBotFirstTradeEstimate.tr()}',
              style: TextStyle(
                color: dexPageColors.inactiveText,
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
