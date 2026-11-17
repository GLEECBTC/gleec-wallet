part of 'swap_amount_cards.dart';

/// The receive side: what the selected option is expected to deliver.
class SwapReceiveCard extends StatelessWidget {
  const SwapReceiveCard({
    required this.state,
    required this.network,
    required this.onPickAsset,
    this.previousEstimate = false,
    super.key,
  });

  final UnifiedSwapState state;
  final String? network;
  final VoidCallback onPickAsset;

  /// The desktop review has revised terms; this card still describes the
  /// preserved draft, which must not look like a competing current quote.
  final bool previousEstimate;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final quote = state.selectedQuote;
    final receive = state.receive;

    // Unknown or updating amounts are never represented by a real zero.
    // The stable row keeps typing and quote arrivals from moving the cards.
    final value = quote?.expectedReceive;
    final amountText = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value == null
                ? '—'
                : SwapFormat.amount(value, rounding: SwapRounding.down),
            style: SwapText.amount(context).copyWith(
              color: value == null ? palette.textTertiary : palette.text,
            ),
            maxLines: 1,
          ),
        ),
      ),
    );

    return _AmountCardFrame(
      label: previousEstimate
          ? 'swapPreviousEstimate'.tr()
          : LocaleKeys.swapYouReceive.tr(),
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
    );
  }

  Widget _fiatLine(BuildContext context) {
    final palette = SwapPalette.of(context);
    final quote = state.selectedQuote;
    if (quote == null) {
      final hasIntent = state.inputText.trim().isNotEmpty && state.hasPair;
      final updating =
          state.preparingAssets ||
          state.checkingMax ||
          state.evaluation == SwapEvaluationStatus.checking ||
          (state.evaluation == SwapEvaluationStatus.idle &&
              state.preparationFailedAsset == null &&
              state.failure == null &&
              state.tradingEnabled &&
              (state.issue?.stillPriced ?? true));
      // A completed failure must not keep promising an update. The specific
      // reason and recovery action remain below the cards.
      final label = !hasIntent
          ? 'swapEstimatePlaceholder'
          : updating
          ? 'swapEstimateUpdating'
          : LocaleKeys.swapPriceUnavailable;
      return Text(label.tr(), style: SwapText.small(context));
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
