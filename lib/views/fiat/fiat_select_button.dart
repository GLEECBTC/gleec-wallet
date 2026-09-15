import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/bloc/fiat/models/i_currency.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/coin_utils.dart';
import 'package:web_dex/views/fiat/fiat_asset_icon.dart';

class FiatSelectButton extends StatelessWidget {
  const FiatSelectButton({
    required this.context,
    required this.foregroundColor,
    required this.enabled,
    required this.currency,
    required this.icon,
    required this.onTap,
    required this.assetExists,
    super.key,
  });

  final BuildContext context;
  final Color foregroundColor;
  final bool enabled;
  final ICurrency? currency;
  final Widget icon;
  final VoidCallback onTap;
  final bool? assetExists;

  @override
  Widget build(BuildContext context) {
    final isFiat = currency?.isFiat ?? false;
    final cryptoCurrency = currency is CryptoCurrency
        ? currency as CryptoCurrency
        : null;

    return FilledButton.icon(
      onPressed: enabled ? onTap : null,
      label: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFiat)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  (isFiat ? currency?.getAbbr() : currency?.name) ??
                      (isFiat
                          ? LocaleKeys.selectFiat.tr()
                          : LocaleKeys.selectCoin.tr()),
                  style: DefaultTextStyle.of(context).style.copyWith(
                    fontWeight: FontWeight.w500,
                    color: enabled
                        ? foregroundColor
                        : foregroundColor.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down,
            size: 28,
            color: foregroundColor.withValues(alpha: enabled ? 1 : 0.5),
          ),
        ],
      ),
      style: (Theme.of(context).filledButtonTheme.style ?? const ButtonStyle())
          .copyWith(
            backgroundColor: WidgetStateProperty.all<Color>(
              Theme.of(context).scaffoldBackgroundColor,
            ),
            padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
              const EdgeInsets.symmetric(),
            ),
            shape: WidgetStateProperty.all<OutlinedBorder>(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
      icon: currency == null
          ? Icon(_getDefaultAssetIcon(isFiat ? 'fiat' : 'coin'))
          : Flexible(
              child: FiatAssetIcon(
                currency: currency!,
                icon: icon,
                onTap: onTap,
                assetExists: assetExists,
                expanded: true,
              ),
            ),
    );
  }
}

IconData _getDefaultAssetIcon(String type) {
  return type == 'fiat' ? Icons.attach_money : Icons.monetization_on;
}
