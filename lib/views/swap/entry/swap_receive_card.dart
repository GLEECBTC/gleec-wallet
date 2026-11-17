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

  bool get _expired => state.evaluation == SwapEvaluationStatus.expired;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final quote = state.selectedQuote;
    final receive = state.receive;

    // Unknown or updating amounts are never represented by a real zero.
    // The stable row keeps typing and quote arrivals from moving the cards.
    final value = quote?.expectedReceive;
    // An amount that no longer holds steps back, as the placeholder does.
    final current = value != null && !previousEstimate && !_expired;
    final amountStyle = SwapText.amount(context)
        .copyWith(color: current ? palette.text : palette.textTertiary);
    final amountText = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // What arrives is an estimate until it has arrived. The sign
              // stays quiet so the figure leads.
              if (value != null) ...[
                Text(
                  '≈',
                  style: amountStyle.copyWith(
                    color: palette.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                value == null
                    ? SwapFormat.unknown
                    : SwapFormat.amount(value, rounding: SwapRounding.down),
                style: amountStyle,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );

    return _AmountCardFrame(
      label: previousEstimate
          ? 'swapPreviousEstimate'.tr()
          : LocaleKeys.swapYouReceive.tr(),
      // Read as one phrase: the amount alone names neither the asset nor
      // its network, and a dash names nothing.
      amount: Semantics(
        container: true,
        label: _amountLabel(),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [amountText, const SizedBox(height: 6), _fiatLine(context)],
        ),
      ),
      assetPill: SwapAssetPill(
        asset: receive,
        network: network,
        onTap: onPickAsset,
        semanticLabel: LocaleKeys.swapYouReceive.tr(),
      ),
    );
  }

  /// Why there is no estimate: none asked for, one on its way, or none to
  /// be had. A completed failure must not keep promising an update; its
  /// reason and recovery action are below the cards.
  String _waitingText() {
    final hasIntent = state.inputText.trim().isNotEmpty && state.hasPair;
    if (!hasIntent) return 'swapEstimatePlaceholder'.tr();
    return swapAwaitingEstimate(state)
        ? 'swapEstimateUpdating'.tr()
        : LocaleKeys.swapPriceUnavailable.tr();
  }

  /// The difference from the market price as shown, or null when it rounds
  /// to nothing: that would read "−0% vs market".
  String? _vsMarket(SwapQuote quote) {
    final impact = quote.pricing.priceImpact;
    if (impact == null ||
        SwapFormat.percent(impact.abs()) == SwapFormat.percent(Decimal.zero)) {
      return null;
    }
    return LocaleKeys.swapVsMarket.tr(
      args: [
        '${impact > Decimal.zero ? '−' : '+'}'
            '${SwapFormat.percent(impact.abs())}',
      ],
    );
  }

  String _amountLabel() {
    final quote = state.selectedQuote;
    if (quote == null) return '${'swapA11yNoEstimate'.tr()}. ${_waitingText()}';
    final tokens = SwapFormat.tokens(
      quote.expectedReceive,
      SwapFormat.ticker(quote.to),
      rounding: SwapRounding.down,
    );
    final network = this.network;
    final amount = network == null
        ? tokens
        : SwapFormat.onNetwork(tokens, network);
    final usd = quote.pricing.expectedUsd;
    return [
      if (usd == null) ...[
        'swapA11yReceiveEstimate'.tr(args: [amount]),
        LocaleKeys.swapPriceUnavailable.tr(),
      ] else
        'swapA11yReceiveEstimateUsd'.tr(
          args: [
            amount,
            SwapFormat.usd(usd, rounding: SwapRounding.down),
          ],
        ),
      ?_vsMarket(quote),
      if (_expired) LocaleKeys.swapReviewExpiredBadge.tr(),
    ].join('. ');
  }

  Widget _fiatLine(BuildContext context) {
    final palette = SwapPalette.of(context);
    final quote = state.selectedQuote;
    if (quote == null) {
      return Text(_waitingText(), style: SwapText.small(context));
    }
    if (_expired) {
      return Text(
        LocaleKeys.swapReviewExpiredBadge.tr(),
        style: SwapText.small(context)
            .copyWith(color: palette.warning, fontWeight: FontWeight.w700),
      );
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
    final vsMarket = _vsMarket(quote);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          SwapFormat.usd(expected, rounding: SwapRounding.down),
          style: SwapText.small(context),
        ),
        if (vsMarket != null)
          Text(
            vsMarket,
            style: SwapText.small(context).copyWith(
              color: high ? palette.warning : palette.textTertiary,
              fontWeight: high ? FontWeight.w700 : null,
            ),
          ),
      ],
    );
  }
}
