part of 'swap_entry_view.dart';

/// What the form says under the cards: [alerts] to act on, shown first, and
/// standing [hints], shown where they move nothing as they change.
typedef _EntryLines = ({List<Widget> alerts, List<String> hints});

const _EntryLines _noLines = (alerts: <Widget>[], hints: <String>[]);

/// The lines under the cards, and the figures they quote.
extension _SwapEntryMessages on _SwapEntryViewState {
  /// An error, else warnings, else hints. With [stale], the selected option
  /// is one the open review has replaced, so nothing is said about it.
  _EntryLines _lines(UnifiedSwapState state, {required bool stale}) {
    final pay = state.pay;
    final issue = state.issue;
    // The button and the quote strip say what is being prepared.
    if (state.preparingAssets) return _noLines;
    if (state.preparationFailedAsset case final asset?) {
      return (
        alerts: [
          SwapHelperLine(
            text: 'swapAssetPreparationUnavailable'.tr(
              args: [SwapFormat.ticker(asset)],
            ),
            tone: SwapTone.warning,
          ),
        ],
        hints: const [],
      );
    }
    if (issue == SwapFormIssue.assetInactive) return _noLines;
    if (issue == SwapFormIssue.noOffers) {
      return (alerts: _noOffersLines(state), hints: const []);
    }
    if (issue != null && issue != SwapFormIssue.amountMissing) {
      final copy = SwapIssueCopy.of(
        issue,
        state,
        networks: _services.networks(),
        feeNeeded: _feeNeeded(state),
        feeHeld: _feeHeld(state),
        neededWithFees: _neededWithFees(state),
        neededForRefund:
            (_bloc.spendOf(state)?.refundReserve ?? Decimal.zero) >
            Decimal.zero,
        heldElsewhere: _heldElsewhere(state),
      );
      if (copy != null) {
        return (
          alerts: [
            SwapHelperLine(
              text: copy.message,
              tone: issue == SwapFormIssue.assetInactive
                  ? SwapTone.warning
                  : SwapTone.danger,
            ),
            if (copy.detail != null) SwapHelperLine(text: copy.detail!),
            // Still priced, so why no price came back matters too.
            if (issue.stillPriced) ..._failureLines(state),
          ],
          hints: const [],
        );
      }
    }

    if (state.fundingFailedAsset case final asset?) {
      return (
        alerts: [
          SwapHelperLine(
            text: 'swapFundingBalanceUnavailable'.tr(
              args: [SwapFormat.ticker(asset)],
            ),
            tone: SwapTone.warning,
          ),
        ],
        hints: const [],
      );
    }
    final failed = _failureLines(state);
    if (failed.isNotEmpty) return (alerts: failed, hints: const []);

    final quote = stale ? null : state.selectedQuote;
    final alerts = <Widget>[];
    if (state.structuralNotice) {
      alerts.add(
        SwapHelperLine(
          text: LocaleKeys.swapHelperStructural.tr(),
          tone: SwapTone.warning,
        ),
      );
    }
    final impact = quote?.pricing.priceImpact;
    if (impact != null && impact >= swapHighImpact) {
      alerts.add(
        SwapHelperLine(
          text: LocaleKeys.swapWarningHighImpact.tr(
            args: [SwapFormat.percent(impact)],
          ),
          tone: SwapTone.warning,
        ),
      );
    }
    final feeShare = quote?.pricing.feeShare;
    if (feeShare != null && feeShare >= swapHighFeeShare) {
      alerts.add(
        SwapHelperLine(
          text: LocaleKeys.swapWarningHighFees.tr(
            args: [SwapFormat.percent(feeShare)],
          ),
          tone: SwapTone.warning,
        ),
      );
    }
    final partial = stale ? null : _partialNote(state);
    final priced = partial != null
        ? [partial]
        : !state.signedIn && quote != null
        ? [LocaleKeys.swapHelperSignedOutPriced.tr()]
        : const <String>[];
    if (alerts.isNotEmpty || priced.isNotEmpty) {
      return (alerts: alerts, hints: priced);
    }

    final max = state.maxApplied;
    if (max != null && pay != null) {
      return (alerts: const [], hints: [_maxHint(max, pay)]);
    }
    if (quote != null && quote.pricing.expectedUsd == null) {
      return (
        alerts: const [],
        hints: [LocaleKeys.swapWarningPriceUnavailable.tr()],
      );
    }
    final range = _offerRange(state);
    // Signed out, "Checking what this wallet can swap" would name no wallet.
    if (!state.signedIn) {
      return (
        alerts: const [],
        hints: [?range, LocaleKeys.swapHelperSignedOut.tr()],
      );
    }
    if (state.loadingAssets) {
      return (
        alerts: const [],
        hints: [LocaleKeys.swapHelperLoadingAssets.tr()],
      );
    }
    return (alerts: const [], hints: [?range]);
  }

