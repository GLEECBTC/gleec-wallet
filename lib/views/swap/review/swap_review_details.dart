part of 'swap_review_view.dart';

/// What stands in for a cost the engine could not read. Never "free".
const _costUnknown = '—';

/// A cost as the review writes it: in dollars when [usd] prices it, else as
/// its own token amounts, and [_costUnknown] when the fees were not read.
String _costText(
  SwapQuote quote,
  Decimal? usd,
  Iterable<SwapFeeComponent> fees,
) {
  if (!quote.feesKnown) return _costUnknown;
  if (usd != null) return SwapFormat.usd(usd, rounding: SwapRounding.up);
  return _feeTokens(fees);
}

/// [fees] summed per token: "0.0004 ETH + 0.1 GLEEC".
String _feeTokens(Iterable<SwapFeeComponent> fees) {
  final byToken = <String, Decimal>{};
  for (final fee in fees) {
    final label = fee.tokenLabel;
    byToken[label] = (byToken[label] ?? Decimal.zero) + fee.amount;
  }
  if (byToken.isEmpty) return SwapFormat.usd(Decimal.zero);
  return byToken.entries
      .map((e) => SwapFormat.tokens(e.value, e.key, rounding: SwapRounding.up))
      .join(' + ');
}

/// The gas [quote] pays, its approval's included.
Iterable<SwapFeeComponent> _networkFees(SwapQuote quote) => quote.fees.where(
  (f) => f.kind == SwapFeeKind.network || f.kind == SwapFeeKind.approvalNetwork,
);

/// The review's detail sections: costs, route and identities, and warnings.
extension _ReviewContentDetails on _ReviewContent {
  /// The USD total of [fees], or null when any is unpriced.
  Decimal? _pricedTotal(Iterable<SwapFeeComponent> fees) {
    var total = Decimal.zero;
    for (final fee in fees) {
      final usd = fee.usdValue;
      if (usd == null) return null;
      total += usd;
    }
    return total;
  }

  Widget _costs(BuildContext context) {
    final pricing = quote.pricing;
    final network = _networkFees(quote);
    final approval = quote.feesOf(SwapFeeKind.approvalNetwork);
    final swap = quote.fees.where(
      (f) => f.kind == SwapFeeKind.swap || f.kind == SwapFeeKind.dexFee,
    );
    final inReceive = quote.feesInReceive.toList();
    final slippage = quote.slippage;
    return SwapDetails(
      title: LocaleKeys.swapReviewCostsProtection.tr(),
      children: [
        SwapDetailRow(
          label: LocaleKeys.swapNetworkCosts.tr(),
          value: _costText(quote, pricing.networkCostUsd, network),
        ),
        // Already counted in the network costs above.
        if (approval.isNotEmpty)
          SwapDetailRow(
            label: '↳ ${LocaleKeys.swapApprovalNetworkCost.tr()}',
            value: _costText(quote, pricing.approvalNetworkCostUsd, approval),
          ),
        SwapDetailRow(
          label: LocaleKeys.swapSwapCosts.tr(),
          value: _costText(quote, pricing.swapCostUsd, swap),
        ),
        if (inReceive.isNotEmpty)
          SwapDetailRow(
            label: LocaleKeys.swapReviewTakenFromReceive.tr(),
            value: _costText(quote, _pricedTotal(inReceive), inReceive),
          ),
        SwapDetailRow(
          label: LocaleKeys.swapReviewSlippage.tr(),
          value: quote.source == SwapLiquiditySource.atomic || slippage == null
              ? LocaleKeys.swapReviewSlippageNone.tr()
              : slippageText(slippage),
        ),
        SwapDetailRow(
          label: LocaleKeys.swapReviewMinimumGuard.tr(),
          value: LocaleKeys.swapReviewMinimumGuardValue.tr(),
        ),
      ],
    );
  }

  Widget _identity(
    BuildContext context,
    AssetId asset,
    String ticker,
    String network,
    String label,
  ) {
    final contract = services.contractOf(asset);
    if (contract == null) {
      return SwapDetailRow(
        label: label,
        value: LocaleKeys.swapNativeIdentity.tr(args: [ticker, network]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label · $ticker · $network', style: SwapText.body(context)),
          SwapCopyLine(value: contract, label: label),
        ],
      ),
    );
  }

