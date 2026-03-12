// lib/src/defi/asset/coin_list_item.dart

import 'package:app_theme/src/dark/theme_custom_dark.dart';
import 'package:app_theme/src/light/theme_custom_light.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/coin_balance.dart';
import 'package:web_dex/shared/widgets/coin_fiat_balance.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/views/wallet/common/address_icon.dart';

/// Widget for showing an authenticated user's balance and anddresses for a
/// given coin
// TODO: Refactor to `AssetId` and migrate to the SDK UI library.
class ExpandableCoinListItem extends StatefulWidget {
  final Coin coin;
  final AssetPubkeys? pubkeys;
  final bool isSelected;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final VoidCallback? onStatisticsTap;

  const ExpandableCoinListItem({
    super.key,
    required this.coin,
    required this.pubkeys,
    required this.isSelected,
    this.onTap,
    this.onStatisticsTap,
    this.backgroundColor,
  });

  @override
  State<ExpandableCoinListItem> createState() => _ExpandableCoinListItemState();
}

class _ExpandableCoinListItemState extends State<ExpandableCoinListItem> {
  // Store the expansion state in the widget's state
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // Attempt to restore state from PageStorage using a unique key
    _isExpanded =
        PageStorage.of(
              context,
            ).readState(context, identifier: '${widget.coin.abbr}_expanded')
            as bool? ??
        false;
  }

  void _handleExpansionChanged(bool expanded) {
    setState(() {
      _isExpanded = expanded;
      // Save state to PageStorage using a unique key
      PageStorage.of(context).writeState(
        context,
        _isExpanded,
        identifier: '${widget.coin.abbr}_expanded',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAddresses = widget.pubkeys?.keys.isNotEmpty ?? false;
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    final sortedAddresses = hasAddresses
        ? (List.of(
            widget.pubkeys!.keys,
          )..sort((a, b) => b.balance.spendable.compareTo(a.balance.spendable)))
        : null;
    final children = sortedAddresses != null
        ? sortedAddresses
              .map(
                (pubkey) => _AddressRow(
                  pubkey: pubkey,
                  coin: widget.coin,
                  isSwapAddress: pubkey == sortedAddresses.first,
                  onTap: widget.onTap,
                  onCopy: () => copyToClipBoard(context, pubkey.address),
                  hideBalances: hideBalances,
                ),
              )
              .toList()
        : [SkeletonListTile()];

    // Match GroupedAssetTickerItem: 16 horizontal, 16 vertical for both (mobile)
    // For desktop, set vertical padding to achieve 78px height
    final horizontalPadding = 16.0;
    final verticalPadding = isMobile ? 16.0 : 22.0; // 34 (icon) + 22*2 = 78

    // TODO! Change rotation of the icon in contracted state
    return CollapsibleCard(
      key: PageStorageKey('coin_${widget.coin.abbr}'),
      borderRadius: BorderRadius.circular(12),
      headerPadding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      onTap: widget.onTap,
      childrenMargin: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      childrenDecoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      initiallyExpanded: _isExpanded,
      onExpansionChanged: _handleExpansionChanged,
      expansionControlPosition: ExpansionControlPosition.leading,
      emptyChildrenBehavior: EmptyChildrenBehavior.disable,
      isDense: true,
      title: _buildTitle(context, hideBalances),
      maintainState: true,
      childrenDivider: const Divider(height: 1, indent: 16, endIndent: 16),
      trailing: CoinMoreActionsButton(coin: widget.coin),
      children: children,
    );
  }

  Widget _buildTitle(BuildContext context, bool hideBalances) {
    final theme = Theme.of(context);

    if (isMobile) {
      return _buildMobileTitle(context, theme, hideBalances);
    } else {
      return _buildDesktopTitle(context, theme, hideBalances);
    }
  }

  Widget _buildMobileTitle(
    BuildContext context,
    ThemeData theme,
    bool hideBalances,
  ) {
    final statsTap = widget.onStatisticsTap;
    return Container(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Use CoinItem with large size for mobile, matching GroupedAssetTickerItem
          AssetIcon(widget.coin.id, size: CoinItemSize.large.coinLogo),
          const SizedBox(width: 8),
          Expanded(
            flex: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Coin name - using headlineMedium for bold 16px text
                AutoScrollText(
                  text: widget.coin.displayName,
                  style: theme.textTheme.headlineMedium,
                ),
                // Crypto balance - using bodySmall for 12px secondary text
                AutoScrollText(
                  text: hideBalances
                      ? '$maskedBalanceText ${widget.coin.abbr}'
                      : '${doubleToString(widget.coin.balance(context.sdk) ?? 0)} ${widget.coin.abbr}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Spacer(),
          // Right side: Price and trend info
          Expanded(
            flex: 7,
            child: InkWell(
              onTap: statsTap,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Current balance in USD - using headlineMedium for bold 16px text
                  _UsdBalanceText(
                    coin: widget.coin,
                    textStyle: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 2),
                  // Trend percentage
                  if (!hideBalances)
                    BlocBuilder<CoinsBloc, CoinsState>(
                      builder: (context, state) {
                        final usdBalance = widget.coin.lastKnownUsdBalance(
                          context.sdk,
                        );
                        if (usdBalance == null) {
                          return const SizedBox.shrink();
                        }

                        final change24hPercent = usdBalance == 0.0
                            ? 0.0
                            : state.get24hChangeForAsset(widget.coin.id);
                        // Calculate the 24h USD change value
                        final change24hValue =
                            change24hPercent != null && usdBalance > 0
                            ? (change24hPercent * usdBalance / 100)
                            : 0.0;
                        final themeCustom =
                            Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).extension<ThemeCustomDark>()!
                            : Theme.of(context).extension<ThemeCustomLight>()!;
                        return TrendPercentageText(
                          percentage: change24hPercent,
                          value: change24hValue,
                          upColor: themeCustom.increaseColor,
                          downColor: themeCustom.decreaseColor,
                          valueFormatter: (value) =>
                              NumberFormat.currency(symbol: '\$').format(value),
                          iconSize: 12,
                          spacing: 2,
                          textStyle: theme.textTheme.bodySmall,
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTitle(
    BuildContext context,
    ThemeData theme,
    bool hideBalances,
  ) {
    final statsTap = widget.onStatisticsTap;
    return Container(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 180),
            child: CoinItem(coin: widget.coin, size: CoinItemSize.large),
          ),
          const Spacer(),
          InkWell(
            onTap: statsTap,
            borderRadius: BorderRadius.circular(8),
            child: CoinBalance(coin: widget.coin),
          ),
          if (!hideBalances)
            BlocBuilder<CoinsBloc, CoinsState>(
              builder: (context, state) {
                final usdBalance = widget.coin.lastKnownUsdBalance(context.sdk);
                if (usdBalance == null) {
                  return const SizedBox.shrink();
                }

                final change24hPercent = usdBalance == 0.0
                    ? 0.0
                    : state.get24hChangeForAsset(widget.coin.id);

                // Calculate the 24h USD change value
                final change24hValue =
                    change24hPercent != null && usdBalance > 0
                    ? (change24hPercent * usdBalance / 100)
                    : 0.0;

                final themeCustom =
                    Theme.of(context).brightness == Brightness.dark
                    ? Theme.of(context).extension<ThemeCustomDark>()!
                    : Theme.of(context).extension<ThemeCustomLight>()!;
                return InkWell(
                  onTap: statsTap,
                  borderRadius: BorderRadius.circular(8),
                  child: TrendPercentageText(
                    percentage: change24hPercent,
                    value: change24hValue,
                    upColor: themeCustom.increaseColor,
                    downColor: themeCustom.decreaseColor,
                    valueFormatter: (value) =>
                        NumberFormat.currency(symbol: '\$').format(value),
                  ),
                );
              },
            ),
          // const Spacer(),
        ],
      ),
    );
  }
}

class _UsdBalanceText extends StatelessWidget {
  const _UsdBalanceText({required this.coin, this.textStyle});

  final Coin coin;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final hideBalances = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    if (hideBalances) {
      return Text('\$$maskedBalanceText', style: textStyle);
    }

    final balanceStream = context.sdk.balances.watchBalance(coin.id);
    return BlocSelector<CoinsBloc, CoinsState, double?>(
      selector: (state) => state.getPriceForAsset(coin.id)?.price?.toDouble(),
      builder: (context, price) {
        return StreamBuilder<BalanceInfo>(
          stream: balanceStream,
          builder: (context, snapshot) {
            final balance = snapshot.data?.spendable.toDouble();
            if (balance == null || price == null) {
              return Text('--', style: textStyle);
            }
            final formatted = NumberFormat("#,##0.00").format(price * balance);
            return Text('\$$formatted', style: textStyle);
          },
        );
      },
    );
  }
}

class _AddressRow extends StatelessWidget {
  final PubkeyInfo pubkey;
  final Coin coin;
  final bool isSwapAddress;
  final bool hideBalances;
  final VoidCallback? onTap;
  final VoidCallback? onCopy;

  const _AddressRow({
    required this.pubkey,
    required this.coin,
    required this.isSwapAddress,
    required this.hideBalances,
    required this.onTap,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 16,
        ),
        leading: AddressIcon(address: pubkey.address),
        title: Row(
          children: [
            Flexible(
              child: AutoScrollText(
                text: pubkey.address,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: IconButton(
                iconSize: 16,
                icon: const Icon(Icons.copy),
                onPressed: onCopy,
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (isSwapAddress) ...[
              const SizedBox(width: 8),
              // TODO: Refactor to use "DexPill" component from the SDK UI library (not yet created)
              Padding(
                padding: EdgeInsets.only(left: isMobile ? 4 : 8),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    vertical: isMobile ? 6 : 8,
                    horizontal: isMobile ? 8 : 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiary,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Text(
                    LocaleKeys.swapAddress.tr(),
                    style: TextStyle(fontSize: isMobile ? 9 : 12),
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              hideBalances
                  ? '$maskedBalanceText ${coin.abbr}'
                  : '${doubleToString(pubkey.balance.spendable.toDouble())} ${coin.abbr}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            CoinFiatBalance(
              coin,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// This will be able to be removed in the near future when activation state
// is removed from the GUI because it is handled internall by the SDK.
class CoinMoreActionsButton extends StatelessWidget {
  const CoinMoreActionsButton({required this.coin});

  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CoinMoreActions>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) async {
        switch (action) {
          case CoinMoreActions.disable:
            confirmBeforeDisablingCoin(coin, context);
        }
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            value: CoinMoreActions.disable,
            child: Text(LocaleKeys.disable.tr()),
          ),
        ];
      },
    );
  }
}

enum CoinMoreActions { disable }