  SwapFailureCopy _failureCopy(
    UnifiedSwapState state,
    SwapQuoteFailure failure,
  ) => SwapFailureCopy.of(
    failure,
    state.pay,
    receive: state.receive,
    all: state.failures,
    support: state.pairSupport,
    networks: _services.networks(),
    amount: _bloc.amountOf(state),
    balance: state.signedIn ? state.balance : null,
    feeHeld: state.signedIn ? _feeHeld(state) : null,
  );

  List<Widget> _failureLines(UnifiedSwapState state) {
    final failure = state.failure;
    if (state.evaluation != SwapEvaluationStatus.failed || failure == null) {
      return const [];
    }
    final copy = _failureCopy(state, failure);
    // Cross-network prices have not answered yet, so an order-book miss is
    // not the final word.
    final paused =
        failure.source == SwapLiquiditySource.atomic &&
        state.failures.routesPaused;
    final tone = switch (failure.kind) {
      SwapQuoteFailureKind.rateLimited => SwapTone.warning,
      SwapQuoteFailureKind.signedOut => SwapTone.neutral,
      SwapQuoteFailureKind.noRoute ||
      SwapQuoteFailureKind.belowMinimum ||
      SwapQuoteFailureKind.aboveMaximum when paused => SwapTone.warning,
      _ => SwapTone.danger,
    };
    return [
      // A failed check is news whatever its tone.
      SwapHelperLine(text: copy.message, tone: tone, liveRegion: true),
      if (copy.detail != null)
        if (failure.reasons.isNotEmpty)
          SwapDetails(
            key: ValueKey((
              state.pay,
              state.receive,
              state.inputText,
              state.amountMode,
              failure,
            )),
            title: LocaleKeys.swapDetails.tr(),
            children: [SwapHelperLine(text: copy.detail!)],
          )
        else
          SwapHelperLine(text: copy.detail!),
      if (paused)
        SwapHelperLine(text: LocaleKeys.swapHelperRoutedPausedLine.tr()),
    ];
  }

  String? _partialNote(UnifiedSwapState state) {
    if (state.evaluation != SwapEvaluationStatus.ready) return null;
    final missing = state.failures
        .where((f) => f.isTransient || f.kind == SwapQuoteFailureKind.signedOut)
        .firstOrNull;
    if (missing == null) return null;
    if (missing.kind == SwapQuoteFailureKind.signedOut) {
      return LocaleKeys.swapHelperRoutedSignedOut.tr();
    }
    if (missing.source == SwapLiquiditySource.atomic) {
      return LocaleKeys.swapHelperAtomicUnavailable.tr();
    }
    return missing.kind == SwapQuoteFailureKind.rateLimited
        ? LocaleKeys.swapHelperRoutedPaused.tr()
        : LocaleKeys.swapHelperRoutedUnavailable.tr();
  }

