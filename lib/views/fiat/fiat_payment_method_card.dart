import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/bloc/fiat/models/fiat_payment_method.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class FiatPaymentMethodCard extends StatefulWidget {
  const FiatPaymentMethodCard({
    required this.fiatAmount,
    required this.paymentMethodData,
    required this.selectedPaymentMethod,
    required this.onSelect,
    super.key,
  });
  final String? fiatAmount;
  final FiatPaymentMethod paymentMethodData;
  final FiatPaymentMethod? selectedPaymentMethod;
  final void Function(FiatPaymentMethod) onSelect;

  @override
  FiatPaymentMethodCardState createState() => FiatPaymentMethodCardState();
}

class FiatPaymentMethodCardState extends State<FiatPaymentMethodCard> {
  @override
  Widget build(BuildContext context) {
    final bool isSelected =
        widget.selectedPaymentMethod != null &&
        widget.selectedPaymentMethod!.id == widget.paymentMethodData.id;

    final relativePercent = widget.paymentMethodData.relativePercent;
    final isBestOffer = relativePercent == Decimal.zero;

    return InkWell(
      onTap: () {
        widget.onSelect(widget.paymentMethodData);
      },
      borderRadius: BorderRadius.circular(8),
      child: Card(
        margin: EdgeInsets.zero,
        color: Theme.of(context).scaffoldBackgroundColor,
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Theme.of(
              context,
            ).primaryColor.withValues(alpha: isSelected ? 1 : 0.25),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(width: 32, child: providerLogo),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.paymentMethodData.name,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.paymentMethodData.providerId,
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isBestOffer)
                  Chip(
                    label: Text(LocaleKeys.bestOffer.tr()),
                    backgroundColor: Colors.green,
                  )
                else
                  Text(
                    '${(relativePercent * Decimal.fromInt(100)).toStringAsFixed(2)}%',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget get providerLogo {
    final assetPath = widget.paymentMethodData.providerIconAssetPath;

    //TODO: Additional validation that the asset exists

    return SvgPicture.asset(assetPath);
  }
}
