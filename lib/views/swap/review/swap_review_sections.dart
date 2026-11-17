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
    void showRecipient() {
      final services = context.read<SwapServices>();
      final auth = context.read<AuthBloc>();
      showSwapSheet<void>(
        context: context,
        label: LocaleKeys.swapReviewRecipientAddress.tr(),
        fitContent: true,
        builder: (_) => RepositoryProvider<SwapServices>.value(
          value: services,
          child: BlocProvider<AuthBloc>.value(
            value: auth,
            child: SwapSheetScaffold(
              title: LocaleKeys.swapReviewRecipientAddress.tr(),
              body: SwapCopyLine(
                value: toAddress!,
                label: LocaleKeys.swapReviewRecipientAddress.tr(),
                payableIn: quote.to,
              ),
            ),
          ),
        ),
      );
    }

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
                    style: SwapText.small(context)
                        .copyWith(fontWeight: FontWeight.w700),
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
                    style: SwapText.small(context)
                        .copyWith(color: palette.textSecondary),
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
        padding: const EdgeInsets.all(14),
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
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Divider(color: palette.border)),
                  const SizedBox(width: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: palette.selected,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
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
            const SizedBox(height: 10),
            _Protection(
              minimum: SwapFormat.tokens(
                quote.guaranteedReceive,
                SwapFormat.ticker(quote.to),
                rounding: SwapRounding.down,
              ),
            ),
            if (toAddress != null)
              SwapLinkButton(
                label: 'swapReviewYourWallet'.tr(
                  args: [SwapFormat.short(toAddress!)],
                ),
                icon: Icons.account_balance_wallet_outlined,
                onPressed: showRecipient,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: palette.successBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.verified_user_outlined,
              color: palette.success,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    LocaleKeys.swapReviewAtLeast.tr(),
                    style: SwapText.small(context),
                  ),
                  Text(
                    minimum,
                    style: SwapText.strong(context).copyWith(fontSize: 14),
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
    final pricing = quote.pricing;
    final total = pricing.totalCostUsd;
    final network = pricing.networkCostUsd;
    final facts = [
      for (final entry in quote.requiredFeeBalances.entries)
        if (entry.value > Decimal.zero)
          (
            'swapReviewRequiredFunding'.tr(
              args: [SwapFormat.ticker(entry.key)],
            ),
            SwapFormat.tokens(
              entry.value,
              SwapFormat.ticker(entry.key),
              rounding: SwapRounding.up,
            ),
          ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in facts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(label, style: SwapText.small(context))),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: SwapText.strong(context).copyWith(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (quote.requiredFeeBalances.isNotEmpty)
          SwapHelperLine(
            text: 'swapReviewRequiredFundingExplanation'.tr(),
            tone: SwapTone.neutral,
          ),
        if (quote.source == SwapLiquiditySource.atomic)
          SwapHelperLine(
            text: 'swapReviewPeerToPeer'.tr(),
            tone: SwapTone.neutral,
          ),
      ],
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
    if (quote.hasUnverifiedAtomicApproval) {
      title = LocaleKeys.swapPermissionAtomicTitle.tr();
      body = LocaleKeys.swapPermissionAtomicBody.tr();
    } else if (approval == null) {
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
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 18,
            color: SwapPalette.of(context).info,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SwapText.small(context)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(body, style: SwapText.small(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({
    required this.review,
    required this.tradingEnabled,
    required this.tradingStatusLoading,
    required this.tradingStatusUnavailable,
    required this.hardwareWallet,
    this.paused = false,
  });

  final SwapReview review;
  final bool paused;
  final bool tradingEnabled;
  final bool tradingStatusLoading;
  final bool tradingStatusUnavailable;
  final bool hardwareWallet;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<UnifiedSwapBloc>();
    void start() => bloc.add(const UnifiedSwapStartRequested());
    // Committing funds gets a firm tap on phones; retries do not.
    void commit() {
      SwapHaptics.medium();
      start();
    }

    final quote = review.quote;

    if (!tradingEnabled &&
        review.status != SwapReviewStatus.starting &&
        review.status != SwapReviewStatus.unconfirmed) {
      final retry =
          !hardwareWallet && !tradingStatusLoading && tradingStatusUnavailable;
      return SwapButton(
        key: const Key('swap-start'),
        label: hardwareWallet
            ? LocaleKeys.swapCtaUnavailable.tr()
            : tradingStatusLoading
            ? 'swapAvailabilityChecking'.tr()
            : retry
            ? LocaleKeys.tryAgain.tr()
            : LocaleKeys.tradingDisabled.tr(),
        onPressed: retry
            ? () => context.read<TradingStatusBloc>().add(
                TradingStatusCheckRequested(),
              )
            : null,
        busy: !hardwareWallet && tradingStatusLoading,
      );
    }

    final action = switch (review.status) {
      SwapReviewStatus.ready => SwapButton(
        key: const Key('swap-start'),
        label: _startLabel(quote),
        onPressed: review.legalAllowed ? commit : null,
      ),
      SwapReviewStatus.materialUpdate => SwapButton(
        key: const Key('swap-start'),
        label: LocaleKeys.swapAcceptUpdated.tr(),
        onPressed: review.legalAllowed ? commit : null,
      ),
      SwapReviewStatus.expired => SwapButton(
        label: LocaleKeys.swapCtaRefresh.tr(),
        onPressed: start,
      ),
      SwapReviewStatus.revalidationFailed =>
        switch (review.revalidationRecovery) {
          SwapRevalidationRecovery.backToForm => SwapButton(
            label: LocaleKeys.swapCtaBackToSwap.tr(),
            onPressed: () => bloc.add(const UnifiedSwapReviewClosed()),
          ),
          SwapRevalidationRecovery.waitForSource => SwapButton(
            label: LocaleKeys.tryAgain.tr(),
            onPressed: paused ? null : start,
          ),
          SwapRevalidationRecovery.tryAgain => SwapButton(
            label: LocaleKeys.tryAgain.tr(),
            onPressed: start,
          ),
        },
      SwapReviewStatus.rejected => SwapButton(
        label: LocaleKeys.tryAgain.tr(),
        onPressed: start,
      ),
      // Keyed like Start, so one button carries on through its checks.
      SwapReviewStatus.revalidating => SwapButton(
        key: const Key('swap-start'),
        label: LocaleKeys.swapCtaChecking.tr(),
        onPressed: null,
        busy: true,
      ),
      SwapReviewStatus.starting => SwapButton(
        key: const Key('swap-start'),
        label: LocaleKeys.swapCtaStarting.tr(),
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
    return LegalActionTooltip(allowed: review.legalAllowed, child: action);
  }

  static String _startLabel(SwapQuote quote) {
    final approval = quote.approval;
    if (approval == null) return 'swapConfirmSwap'.tr();
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
