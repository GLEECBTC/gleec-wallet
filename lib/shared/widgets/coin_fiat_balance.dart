import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';

class CoinFiatBalance extends StatefulWidget {
  const CoinFiatBalance(
    this.coin, {
    super.key,
    this.style,
    this.isSelectable = false,
    this.isAutoScrollEnabled = false,
  });

  final Coin coin;
  final TextStyle? style;
  final bool isSelectable;
  final bool isAutoScrollEnabled;

  @override
  State<CoinFiatBalance> createState() => _CoinFiatBalanceState();
}

class _CoinFiatBalanceState extends State<CoinFiatBalance> {
  /// Held for the widget's lifetime - see [CoinBalance] for why creating this
  /// in [build] restarts the SDK balance watcher on every rebuild.
  late Stream<BalanceInfo> _balanceStream;

  @override
  void initState() {
    super.initState();
    _balanceStream = context.sdk.balances.watchBalance(widget.coin.id);
  }

  @override
  void didUpdateWidget(covariant CoinFiatBalance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coin.id != widget.coin.id) {
      _balanceStream = context.sdk.balances.watchBalance(widget.coin.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coin = widget.coin;
    final style = widget.style;
    final isSelectable = widget.isSelectable;
    final isAutoScrollEnabled = widget.isAutoScrollEnabled;
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );

    final TextStyle mergedStyle = const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ).merge(style);

    if (hideBalances) {
      final balanceStr = ' ($maskedBalanceText)';
      return isAutoScrollEnabled
          ? AutoScrollText(
              text: balanceStr,
              style: mergedStyle,
              isSelectable: isSelectable,
            )
          : isSelectable
          ? SelectableText(balanceStr, style: mergedStyle)
          : Text(balanceStr, style: mergedStyle);
    }

    return BlocSelector<CoinsBloc, CoinsState, double?>(
      selector: (state) => state.getPriceForAsset(coin.id)?.price?.toDouble(),
      builder: (context, price) {
        return StreamBuilder<BalanceInfo>(
          stream: _balanceStream,
          builder: (context, snapshot) {
            final balance = snapshot.data?.spendable.toDouble();
            if (balance == null || price == null) {
              final balanceStr = ' ($kBalancePlaceholder)';
              return isAutoScrollEnabled
                  ? AutoScrollText(
                      text: balanceStr,
                      style: mergedStyle,
                      isSelectable: isSelectable,
                    )
                  : isSelectable
                  ? SelectableText(balanceStr, style: mergedStyle)
                  : Text(balanceStr, style: mergedStyle);
            }

            final formattedBalance = formatUsdValue(price * balance);
            final balanceStr = ' ($formattedBalance)';

            if (isAutoScrollEnabled) {
              return AutoScrollText(
                text: balanceStr,
                style: mergedStyle,
                isSelectable: isSelectable,
              );
            }

            return isSelectable
                ? SelectableText(balanceStr, style: mergedStyle)
                : Text(balanceStr, style: mergedStyle);
          },
        );
      },
    );
  }
}
