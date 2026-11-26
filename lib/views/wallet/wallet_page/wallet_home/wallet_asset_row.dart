import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_cex_market_data/komodo_cex_market_data.dart'
    show SparklineRepository;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/balance_format.dart';
import 'package:web_dex/shared/utils/extensions/sdk_extensions.dart';
import 'package:web_dex/shared/utils/fiat_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/wallet/coin_details/coin_details_info/charts/coin_sparkline.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/asset_display_name.dart';
import 'package:web_dex/views/wallet/wallet_page/wallet_home/wallet_home_style.dart';

part 'wallet_asset_row_price.dart';

/// One asset in the wallet: its logo, name and network, and market price
/// with the 24h change; on the right, what is held, in dollars and in coins.
///
/// Held amounts are never cut short, since "147…" for a 14,772 balance reads
/// as a different number: the value column shrinks its text to fit, and the
/// name gives way first.
class WalletAssetRow extends StatefulWidget {
  const WalletAssetRow({
    required this.coin,
    required this.onTap,
    this.onLongPress,
    this.showDivider = false,
    this.borderRadius,
    super.key,
  });

  final Coin coin;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Draws a hairline above the row, inset to where its text starts.
  final bool showDivider;

  /// Clips the press highlight to the group's corners.
  final BorderRadius? borderRadius;

  /// The market price on a row, a dash until there is one.
  static const priceKey = Key('wallet-asset-price');

  /// The amount held on the row for [abbr], under the key the older wallet
  /// list gave it.
  static Key amountKey(String abbr) =>
      Key('coin-balance-asset-${abbr.toLowerCase()}');

  @override
  State<WalletAssetRow> createState() => _WalletAssetRowState();
}

class _WalletAssetRowState extends State<WalletAssetRow> {
  /// Held for the widget's lifetime: a `watchBalance` stream made in [build]
  /// restarts the SDK's balance watcher on every rebuild.
  late Stream<BalanceInfo> _balanceStream;

  @override
  void initState() {
    super.initState();
    _balanceStream = context.sdk.balances.watchBalance(widget.coin.id);
  }

  @override
  void didUpdateWidget(covariant WalletAssetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coin.id != widget.coin.id) {
      _balanceStream = context.sdk.balances.watchBalance(widget.coin.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coin = widget.coin;
    final sdk = context.sdk;
    final hidden = context.select(
      (SettingsBloc bloc) => bloc.state.hideBalances,
    );
    final price = context.select(
      (CoinsBloc bloc) =>
          bloc.state.getPriceForAsset(coin.id)?.price?.toDouble(),
    );
    final change = context.select(
      (CoinsBloc bloc) => bloc.state.get24hChangeForAsset(coin.id),
    );
    final names = assetDisplayParts(coin);

    return StreamBuilder<BalanceInfo>(
      initialData: sdk.balances.lastKnown(coin.id),
      stream: _balanceStream,
      builder: (context, snapshot) {
        final balance =
            (snapshot.hasError
                    ? sdk.balances.lastKnown(coin.id)
                    : snapshot.data)
                ?.spendable
                .toDouble();
        return Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            // A right click is the long press of a mouse.
            onSecondaryTap: widget.onLongPress,
            borderRadius: widget.borderRadius,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.showDivider) const _Divider(),
                Padding(
                  padding: WalletHomeGeometry.rowPadding,
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        constraints.maxWidth >= WalletHomeGeometry.wideRowFrom
                        ? _WideRow(
                            coin: coin,
                            name: names.name,
                            network: names.network,
                            price: price,
                            change: change,
                            balance: balance,
                            hidden: hidden,
                          )
                        : Row(
                            children: [
                              AssetLogo.ofId(
                                coin.id,
                                size: WalletHomeGeometry.logoSize,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _NameAndPrice(
                                  name: names.name,
                                  network: names.network,
                                  price: price,
                                  change: change,
                                ),
                              ),
                              const SizedBox(width: 12),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth * 0.42,
                                ),
                                child: _Holding(
                                  balance: balance,
                                  price: price,
                                  symbol: coin.id.symbol.configSymbol,
                                  hidden: hidden,
                                  amountKey: WalletAssetRow.amountKey(
                                    coin.abbr,
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
        );
      },
    );
  }
}

class _NameAndPrice extends StatelessWidget {
  const _NameAndPrice({
    required this.name,
    required this.network,
    required this.price,
    required this.change,
    this.showPrice = true,
  });

  final String name;
  final String? network;
  final double? price;
  final double? change;

  /// Off where the price has a column of its own.
  final bool showPrice;

  @override
  Widget build(BuildContext context) {
    final network = this.network;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The chip flows after the name, so with large text the pair wraps
        // onto a second line rather than cutting the name short.
        Text.rich(
          TextSpan(
            text: name,
            children: [
              if (network != null)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 6),
                    child: NetworkChip(label: network),
                  ),
                ),
            ],
          ),
          style: WalletHomeText.title(context),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (showPrice) ...[
          const SizedBox(height: 3),
          _PriceLine(price: price, change: change),
        ],
      ],
    );
  }
}

