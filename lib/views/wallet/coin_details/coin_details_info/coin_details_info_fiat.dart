import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui/komodo_ui.dart' show TrendPercentageText;
import 'package:komodo_ui_kit/komodo_ui_kit.dart' show AppPalette;
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/widgets/coin_fiat_balance.dart';
import 'package:web_dex/shared/utils/fiat_format.dart';
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';

class CoinDetailsInfoFiat extends StatelessWidget {
  const CoinDetailsInfoFiat({
    Key? key,
    required this.coin,
    required this.isMobile,
  }) : super(key: key);

  final bool isMobile;
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: isMobile ? null : const EdgeInsets.fromLTRB(0, 6, 4, 0),
      child: Flex(
        direction: isMobile ? Axis.horizontal : Axis.vertical,
        mainAxisAlignment: isMobile
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.end,
        crossAxisAlignment: isMobile
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.end,
        mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (isMobile) _AssetFiatBalance(isMobile: isMobile, coin: coin),
          _AssetFiatPrice(coin: coin, isMobile: isMobile),
          if (!isMobile) const SizedBox(height: 6),
          _AssetFiatValuePercentageChange(isMobile: isMobile, coin: coin),
        ],
      ),
    );
  }
}

class _AssetFiatPrice extends StatelessWidget {
  const _AssetFiatPrice({required this.coin, required this.isMobile});

  final Coin coin;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    // Use the same approach as main wallet page
    final sdk = context.read<KomodoDefiSdk>();
    final double? usdPrice = coin.lastKnownUsdPrice(sdk);

    if (usdPrice == null || usdPrice == 0) return const SizedBox();

    final TextStyle style = TextStyle(
      fontSize: isMobile ? 16 : 14,
      fontWeight: FontWeight.w700,
    );

    return Flex(
      direction: isMobile ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          LocaleKeys.price.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        isMobile ? const SizedBox(height: 3) : const SizedBox(width: 10),
        Text(
          FiatFormat.price(usdPrice),
          key: Key('fiat-price-${coin.abbr.toLowerCase()}'),
          semanticsLabel: FiatFormat.spokenPrice(usdPrice),
          style: style,
        ),
      ],
    );
  }
}

class _AssetFiatValuePercentageChange extends StatelessWidget {
  const _AssetFiatValuePercentageChange({
    required this.coin,
    required this.isMobile,
  });

  final Coin coin;
  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CoinsBloc, CoinsState>(
      buildWhen: (previous, current) {
        return previous.get24hChangeForAsset(coin.id) !=
            current.get24hChangeForAsset(coin.id);
      },
      builder: (context, state) {
        final change24hPercent = state.get24hChangeForAsset(coin.id);
        final palette = AppPalette.of(context);

        return Flex(
          direction: isMobile ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize:
              MainAxisSize.min, // Prevent layout constraint violations
          children: [
            Text(
              LocaleKeys.change24h.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            isMobile ? const SizedBox(height: 3) : const SizedBox(width: 10),
            TrendPercentageText(
              percentage: change24hPercent,
              textStyle: TextStyle(
                fontSize: isMobile ? 16 : 14,
                fontWeight: FontWeight.w700,
              ),
              upColor: palette.success,
              downColor: palette.danger,
              showIcon: false,
              noValueText: '-',
            ),
          ],
        );
      },
    );
  }
}

class _AssetFiatBalance extends StatelessWidget {
  const _AssetFiatBalance({required this.isMobile, required this.coin});

  final bool isMobile;
  final Coin coin;

  @override
  Widget build(BuildContext context) {
    return Flex(
      direction: isMobile ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min, // Prevent layout constraint violations
      children: [
        Text(
          LocaleKeys.fiatBalance.tr(),
          style: Theme.of(context).textTheme.titleSmall!.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
        isMobile ? const SizedBox(height: 3) : const SizedBox(width: 10),
        CoinFiatBalance(
          coin,
          format: FiatFormat.amount,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
