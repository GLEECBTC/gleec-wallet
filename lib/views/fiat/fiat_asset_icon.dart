import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/fiat/models/i_currency.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_item_size.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_protocol_name.dart';
import 'package:web_dex/shared/widgets/coin_item/coin_ticker.dart';
import 'package:web_dex/shared/widgets/segwit_icon.dart';
import 'package:web_dex/views/fiat/fiat_icon.dart';

class FiatAssetIcon extends StatelessWidget {
  const FiatAssetIcon({
    required this.currency,
    required this.icon,
    required this.onTap,
    required this.assetExists,
    super.key,
    this.expanded = false,
  });

  final ICurrency currency;
  final Widget icon;
  final VoidCallback onTap;
  final bool? assetExists;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (currency.isFiat) {
      return FiatIcon(symbol: currency.getAbbr());
    }

    final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
    final asset = sdk.getSdkAsset(currency.getAbbr());
    final coin = asset.toCoin();
    final size = CoinItemSize.large;

    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AssetLogo.ofId(coin.id, size: size.coinLogo),
        SizedBox(width: size.spacer),
        expanded
            ? Expanded(
                child: _FiatCoinItemLabel(size: size, coin: coin),
              )
            : Flexible(
                fit: expanded ? FlexFit.tight : FlexFit.loose,
                child: _FiatCoinItemLabel(size: size, coin: coin),
              ),
      ],
    );
  }
}

class _FiatCoinItemLabel extends StatelessWidget {
  const _FiatCoinItemLabel({super.key, required this.size, required this.coin});

  final CoinItemSize size;
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: size.spacer),
        _FiatCoinItemTitle(coin: coin, size: size),
        SizedBox(height: size.spacer),
        _FiatCoinItemSubtitle(coin: coin, size: size),
      ],
    );
  }
}

class _FiatCoinItemTitle extends StatelessWidget {
  const _FiatCoinItemTitle({required this.coin, required this.size});

  final Coin? coin;
  final CoinItemSize size;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showCoinName = constraints.maxWidth > 75;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CoinTicker(
              coinId: coin?.abbr,
              style: TextStyle(fontSize: size.titleFontSize, height: 1),
              showSuffix: false,
            ),
            if (showCoinName) ...[
              SizedBox(width: size.spacer),
              Flexible(
                child: _FiatCoinName(
                  text: coin?.displayName,
                  style: TextStyle(fontSize: size.titleFontSize, height: 1),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FiatCoinItemSubtitle extends StatelessWidget {
  const _FiatCoinItemSubtitle({required this.coin, required this.size});

  final Coin? coin;
  final CoinItemSize size;

  @override
  Widget build(BuildContext context) {
    return coin?.mode == CoinMode.segwit
        ? SegwitIcon(height: size.segwitIconSize)
        : CoinProtocolName(
            text: coin?.typeNameWithTestnet,
            upperCase: true,
            size: size,
          );
  }
}

class _FiatCoinName extends StatelessWidget {
  const _FiatCoinName({required this.text, this.style});

  final String? text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final String? coinName = text;
    if (coinName == null) return const SizedBox.shrink();

    return AutoScrollText(
      text: coinName,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppPalette.of(context).textTertiary,
      ).merge(style),
    );
  }
}
