part of 'swap_review_view.dart';

class _Summary extends StatelessWidget {
  const _Summary({
    required this.quote,
    required this.fromNetwork,
    required this.toNetwork,
    required this.fromAddress,
    required this.toAddress,
  });

  final SwapQuote quote;
  final String fromNetwork;
  final String toNetwork;
  final String? fromAddress;
  final String? toAddress;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    Widget leg({
      required AssetId asset,
      required String label,
      required String amount,
      required String network,
      required String? address,
    }) {
      return MergeSemantics(
        child: Row(
          children: [
            SwapTokenIcon(asset: asset),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: SwapText.small(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    amount,
                    style: SwapText.strong(context).copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    address == null
                        ? network
                        : '$network · ${SwapFormat.short(address)}',
                    style: SwapText.small(
                      context,
                    ).copyWith(color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: LocaleKeys.swapReviewSummaryA11y.tr(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.controlBorder),
        ),
        child: Column(
          children: [
            leg(
              asset: quote.from,
              label: LocaleKeys.swapYouPay.tr(),
              amount: SwapFormat.tokens(
                quote.sellAmount,
                SwapFormat.ticker(quote.from),
              ),
              network: fromNetwork,
              address: fromAddress,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Divider(color: palette.border)),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: palette.selected,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 18,
                      color: palette.brandHover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: palette.border)),
                ],
              ),
            ),
            leg(
              asset: quote.to,
              label: LocaleKeys.swapYouReceive.tr(),
              amount: SwapFormat.tokens(
                quote.expectedReceive,
                SwapFormat.ticker(quote.to),
                rounding: SwapRounding.down,
              ),
              network: toNetwork,
              address: toAddress,
            ),
          ],
        ),
      ),
    );
  }
}

class _Protection extends StatelessWidget {
  const _Protection({required this.minimum});

  final String minimum;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.successBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.success),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.verified_user_outlined, color: palette.success),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    LocaleKeys.swapReviewAtLeast.tr(),
                    style: SwapText.body(context),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    minimum,
                    style: SwapText.strong(context).copyWith(fontSize: 17),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionGrid extends StatelessWidget {
  const _DecisionGrid({required this.quote});

  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final pricing = quote.pricing;
    final total = pricing.totalCostUsd;
    final network = pricing.networkCostUsd;
    final facts = [
      (
        LocaleKeys.swapTotalCost.tr(),
        total == null || !pricing.isComplete
            ? LocaleKeys.swapCostIncomplete.tr()
            : SwapFormat.usd(total, rounding: SwapRounding.up),
      ),
      (
        LocaleKeys.swapReviewEstimatedCompletion.tr(),
        SwapFormat.duration(quote.estimatedDuration),
      ),
      (
        LocaleKeys.swapReviewNetworkCost.tr(),
        network == null
            ? LocaleKeys.swapCostIncomplete.tr()
            : SwapFormat.usd(network, rounding: SwapRounding.up),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = constraints.maxWidth / scale < 300 ? 1 : 3;
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, value) in facts)
              SizedBox(
                width: width,
                child: MergeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: palette.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: SwapText.small(context)),
                        const SizedBox(height: 5),
                        Text(value, style: SwapText.strong(context)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Permission extends StatelessWidget {
  const _Permission({required this.quote});

  final SwapQuote quote;

  @override
  Widget build(BuildContext context) {
    final approval = quote.approval;
    final String title;
    final String body;
    if (approval == null) {
      title = LocaleKeys.swapPermissionNoneTitle.tr();
      body = LocaleKeys.swapPermissionNoneBody.tr();
    } else {
      final amount = SwapFormat.tokens(
        approval.exactAmount,
        SwapFormat.ticker(approval.asset),
      );
      title = approval.resetsFirst
          ? LocaleKeys.swapPermissionResetTitle.tr()
          : LocaleKeys.swapPermissionExactTitle.tr();
      body = approval.resetsFirst
          ? LocaleKeys.swapPermissionResetBody.tr(args: [amount])
          : LocaleKeys.swapPermissionExactBody.tr(args: [amount]);
    }
    return SwapCallout(
      tone: SwapTone.info,
      icon: Icons.shield_outlined,
      title: title,
      message: body,
    );
  }
}

/// The routing provider's terms, presented on a wallet's first routed swap.
/// Starting the swap is the acceptance; the link only opens the document.
class _TermsNotice extends StatelessWidget {
  const _TermsNotice();

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final style = SwapText.small(
      context,
    ).copyWith(color: palette.textSecondary, height: 1.5);
    final linkLabel = LocaleKeys.swapTermsLinkLabel.tr(
      args: [SwapTermsRepository.provider],
    );
    final sentence = LocaleKeys.swapTermsNotice.tr(
      namedArgs: {'terms': '{terms}', 'provider': SwapTermsRepository.provider},
    );
    final spans = <InlineSpan>[];
    sentence.splitMapJoin(
      '{terms}',
      onMatch: (_) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: MediaQuery.withNoTextScaling(
              child: Semantics(
                link: true,
                child: InkWell(
                  key: const Key('swap-terms-link'),
                  onTap: () => launchURLString(SwapTermsRepository.termsUrl),
                  // WidgetSpan scales its child with the paragraph already.
                  child: Text(
                    linkLabel,
                    style: style.copyWith(
                      color: palette.brandHover,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return '';
      },
      onNonMatch: (text) {
        spans.add(TextSpan(text: text));
        return '';
      },
    );
    return Text.rich(TextSpan(style: style, children: spans));
  }
}

class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({required this.review});

  final SwapReview review;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<UnifiedSwapBloc>();
    void start() => bloc.add(const UnifiedSwapStartRequested());
    final quote = review.quote;

    return switch (review.status) {
      SwapReviewStatus.ready => SwapButton(
        key: const Key('swap-start'),
        label: _startLabel(quote),
        onPressed: start,
      ),
      SwapReviewStatus.materialUpdate => SwapButton(
        key: const Key('swap-start'),
        label: LocaleKeys.swapAcceptUpdated.tr(),
        onPressed: start,
      ),
      SwapReviewStatus.expired => SwapButton(
        label: LocaleKeys.swapCtaRefresh.tr(),
        onPressed: start,
      ),
      SwapReviewStatus.revalidationFailed || SwapReviewStatus.rejected =>
        SwapButton(label: LocaleKeys.tryAgain.tr(), onPressed: start),
      SwapReviewStatus.revalidating => SwapButton(
        label: LocaleKeys.swapCtaChecking.tr(),
        onPressed: null,
        busy: true,
      ),
      SwapReviewStatus.starting => SwapButton(
        label: _startLabel(quote),
        onPressed: null,
        busy: true,
      ),
      // The swap may be running. Another start could swap twice, so the only
      // way forward is to look.
      SwapReviewStatus.unconfirmed => SwapButton(
        label: LocaleKeys.swapViewInActivity.tr(),
        onPressed: () {
          bloc.add(const UnifiedSwapResetRequested());
          SwapShellScope.of(context).showActivity();
        },
      ),
    };
  }

  static String _startLabel(SwapQuote quote) {
    final approval = quote.approval;
    if (approval == null) return LocaleKeys.swapStartSwap.tr();
    if (approval.resetsFirst) return LocaleKeys.swapStartReset.tr();
    return LocaleKeys.swapStartApprove.tr(
      args: [
        SwapFormat.tokens(
          approval.exactAmount,
          SwapFormat.ticker(approval.asset),
        ),
      ],
    );
  }
}
