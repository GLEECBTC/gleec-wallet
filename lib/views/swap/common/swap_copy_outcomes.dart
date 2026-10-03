part of 'swap_copy.dart';

/// How a finished swap is headlined, by outcome and failure reason.
extension _SwapOutcomeCopy on SwapExecutionCopy {
  SwapHeroCopy _outcomeHero(SwapExecutionOutcome outcome) {
    switch (outcome.kind) {
      case SwapOutcomeKind.completed:
        return SwapHeroCopy(
          title: LocaleKeys.swapOutcomeCompletedTitle.tr(args: [_received]),
          body: _receivedWhere,
          icon: Icons.check_circle_outline_rounded,
          tone: SwapTone.success,
        );
      case SwapOutcomeKind.partialBelowMinimum:
        final minimum = snapshot.minimumReceive;
        return SwapHeroCopy(
          title: LocaleKeys.swapOutcomeBelowMinimumTitle.tr(),
          body: LocaleKeys.swapOutcomeBelowMinimumBody.tr(
            args: [
              _received,
              if (minimum == null)
                toTicker
              else
                SwapFormat.tokens(
                  minimum,
                  toTicker,
                  rounding: SwapRounding.down,
                ),
            ],
          ),
          icon: Icons.trending_down_rounded,
          tone: SwapTone.warning,
        );
      case SwapOutcomeKind.partialOtherToken:
        return SwapHeroCopy(
          title: LocaleKeys.swapOutcomeOtherTokenTitle.tr(),
          body: LocaleKeys.swapOutcomeOtherTokenBody.tr(
            args: [_received, toTicker],
          ),
          icon: Icons.currency_exchange_rounded,
          tone: SwapTone.warning,
        );
      case SwapOutcomeKind.refunded:
        return SwapHeroCopy(
          title: LocaleKeys.swapOutcomeRefundedTitle.tr(),
          body: LocaleKeys.swapOutcomeRefundedBody.tr(
            args: [fromTicker, fromNetwork],
          ),
          icon: Icons.undo_rounded,
          tone: SwapTone.success,
        );
      case SwapOutcomeKind.cancelled:
        return SwapHeroCopy(
          title: LocaleKeys.swapOutcomeCancelledTitle.tr(),
          body: snapshot.approvalRemains
              ? LocaleKeys.swapOutcomeCancelledApprovalBody.tr(
                  args: [_approvalAmount],
                )
              : LocaleKeys.swapOutcomeCancelledBody.tr(),
          icon: Icons.cancel_outlined,
          tone: snapshot.approvalRemains ? SwapTone.warning : SwapTone.neutral,
        );
      case SwapOutcomeKind.noMatch:
        return SwapHeroCopy(
          title: LocaleKeys.swapOutcomeNoMatchTitle.tr(),
          body: LocaleKeys.swapOutcomeNoMatchBody.tr(),
          icon: Icons.person_search_outlined,
          tone: SwapTone.neutral,
        );
      case SwapOutcomeKind.failed:
        return _failureHero(outcome.failure);
    }
  }

  String get _receivedWhere {
    final address = snapshot.toAddress;
    return address == null
        ? LocaleKeys.swapOutcomeCompletedBodyNetwork.tr(args: [toNetwork])
        : LocaleKeys.swapOutcomeCompletedBody.tr(
            args: [SwapFormat.short(address), toNetwork],
          );
  }

  bool get _nothingSent => _movement == SwapFundsMovement.none;

  String _unlessMoved(String safe) => switch (_movement) {
    SwapFundsMovement.none => safe,
    SwapFundsMovement.feesOnly => LocaleKeys.swapFailFeesOnlyBody.tr(
      args: [fromTicker],
    ),
    SwapFundsMovement.uncertain ||
    SwapFundsMovement.sent => LocaleKeys.swapFailUncertainBody.tr(),
  };

