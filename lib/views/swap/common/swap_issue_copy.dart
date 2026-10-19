part of 'swap_failure_copy.dart';

/// The entry form's message for a form issue.
class SwapIssueCopy {
  const SwapIssueCopy({
    required this.message,
    this.detail,
    this.action = SwapEntryAction.none,
  });

  final String message;
  final String? detail;
  final SwapEntryAction action;

  /// The copy for [issue] in [state], or null for "not finished yet": no
  /// amount, or no wallet. [neededWithFees] is the amount with the fees paid
  /// on top, when only those fees make it too much; [neededForRefund] says
  /// it also holds the gas to refund the swap if it fails. [heldElsewhere] is
  /// what the pay asset's other addresses hold.
  static SwapIssueCopy? of(
    SwapFormIssue issue,
    UnifiedSwapState state, {
    required SwapNetworks networks,
    String? feeNeeded,
    String? feeHeld,
    String? neededWithFees,
    bool neededForRefund = false,
    String? heldElsewhere,
  }) {
    final pay = state.pay;
    final ticker = pay == null ? '' : SwapFormat.ticker(pay);
    return switch (issue) {
      SwapFormIssue.amountMissing || SwapFormIssue.signedOut => null,
      SwapFormIssue.pairUnsupported => _pairUnsupported(
        state.pairSupport,
        networks,
      ),
      SwapFormIssue.noOffers => SwapIssueCopy(
        message: LocaleKeys.swapErrorNoOffers.tr(
          args: [
            if (state.receive case final receive?) SwapFormat.ticker(receive),
            ticker,
          ],
        ),
        action: SwapEntryAction.chooseAnother,
      ),
      SwapFormIssue.assetInactive => SwapIssueCopy(
        message: LocaleKeys.swapErrorInactive.tr(
          args: [SwapFormat.ticker(state.inactiveAsset ?? pay!)],
        ),
        action: SwapEntryAction.activate,
      ),
      SwapFormIssue.noFeeBalance => SwapIssueCopy(
        message: LocaleKeys.swapErrorNoFeeBalance.tr(
          args: [
            SwapFormat.ticker(pay!.parentId!),
            networks.networkOf(pay.parentId!),
          ],
        ),
      ),
      SwapFormIssue.amountMalformed => SwapIssueCopy(
        message: LocaleKeys.swapErrorMalformed.tr(),
      ),
      SwapFormIssue.amountZero => SwapIssueCopy(
        message: LocaleKeys.swapErrorZero.tr(),
      ),
      SwapFormIssue.tooManyDecimals => SwapIssueCopy(
        message: LocaleKeys.swapErrorTooManyDecimals.tr(
          args: [ticker, '${pay?.chainId.decimals ?? 8}'],
        ),
      ),
      SwapFormIssue.insufficient => SwapIssueCopy(
        message: _insufficient(
          state.balance,
          ticker,
          neededWithFees,
          forRefund: neededForRefund,
        ),
        detail: heldElsewhere == null
            ? null
            : LocaleKeys.swapHelperHeldElsewhere.tr(args: [heldElsewhere]),
      ),
      SwapFormIssue.insufficientForFees => SwapIssueCopy(
        message:
            (_providerFeesInParent(state)
                    ? LocaleKeys.swapErrorInsufficientForProviderFees
                    : LocaleKeys.swapErrorInsufficientForFees)
                .tr(args: [feeNeeded ?? '', feeHeld ?? '']),
      ),
      SwapFormIssue.sameAsset => SwapIssueCopy(
        message: LocaleKeys.swapErrorSameAsset.tr(),
        action: SwapEntryAction.chooseAnother,
      ),
      SwapFormIssue.fiatUnavailable => SwapIssueCopy(
        message: LocaleKeys.swapErrorFiatUnavailable.tr(args: [ticker, ticker]),
      ),
    };
  }

  static String _insufficient(
    Decimal? balance,
    String ticker,
    String? neededWithFees, {
    required bool forRefund,
  }) {
    if (balance == null) {
      return LocaleKeys.swapErrorInsufficient.tr(args: [ticker]);
    }
    final held = SwapFormat.tokens(
      balance,
      ticker,
      rounding: SwapRounding.down,
    );
    if (neededWithFees == null) {
      return LocaleKeys.swapErrorInsufficient.tr(args: [held]);
    }
    return (forRefund
            ? LocaleKeys.swapErrorInsufficientWithRefund
            : LocaleKeys.swapErrorInsufficientWithFees)
        .tr(args: [neededWithFees, held]);
  }

  static bool _providerFeesInParent(UnifiedSwapState state) {
    final parent = state.pay?.parentId;
    final quote = state.selectedQuote;
    if (parent == null || quote == null) return false;
    return quote
        .feesOnTopIn(parent)
        .any(
          (fee) =>
              fee.kind != SwapFeeKind.network &&
              fee.kind != SwapFeeKind.approvalNetwork,
        );
  }

  static SwapIssueCopy _pairUnsupported(
    SwapPairSupport? support,
    SwapNetworks networks,
  ) {
    final limiting = support?.limitingAsset;
    final routesOnly = support?.routesOnlyAsset;
    if (limiting == null) {
      return SwapIssueCopy(
        message: LocaleKeys.swapErrorPairUnsupported.tr(),
        action: SwapEntryAction.chooseAnother,
      );
    }
    if (support?.gap == SwapPairGap.notTradable || routesOnly == null) {
      return SwapIssueCopy(
        message: LocaleKeys.swapErrorNotTradable.tr(
          args: [SwapFormat.ticker(limiting)],
        ),
        action: SwapEntryAction.chooseAnother,
      );
    }
    return SwapIssueCopy(
      message: LocaleKeys.swapErrorPairDisjoint.tr(
        args: [SwapFormat.ticker(routesOnly), SwapFormat.ticker(limiting)],
      ),
      detail: routesReachDetail(limiting, networks),
      action: SwapEntryAction.chooseAnother,
    );
  }
}
