part of 'swap_review_view.dart';

/// The review's detail sections: costs, route and identities, warnings and
/// the status of the latest re-price.
extension _ReviewContentDetails on _ReviewContent {
  String _usdOrTokens(Decimal? usd, Iterable<SwapFeeComponent> fees) {
    if (usd != null) return SwapFormat.usd(usd, rounding: SwapRounding.up);
    final byToken = <String, Decimal>{};
    for (final fee in fees) {
      final label = fee.tokenLabel;
      byToken[label] = (byToken[label] ?? Decimal.zero) + fee.amount;
    }
    if (byToken.isEmpty) return SwapFormat.usd(Decimal.zero);
    return byToken.entries
        .map(
          (e) => SwapFormat.tokens(e.value, e.key, rounding: SwapRounding.up),
        )
        .join(' + ');
  }

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
    final network = quote.fees.where(
      (f) =>
          f.kind == SwapFeeKind.network ||
          f.kind == SwapFeeKind.approvalNetwork,
    );
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
          value: _usdOrTokens(pricing.networkCostUsd, network),
        ),
        if (approval.isNotEmpty)
          SwapDetailRow(
            label: LocaleKeys.swapApprovalNetworkCost.tr(),
            value: _usdOrTokens(pricing.approvalNetworkCostUsd, approval),
          ),
        SwapDetailRow(
          label: LocaleKeys.swapSwapCosts.tr(),
          value: _usdOrTokens(pricing.swapCostUsd, swap),
        ),
        if (inReceive.isNotEmpty)
          SwapDetailRow(
            label: LocaleKeys.swapReviewTakenFromReceive.tr(),
            value: _usdOrTokens(_pricedTotal(inReceive), inReceive),
          ),
        SwapDetailRow(
          label: LocaleKeys.swapReviewSlippage.tr(),
          value: quote.source == SwapLiquiditySource.atomic || slippage == null
              ? LocaleKeys.swapReviewSlippageNone.tr()
              : SwapFormat.percent(Decimal.parse(slippage.toString())),
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

  List<Widget> _status(BuildContext context) {
    final toTicker = SwapFormat.ticker(quote.to);
    switch (review.status) {
      case SwapReviewStatus.materialUpdate:
        final previous = review.previous;
        final lines = <String>[];
        if (previous != null) {
          if (previous.guaranteedReceive != quote.guaranteedReceive) {
            final (was, now) = SwapFormat.tokensApart(
              previous.guaranteedReceive,
              quote.guaranteedReceive,
              toTicker,
              rounding: SwapRounding.down,
            );
            lines.add(LocaleKeys.swapReviewUpdatedMinimum.tr(args: [was, now]));
          }
          final before = previous.pricing.totalCostUsd;
          final after = quote.pricing.totalCostUsd;
          if (before != null && after != null) {
            final was = SwapFormat.usd(before, rounding: SwapRounding.up);
            final now = SwapFormat.usd(after, rounding: SwapRounding.up);
            // Cents are the finest a cost is worth showing: a smaller change
            // would read "from $0.54 to $0.54".
            if (was != now) {
              lines.add(LocaleKeys.swapReviewUpdatedCost.tr(args: [was, now]));
            }
          }
        }
        return [
          const SizedBox(height: 12),
          SwapCallout(
            tone: SwapTone.warning,
            icon: Icons.refresh_rounded,
            title: LocaleKeys.swapReviewUpdatedTitle.tr(),
            message: lines.join(' '),
            liveRegion: true,
          ),
        ];
      case SwapReviewStatus.expired:
        return [
          const SizedBox(height: 12),
          SwapCallout(
            tone: SwapTone.warning,
            icon: Icons.timer_outlined,
            title: LocaleKeys.swapReviewExpiredTitle.tr(),
            message: LocaleKeys.swapReviewExpiredBody.tr(),
            liveRegion: true,
          ),
        ];
      case SwapReviewStatus.revalidating:
        return [
          SwapHelperLine(text: LocaleKeys.swapReviewRevalidatingBody.tr()),
        ];
      case SwapReviewStatus.revalidationFailed:
        final (title, message) = switch (review.revalidationRecovery) {
          SwapRevalidationRecovery.waitForSource => (
            LocaleKeys.swapReviewPausedTitle.tr(),
            LocaleKeys.swapReviewPausedBody.tr(),
          ),
          SwapRevalidationRecovery.backToForm =>
            switch (review.revalidationFailure?.kind) {
              SwapQuoteFailureKind.noRoute ||
              SwapQuoteFailureKind.belowMinimum ||
              SwapQuoteFailureKind.aboveMaximum ||
              SwapQuoteFailureKind.pairUnsupported => (
                LocaleKeys.swapReviewGoneTitle.tr(),
                LocaleKeys.swapReviewGoneBody.tr(),
              ),
              _ => (
                LocaleKeys.swapReviewChangedTitle.tr(),
                LocaleKeys.swapReviewChangedBody.tr(),
              ),
            },
          SwapRevalidationRecovery.tryAgain => (
            LocaleKeys.swapReviewFailedTitle.tr(),
            LocaleKeys.swapReviewFailedBody.tr(),
          ),
        };
        return [
          const SizedBox(height: 12),
          SwapCallout(
            tone: SwapTone.warning,
            title: title,
            message: message,
            liveRegion: true,
          ),
        ];
      case SwapReviewStatus.rejected:
        return [
          const SizedBox(height: 12),
          SwapCallout(
            tone: SwapTone.danger,
            title: LocaleKeys.swapReviewRejectedTitle.tr(),
            message: LocaleKeys.swapReviewRejectedBody.tr(),
            liveRegion: true,
          ),
        ];
      case SwapReviewStatus.unconfirmed:
        return [
          const SizedBox(height: 12),
          SwapCallout(
            tone: SwapTone.warning,
            title: LocaleKeys.swapReviewUnconfirmedTitle.tr(),
            message: LocaleKeys.swapReviewUnconfirmedBody.tr(),
            liveRegion: true,
          ),
        ];
      case SwapReviewStatus.ready || SwapReviewStatus.starting:
        return const [];
    }
  }
}
