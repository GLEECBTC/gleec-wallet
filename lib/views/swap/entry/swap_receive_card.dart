part of 'swap_amount_cards.dart';

/// The receive side: what the selected option is expected to deliver.
class SwapReceiveCard extends StatelessWidget {
  const SwapReceiveCard({
    required this.state,
    required this.network,
    required this.onPickAsset,
    super.key,
  });

  final UnifiedSwapState state;
  final String? network;
  final VoidCallback onPickAsset;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final quote = state.selectedQuote;
    final receive = state.receive;
    final checking =
        state.evaluation == SwapEvaluationStatus.checking && quote == null;
    final address = quote?.toAddress ?? state.receiveAddress;

    final Widget amountText;
    if (checking) {
      amountText = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SwapSkeleton(height: 24, widthFactor: 0.6),
      );
    } else {
      final value = quote?.expectedReceive;
      amountText = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value == null
                  ? '0'
                  : SwapFormat.amount(value, rounding: SwapRounding.down),
              style: SwapText.amount(context).copyWith(
                color: value == null ? palette.textTertiary : palette.text,
              ),
              maxLines: 1,
            ),
          ),
        ),
      );
    }

    return _AmountCardFrame(
      label: LocaleKeys.swapYouReceive.tr(),
      amount: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [amountText, const SizedBox(height: 6), _fiatLine(context)],
      ),
      assetPill: SwapAssetPill(
        asset: receive,
        network: network,
        onTap: onPickAsset,
        semanticLabel: LocaleKeys.swapYouReceive.tr(),
      ),
      footer: address == null && (receive == null || !state.signedIn)
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: _AddressFooterButton(
                prefix: (a) => LocaleKeys.swapToAddress.tr(args: [a]),
                address: address,
                asset: receive,
              ),
            ),
    );
  }

  Widget _fiatLine(BuildContext context) {
    final palette = SwapPalette.of(context);
    final quote = state.selectedQuote;
    if (quote == null) {
      return Text(r'$0.00', style: SwapText.small(context));
    }
    final expected = quote.pricing.expectedUsd;
    if (expected == null) {
      return Text(
        LocaleKeys.swapPriceUnavailable.tr(),
        style: SwapText.small(context),
      );
    }
    final impact = quote.pricing.priceImpact;
    final high = impact != null && impact >= swapHighImpact;
    // A difference that rounds to nothing would read "−0% vs market".
    final shown =
        impact != null &&
        SwapFormat.percent(impact.abs()) != SwapFormat.percent(Decimal.zero);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          SwapFormat.usd(expected, rounding: SwapRounding.down),
          style: SwapText.small(context),
        ),
        if (shown)
          Text(
            LocaleKeys.swapVsMarket.tr(
              args: [
                '${impact > Decimal.zero ? '−' : '+'}'
                    '${SwapFormat.percent(impact.abs())}',
              ],
            ),
            style: SwapText.small(context).copyWith(
              color: high ? palette.warning : palette.textTertiary,
              fontWeight: high ? FontWeight.w700 : null,
            ),
          ),
      ],
    );
  }
}