  Widget _routeAndIdentities(
    BuildContext context, {
    required String? fromAddress,
    required String? toAddress,
    required String fromTicker,
    required String toTicker,
    required String fromNetwork,
    required String toNetwork,
  }) {
    final steps = SwapTimeline.describe(quote, networks);
    return SwapDetails(
      title: LocaleKeys.swapReviewRouteIdentities.tr(),
      children: [
        SwapDetailRow(
          label: LocaleKeys.swapReviewHowItCompletes.tr(),
          value: steps.isEmpty
              ? _routeKind(quote.routeKind)
              : steps.join(' → '),
        ),
        if (fromAddress != null) ...[
          const SizedBox(height: 6),
          Text(
            LocaleKeys.swapReviewSourceAddress.tr(),
            style: SwapText.body(context),
          ),
          SwapCopyLine(
            value: fromAddress,
            label: LocaleKeys.swapReviewSourceAddress.tr(),
            payableIn: quote.from,
          ),
        ],
        if (toAddress != null) ...[
          const SizedBox(height: 6),
          Text(
            LocaleKeys.swapReviewRecipientAddress.tr(),
            style: SwapText.body(context),
          ),
          SwapCopyLine(
            value: toAddress,
            label: LocaleKeys.swapReviewRecipientAddress.tr(),
            payableIn: quote.to,
          ),
        ],
        _identity(
          context,
          quote.from,
          fromTicker,
          fromNetwork,
          LocaleKeys.swapReviewSourceIdentity.tr(),
        ),
        _identity(
          context,
          quote.to,
          toTicker,
          toNetwork,
          LocaleKeys.swapReviewDestinationIdentity.tr(),
        ),
      ],
    );
  }

  static String _routeKind(SwapRouteKind kind) => switch (kind) {
    SwapRouteKind.direct => LocaleKeys.swapRouteDirect.tr(),
    SwapRouteKind.sameChain => LocaleKeys.swapRouteSameChain.tr(),
    SwapRouteKind.crossChain => LocaleKeys.swapRouteCrossChain.tr(),
  };

  List<Widget> _warnings(BuildContext context, Decimal? impact) {
    final feeShare = quote.pricing.feeShare;
    final multiStep =
        quote.routeKind == SwapRouteKind.crossChain ||
        quote.stages
                .where(
                  (s) =>
                      s.kind == SwapRouteStageKind.bridge ||
                      s.kind == SwapRouteStageKind.convert ||
                      s.kind == SwapRouteStageKind.exchange,
                )
                .length >
            1;
    return [
      if (multiStep) ...[
        const SizedBox(height: 12),
        SwapCallout(
          tone: SwapTone.warning,
          title: LocaleKeys.swapMultiStepTitle.tr(),
          message: LocaleKeys.swapMultiStepBody.tr(),
        ),
      ],
      if (impact != null && impact >= swapHighImpact) ...[
        const SizedBox(height: 12),
        SwapCallout(
          tone: SwapTone.warning,
          icon: Icons.trending_down_rounded,
          title: LocaleKeys.swapReviewHighImpactTitle.tr(),
          message: LocaleKeys.swapReviewHighImpactBody.tr(),
        ),
      ],
      if (feeShare != null && feeShare >= swapHighFeeShare) ...[
        const SizedBox(height: 12),
        SwapCallout(
          tone: SwapTone.warning,
          icon: Icons.receipt_long_rounded,
          title: LocaleKeys.swapReviewHighFeesTitle.tr(),
          message: LocaleKeys.swapReviewHighFeesBody.tr(
            args: [SwapFormat.percent(feeShare)],
          ),
        ),
      ],
      if (quote.pricing.expectedUsd == null) ...[
        const SizedBox(height: 12),
        SwapCallout(
          tone: SwapTone.info,
          title: LocaleKeys.swapReviewPriceUnavailableTitle.tr(),
          message: LocaleKeys.swapReviewPriceUnavailableBody.tr(),
        ),
      ],
    ];
  }
}
