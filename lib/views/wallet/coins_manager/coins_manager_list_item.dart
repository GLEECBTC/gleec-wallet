import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/widgets/coin_fiat_balance.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';

class CoinsManagerListItem extends StatelessWidget {
  const CoinsManagerListItem({
    super.key,
    required this.coin,
    required this.isSelected,
    required this.isMobile,
    required this.isAddAssets,
    required this.onSelect,
  });

  final Coin coin;
  final bool isSelected;
  final bool isMobile;
  final bool isAddAssets;
  final Function() onSelect;

  @override
  Widget build(BuildContext context) {
    return isMobile
        ? _CoinsManagerListItemMobile(
            coin: coin,
            isAddAssets: isAddAssets,
            protocolColor: getProtocolColor(coin.type),
            protocolText: _protocolText,
            isSelected: isSelected,
            onSelect: onSelect,
          )
        : _CoinsManagerListItemDesktop(
            coin: coin,
            isAddAssets: isAddAssets,
            protocolColor: getProtocolColor(coin.type),
            protocolText: _protocolText,
            isSelected: isSelected,
            onSelect: onSelect,
          );
  }

  String get _protocolText => coin.typeName;
}

class _CoinsManagerListItemDesktop extends StatelessWidget {
  const _CoinsManagerListItemDesktop({
    required this.isAddAssets,
    required this.coin,
    required this.isSelected,
    required this.onSelect,
    required this.protocolText,
    required this.protocolColor,
  });

  final bool isAddAssets;
  final Coin coin;
  final bool isSelected;
  final VoidCallback onSelect;
  final String protocolText;
  final Color protocolColor;

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    final balance = coin.balance(context.sdk) ?? 0.0;
    final bool isZeroBalance = balance == 0.0;
    final Color balanceColor = isZeroBalance
        ? theme.custom.coinsManagerTheme.listItemZeroBalanceColor
        : theme.custom.balanceColor;
    return InkWell(
      key: Key('coins-manager-list-item-${coin.abbr.toLowerCase()}'),
      borderRadius: BorderRadius.circular(8),
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.onSurface,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 20.0),
              child: UiSwitcher(
                value: isSelected,
                onChanged: (_) => onSelect(),
              ),
            ),
            Expanded(
              flex: 2,
              child: CoinItem(coin: coin, size: CoinItemSize.large),
            ),
            Expanded(
              flex: isAddAssets ? 2 : 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: protocolColor,
                      border: Border.all(
                        color: coin.type == CoinType.smartChain
                            ? theme.custom.smartchainLabelBorderColor
                            : protocolColor,
                      ),
                    ),
                    child: Text(
                      protocolText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme
                            .custom
                            .coinsManagerTheme
                            .listItemProtocolTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!isAddAssets)
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: AutoScrollText(
                        text: hideBalances
                            ? maskedBalanceText
                            : isZeroBalance
                            ? formatAmt(balance)
                            : formatDexAmt(coin.balance),
                        style: TextStyle(
                          color: balanceColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        coin.abbr,
                        style: TextStyle(
                          color: balanceColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: CoinFiatBalance(
                                coin,
                                isAutoScrollEnabled: true,
                                style: TextStyle(
                                  color: balanceColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoinsManagerListItemMobile extends StatelessWidget {
  const _CoinsManagerListItemMobile({
    required this.isAddAssets,
    required this.coin,
    required this.isSelected,
    required this.onSelect,
    required this.protocolText,
    required this.protocolColor,
  });

  final bool isAddAssets;
  final Coin coin;
  final bool isSelected;
  final VoidCallback onSelect;
  final String protocolText;
  final Color protocolColor;

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    final balance = coin.balance(context.sdk) ?? 0.0;
    final bool isZeroBalance = balance == 0.0;
    final Color balanceColor = isZeroBalance
        ? theme.custom.coinsManagerTheme.listItemZeroBalanceColor
        : theme.custom.balanceColor;
    return InkWell(
      key: Key('coins-manager-list-item-${coin.abbr.toLowerCase()}'),
      borderRadius: BorderRadius.circular(8),
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          children: [
            Checkbox(
              value: isSelected,
              splashRadius: 18,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              onChanged: (_) => onSelect(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: CoinItem(coin: coin, size: CoinItemSize.large),
            ),
            if (!isAddAssets)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AutoScrollText(
                    text: hideBalances
                        ? maskedBalanceText
                        : isZeroBalance
                        ? formatAmt(balance)
                        : formatDexAmt(balance),
                    style: TextStyle(
                      color: balanceColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: CoinFiatBalance(
                          coin,
                          isAutoScrollEnabled: true,
                          style: TextStyle(
                            color: balanceColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