  String _maxHint(SwapMaxAmount max, AssetId pay) {
    final ticker = SwapFormat.ticker(pay);
    final amount = SwapFormat.tokens(max.amount, ticker);
    if (max.offerLimit) return LocaleKeys.swapHelperMaxOffer.tr(args: [amount]);
    if (max.reservedForFees > Decimal.zero) {
      final feeTicker = max.feeAsset == null
          ? ticker
          : SwapFormat.ticker(max.feeAsset!);
      final key = switch (max.reserveCovers) {
        SwapMaxReserve.networkFees => LocaleKeys.swapHelperMaxNative,
        SwapMaxReserve.networkAndProviderFees =>
          LocaleKeys.swapHelperMaxNetworkAndProviderFees,
        SwapMaxReserve.providerFees => LocaleKeys.swapHelperMaxProviderFees,
        SwapMaxReserve.tradingFee => LocaleKeys.swapHelperMaxTradingFee,
        SwapMaxReserve.tradingAndNetworkFees =>
          LocaleKeys.swapHelperMaxTradingAndNetworkFees,
      };
      return key.tr(
        args: [
          amount,
          SwapFormat.tokens(
            max.reservedForFees,
            feeTicker,
            rounding: SwapRounding.up,
          ),
        ],
      );
    }
    final parent = pay.parentId;
    if (parent != null) {
      return LocaleKeys.swapHelperMaxToken.tr(
        args: [amount, SwapFormat.ticker(parent)],
      );
    }
    return LocaleKeys.swapHelperMaxWhole.tr(args: [amount]);
  }

  /// What screen readers hear when Max lands, without the figures.
  String _maxAnnouncement(SwapMaxAmount? max) {
    if (max != null && max.offerLimit) {
      return LocaleKeys.swapAnnounceMaxOffer.tr();
    }
    if (max == null || max.reservedForFees <= Decimal.zero) {
      return LocaleKeys.swapAnnounceWholeBalance.tr();
    }
    return switch (max.reserveCovers) {
      SwapMaxReserve.networkFees => LocaleKeys.swapAnnounceMax.tr(),
      SwapMaxReserve.networkAndProviderFees =>
        LocaleKeys.swapAnnounceMaxNetworkAndProviderFees.tr(),
      SwapMaxReserve.providerFees =>
        LocaleKeys.swapAnnounceMaxProviderFees.tr(),
      SwapMaxReserve.tradingFee => LocaleKeys.swapAnnounceMaxTradingFee.tr(),
      SwapMaxReserve.tradingAndNetworkFees =>
        LocaleKeys.swapAnnounceMaxTradingAndNetworkFees.tr(),
    };
  }

  String? _feeNeeded(UnifiedSwapState state) {
    final parent = state.insufficientFeeAsset;
    final quote = state.selectedQuote;
    if (parent == null || quote == null) return null;
    return SwapFormat.tokens(
      quote.fundingOnTopIn(parent),
      SwapFormat.ticker(parent),
      rounding: SwapRounding.up,
    );
  }

  /// The amount with its fees and refund gas on top, when the amount alone
  /// fits the balance and those are what it falls short by.
  String? _neededWithFees(UnifiedSwapState state) {
    final pay = state.pay;
    final balance = state.balance;
    final spend = _bloc.spendOf(state);
    if (pay == null || balance == null || spend == null) return null;
    final needed = spend.amount + spend.fees + spend.refundReserve;
    if (spend.amount > balance || needed <= balance) return null;
    return SwapFormat.tokens(
      needed,
      SwapFormat.ticker(pay),
      rounding: SwapRounding.up,
    );
  }

  String? _feeHeld(UnifiedSwapState state) {
    final parent = state.insufficientFeeAsset;
    final held = parent == state.pay?.parentId
        ? state.feeBalance
        : state.fundingBalances[parent];
    if (parent == null || held == null) return null;
    return SwapFormat.tokens(
      held,
      SwapFormat.ticker(parent),
      rounding: SwapRounding.down,
    );
  }

  String? _heldElsewhere(UnifiedSwapState state) {
    final pay = state.pay;
    if (pay == null || state.issue != SwapFormIssue.insufficient) return null;
    final held = _services.spendableElsewhere(pay);
    if (held == null || held <= Decimal.zero) return null;
    return SwapFormat.tokens(
      held,
      SwapFormat.ticker(pay),
      rounding: SwapRounding.down,
    );
  }
}
