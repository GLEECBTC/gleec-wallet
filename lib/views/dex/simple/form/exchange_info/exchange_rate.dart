import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/views/dex/dex_helpers.dart';

class ExchangeRate extends StatelessWidget {
  const ExchangeRate({
    required this.base,
    required this.rel,
    required this.rate,
    super.key,
    this.showDetails = true,
  });

  final String? base;
  final String? rel;
  final Rational? rate;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final isEmptyData = rate == null || base == null || rel == null;
    final typography = GleecTypography.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('${LocaleKeys.rate.tr()}:', style: typography.bodySmall),
        if (isEmptyData)
          Text('0.00', style: typography.tabularAmountCompact)
        else
          Flexible(
            child: _Rates(
              base: base,
              rel: rel,
              rate: rate,
              showDetails: showDetails,
            ),
          ),
      ],
    );
  }
}

class _Rates extends StatelessWidget {
  const _Rates({
    required this.base,
    required this.rel,
    required this.rate,
    this.showDetails = true,
  });

  final String? base;
  final String? rel;
  final Rational? rate;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final typography = GleecTypography.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              ' 1 ${Coin.normalizeAbbr(base ?? '')} = ',
              style: typography.tabularAmountCompact,
            ),
            Flexible(
              child: AutoScrollText(
                text: ' $price ${Coin.normalizeAbbr(rel ?? '')}',
                style: typography.tabularAmountCompact,
              ),
            ),
            Text(
              showDetails ? '(${baseFiat(context)})' : '',
              style: typography.tabularAmountCompact,
            ),
          ],
        ),
        if (showDetails)
          Text(
            '1 ${Coin.normalizeAbbr(rel ?? '')} ='
            ' $quotePrice'
            ' ${Coin.normalizeAbbr(base ?? '')}'
            ' (${relFiat(context)})',
            style: typography.bodySmall.copyWith(color: colors.textTertiary),
          ),
      ],
    );
  }

  String baseFiat(BuildContext context) {
    return getFormattedFiatAmount(context, rel ?? '', rate ?? Rational.zero);
  }

  String relFiat(BuildContext context) {
    if (rate == Rational.zero) {
      return getFormattedFiatAmount(context, base ?? '', Rational.zero);
    }
    return getFormattedFiatAmount(
      context,
      base ?? '',
      rate?.inverse ?? Rational.zero,
    );
  }

  String get price {
    if (rate == null) return '0';
    return formatDexAmt(rate);
  }

  String get quotePrice {
    if (rate == null || rate == Rational.zero) return '0';
    return formatDexAmt(rate!.inverse);
  }
}
