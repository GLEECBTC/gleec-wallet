part of 'swap_entry_view.dart';

/// The lines under the cards, and the figures they quote.
extension _SwapEntryMessages on _SwapEntryViewState {
  /// One line under the cards: an error, else a warning, else a hint.
  List<Widget> _messages(BuildContext context, UnifiedSwapState state) {
    final pay = state.pay;
    final issue = state.issue;
    if (issue != null && issue != SwapFormIssue.amountMissing) {
      final copy = SwapIssueCopy.of(
        issue,
        state,
        networks: _services.networks(),
        feeNeeded: _feeNeeded(state),
        feeHeld: _feeHeld(state),
      );
      if (copy != null) {
        return [
          SwapHelperLine(
            text: copy.message,
            tone: issue == SwapFormIssue.assetInactive
                ? SwapTone.warning
                : SwapTone.danger,
          ),
          if (copy.detail != null) SwapHelperLine(text: copy.detail!),
          // Still priced, so why no price came back matters too.
          if (issue.stillPriced) ..._failureLines(state),
        ];
      }
    }

    final failed = _failureLines(state);
    if (failed.isNotEmpty) return failed;

    final partial = _partialNote(state);

    final messages = <Widget>[];
    if (state.structuralNotice) {
      messages.add(
        SwapHelperLine(
          text: LocaleKeys.swapHelperStructural.tr(),
          tone: SwapTone.warning,
        ),
      );
    }
    final quote = state.selectedQuote;
    final impact = quote?.pricing.priceImpact;
    if (impact != null && impact >= swapHighImpact) {
      messages.add(
        SwapHelperLine(
          text: LocaleKeys.swapWarningHighImpact.tr(
            args: [SwapFormat.percent(impact)],
          ),
          tone: SwapTone.warning,
        ),
      );
    }
    if (partial != null) messages.add(SwapHelperLine(text: partial));
    if (messages.isNotEmpty) return messages;

    if (state.evaluation == SwapEvaluationStatus.checking) {
      return [SwapHelperLine(text: LocaleKeys.swapHelperChecking.tr())];
    }
    final max = state.maxApplied;
    if (max != null && pay != null) {
      return [SwapHelperLine(text: _maxHint(max, pay))];
    }
    if (quote != null && quote.pricing.expectedUsd == null) {
      return [
        SwapHelperLine(text: LocaleKeys.swapWarningPriceUnavailable.tr()),
      ];
    }
    if (state.loadingAssets) {
      return [SwapHelperLine(text: LocaleKeys.swapHelperLoadingAssets.tr())];
    }
    return const [];
  }

  SwapFailureCopy _failureCopy(
    UnifiedSwapState state,
    SwapQuoteFailure failure,
  ) => SwapFailureCopy.of(
    failure,
    state.pay,
    all: state.failures,
    support: state.pairSupport,
    networks: _services.networks(),
  );

  List<Widget> _failureLines(UnifiedSwapState state) {
    final failure = state.failure;
    if (state.evaluation != SwapEvaluationStatus.failed || failure == null) {
      return const [];
    }
    final copy = _failureCopy(state, failure);
    final tone = failure.kind == SwapQuoteFailureKind.rateLimited
        ? SwapTone.warning
        : SwapTone.danger;
    return [
      SwapHelperLine(text: copy.message, tone: tone),
      if (copy.detail != null) SwapHelperLine(text: copy.detail!),
    ];
  }

  String? _partialNote(UnifiedSwapState state) {
    if (state.evaluation != SwapEvaluationStatus.ready) return null;
    final missing = state.failures.where((f) => f.isTransient).firstOrNull;
    if (missing == null) return null;
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
    if (max.reservedForFees > Decimal.zero) {
      final feeTicker = max.feeAsset == null
          ? ticker
          : SwapFormat.ticker(max.feeAsset!);
      return LocaleKeys.swapHelperMaxNative.tr(
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
    return LocaleKeys.swapHelperMaxAtomic.tr(args: [amount]);
  }

  String? _feeNeeded(UnifiedSwapState state) {
    final parent = state.pay?.parentId;
    final quote = state.selectedQuote;
    if (parent == null || quote == null) return null;
    var total = Decimal.zero;
    for (final fee in quote.fees) {
      if (fee.asset == parent && !fee.deductedFromReceive) total += fee.amount;
    }
    return SwapFormat.tokens(
      total,
      SwapFormat.ticker(parent),
      rounding: SwapRounding.up,
    );
  }

  String? _feeHeld(UnifiedSwapState state) {
    final parent = state.pay?.parentId;
    final held = state.feeBalance;
    if (parent == null || held == null) return null;
    return SwapFormat.tokens(
      held,
      SwapFormat.ticker(parent),
      rounding: SwapRounding.down,
    );
  }
}