  SwapHeroCopy _failureHero(SwapExecutionFailure? failure) {
    final reason = failure?.reason ?? SwapFailureReason.unknown;
    final uncertain =
        snapshot.fundsMovement == SwapFundsMovement.uncertain ||
        snapshot.fundsMovement == SwapFundsMovement.sent;

    return switch (reason) {
      SwapFailureReason.priceMoved => SwapHeroCopy(
        title: LocaleKeys.swapFailPriceMovedTitle.tr(),
        body: LocaleKeys.swapFailPriceMovedBody.tr(),
        icon: Icons.show_chart_rounded,
        tone: SwapTone.warning,
      ),
      SwapFailureReason.insufficientBalance => SwapHeroCopy(
        title: LocaleKeys.swapFailBalanceTitle.tr(),
        body: _shortfallBody(failure),
        icon: Icons.account_balance_wallet_outlined,
        tone: SwapTone.warning,
      ),
      SwapFailureReason.approvalFailed => SwapHeroCopy(
        title: LocaleKeys.swapFailApprovalTitle.tr(),
        body: LocaleKeys.swapFailApprovalBody.tr(),
        icon: Icons.gpp_bad_outlined,
        tone: SwapTone.danger,
      ),
      SwapFailureReason.reverted => SwapHeroCopy(
        title: LocaleKeys.swapFailRevertedTitle.tr(),
        body: LocaleKeys.swapFailRevertedBody.tr(args: [fromTicker]),
        icon: Icons.error_outline_rounded,
        tone: SwapTone.danger,
      ),
      SwapFailureReason.notConfirmed => SwapHeroCopy(
        title: LocaleKeys.swapFailNotConfirmedTitle.tr(),
        body: LocaleKeys.swapFailNotConfirmedBody.tr(),
        icon: Icons.hourglass_bottom_rounded,
        tone: SwapTone.warning,
      ),
      SwapFailureReason.walletRejected => SwapHeroCopy(
        title: LocaleKeys.swapFailRejectedTitle.tr(),
        body: _unlessMoved(LocaleKeys.swapFailRejectedBody.tr()),
        icon: Icons.do_not_disturb_on_outlined,
        tone: SwapTone.warning,
      ),
      SwapFailureReason.routeFailed => SwapHeroCopy(
        title: LocaleKeys.swapFailRouteTitle.tr(),
        body: LocaleKeys.swapFailRouteBody.tr(args: [fromNetwork]),
        icon: Icons.support_agent_rounded,
        tone: SwapTone.danger,
      ),
      SwapFailureReason.safetyCheck => SwapHeroCopy(
        title: LocaleKeys.swapFailSafetyTitle.tr(),
        body: _unlessMoved(LocaleKeys.swapFailSafetyBody.tr()),
        icon: Icons.shield_outlined,
        tone: SwapTone.warning,
      ),
      SwapFailureReason.quoteUnavailable => SwapHeroCopy(
        title: LocaleKeys.swapFailQuoteTitle.tr(),
        body: _unlessMoved(LocaleKeys.swapFailQuoteBody.tr()),
        icon: Icons.price_change_outlined,
        tone: SwapTone.warning,
      ),
      SwapFailureReason.restarted => SwapHeroCopy(
        title: LocaleKeys.swapFailRestartTitle.tr(),
        body: _unlessMoved(LocaleKeys.swapFailRestartBody.tr()),
        icon: Icons.restart_alt_rounded,
        tone: SwapTone.warning,
      ),
      SwapFailureReason.exchangeFailed => SwapHeroCopy(
        title: LocaleKeys.swapFailExchangeTitle.tr(),
        body: _nothingSent
            ? LocaleKeys.swapFailExchangeBodySafe.tr()
            : LocaleKeys.swapFailExchangeBody.tr(),
        icon: Icons.sync_problem_rounded,
        tone: _nothingSent ? SwapTone.warning : SwapTone.danger,
      ),
      SwapFailureReason.internal => SwapHeroCopy(
        title: LocaleKeys.swapFailInternalTitle.tr(),
        body: _unlessMoved(LocaleKeys.swapFailInternalBody.tr()),
        icon: Icons.error_outline_rounded,
        tone: uncertain ? SwapTone.danger : SwapTone.warning,
      ),
      SwapFailureReason.unknown => SwapHeroCopy(
        title: LocaleKeys.swapFailUnknownTitle.tr(),
        body: LocaleKeys.swapFailUnknownBody.tr(),
        icon: Icons.help_outline_rounded,
        tone: SwapTone.warning,
      ),
    };
  }

  String _shortfallBody(SwapExecutionFailure? failure) {
    final required = failure?.shortfallRequired;
    final available = failure?.shortfallAvailable;
    final ticker =
        (failure?.shortfallAsset == null
            ? null
            : SwapFormat.ticker(failure!.shortfallAsset!)) ??
        failure?.shortfallTicker ??
        fromTicker;
    if (required == null || available == null) {
      return _unlessMoved(LocaleKeys.swapFundsUnchanged.tr());
    }
    return LocaleKeys.swapFailBalanceBody.tr(
      args: [
        SwapFormat.tokens(required, ticker, rounding: SwapRounding.up),
        SwapFormat.tokens(available, ticker, rounding: SwapRounding.down),
      ],
    );
  }
}
