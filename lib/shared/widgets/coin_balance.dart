import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/coin_fiat_balance.dart';

// TODO! Integrate this widget directly to the SDK and make it subscribe to
// the balance changes of the coin.
class CoinBalance extends StatefulWidget {
  const CoinBalance({super.key, required this.coin, this.isVertical = false});

  final Coin coin;
  final bool isVertical;

  @override
  State<CoinBalance> createState() => _CoinBalanceState();
}

class _CoinBalanceState extends State<CoinBalance> {
  /// Held for the lifetime of the widget rather than created in [build].
  ///
  /// Every `watchBalance` call returns a new stream. Creating one in [build]
  /// makes [StreamBuilder] unsubscribe and resubscribe on every rebuild, which
  /// flaps the SDK's per-asset broadcast controller 1->0->1 and re-runs its
  /// `onCancel`/`onListen` hooks - tearing down and restarting the KDF balance
  /// watcher (an IndexedDB read plus several RPCs) each time.
  late Stream<BalanceInfo> _balanceStream;

  @override
  void initState() {
    super.initState();
    _balanceStream = context.sdk.balances.watchBalance(widget.coin.id);
  }

  @override
  void didUpdateWidget(covariant CoinBalance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coin.id != widget.coin.id) {
      _balanceStream = context.sdk.balances.watchBalance(widget.coin.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coin = widget.coin;
    final isVertical = widget.isVertical;
    final baseFont = Theme.of(context).textTheme.bodySmall;
    final balanceStyle = baseFont?.copyWith(fontWeight: FontWeight.w500);
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );

    return StreamBuilder<BalanceInfo>(
      stream: _balanceStream,
      builder: (context, snapshot) {
        final balance = snapshot.data?.spendable.toDouble();
        final balanceText = hideBalances
            ? maskedBalanceText
            : balance == null
            ? '--'
            : doubleToString(balance);

        final children = [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: AutoScrollText(
                  key: Key('coin-balance-asset-${coin.abbr.toLowerCase()}'),
                  text: balanceText,
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
      },
    );
  }
}