/// The row on a wide screen: the price with its 24h change, the week's
/// sparkline and the holding each take a column, so they line up down the
/// list.
class _WideRow extends StatelessWidget {
  const _WideRow({
    required this.coin,
    required this.name,
    required this.network,
    required this.price,
    required this.change,
    required this.balance,
    required this.hidden,
  });

  final Coin coin;
  final String name;
  final String? network;
  final double? price;
  final double? change;
  final double? balance;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    // Only the app provides one; without it the row has no sparkline.
    final sparklines = context.read<SparklineRepository?>();
    return Row(
      children: [
        AssetLogo.ofId(coin.id, size: WalletHomeGeometry.logoSize),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: _NameAndPrice(
            name: name,
            network: network,
            price: price,
            change: change,
            showPrice: false,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: _PriceColumn(price: price, change: change),
        ),
        if (sparklines != null) ...[
          const SizedBox(width: 24),
          SizedBox(
            width: 90,
            height: 36,
            child: CoinSparkline(coinId: coin.id, repository: sparklines),
          ),
        ],
        const SizedBox(width: 24),
        Expanded(
          flex: 3,
          child: _Holding(
            balance: balance,
            price: price,
            symbol: coin.id.symbol.configSymbol,
            hidden: hidden,
            amountKey: WalletAssetRow.amountKey(coin.abbr),
          ),
        ),
      ],
    );
  }
}

class _Holding extends StatelessWidget {
  const _Holding({
    required this.balance,
    required this.price,
    required this.symbol,
    required this.hidden,
    required this.amountKey,
  });

  final double? balance;
  final double? price;
  final String symbol;
  final bool hidden;
  final Key amountKey;

  @override
  Widget build(BuildContext context) {
    final balance = this.balance;
    final price = this.price;
    if (balance == null && !hidden) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Bar(width: 64, height: 14),
          SizedBox(height: 6),
          _Bar(width: 44, height: 10),
        ],
      );
    }
    final palette = SwapPalette.of(context);
    final String value;
    final String amount;
    if (hidden) {
      value = '\$$maskedBalanceText';
      amount = '$maskedBalanceText $symbol';
    } else {
      value = price == null ? '—' : FiatFormat.amount(balance! * price);
      amount = '${formatListBalance(balance!)} $symbol';
    }
    final isEmpty = !hidden && balance == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _fit(
          Text(
            value,
            maxLines: 1,
            style: WalletHomeText.value(context).copyWith(
              color: isEmpty || price == null
                  ? palette.textTertiary
                  : palette.text,
            ),
          ),
        ),
        const SizedBox(height: 3),
        _fit(
          Text(
            amount,
            key: amountKey,
            maxLines: 1,
            style: WalletHomeText.detail(context),
          ),
        ),
      ],
    );
  }

  Widget _fit(Widget child) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerEnd,
    child: child,
  );
}

/// The network a token runs on, beside its name: `ERC-20`, `TRC-20`.
class NetworkChip extends StatelessWidget {
  const NetworkChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SwapPalette.of(context).surfaceHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(label, style: WalletHomeText.chip(context), maxLines: 1),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: WalletHomeGeometry.rowTextInset,
      ),
      child: Divider(
        height: 1,
        thickness: 1,
        color: SwapPalette.of(context).border.withValues(alpha: 0.6),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: SwapPalette.of(context).surfaceHigh,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
