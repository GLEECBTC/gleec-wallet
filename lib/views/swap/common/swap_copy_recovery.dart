part of 'swap_copy.dart';

/// The recovery answers for a finished swap: where the funds are, what can
/// be done next, and what support needs.
extension SwapRecoveryCopy on SwapExecutionCopy {
  /// "Minimum was X. Now Y." for a price move with a fresh quote.
  String? get priceMoveComparison {
    final failure = snapshot.outcome?.failure;
    final fresh = failure?.freshQuote;
    final before = snapshot.minimumReceive;
    if (fresh == null || before == null) return null;
    return LocaleKeys.swapFailPriceMovedCompare.tr(
      args: [
        SwapFormat.tokens(before, toTicker, rounding: SwapRounding.down),
        SwapFormat.tokens(
          fresh.guaranteedReceive,
          toTicker,
          rounding: SwapRounding.down,
        ),
      ],
    );
  }

  /// The answer to "Where are the funds?".
  String get fundsLocation {
    final outcome = snapshot.outcome;
    final lines = <String>[];
    switch (outcome?.kind) {
      case SwapOutcomeKind.completed ||
          SwapOutcomeKind.partialBelowMinimum ||
          SwapOutcomeKind.partialOtherToken:
        final address = snapshot.toAddress;
        lines.add(
          address == null
              ? LocaleKeys.swapFundsAtDestinationNetwork.tr(
                  args: [_received, toNetwork],
                )
              : LocaleKeys.swapFundsAtDestination.tr(
                  args: [_received, SwapFormat.short(address), toNetwork],
                ),
        );
      case SwapOutcomeKind.refunded:
        lines.add(LocaleKeys.swapFundsRefunded.tr(args: [fromNetwork]));
      case SwapOutcomeKind.cancelled || SwapOutcomeKind.noMatch:
        lines.add(LocaleKeys.swapFundsUnchanged.tr());
      case SwapOutcomeKind.failed || null:
        lines.add(switch (snapshot.fundsMovement) {
          SwapFundsMovement.none => LocaleKeys.swapFundsUnchanged.tr(),
          SwapFundsMovement.feesOnly => LocaleKeys.swapFundsFeesOnly.tr(
            args: [fromTicker],
          ),
          SwapFundsMovement.uncertain || SwapFundsMovement.sent =>
            snapshot.source == SwapLiquiditySource.atomic
                ? LocaleKeys.swapFundsInExchange.tr(args: [fromNetwork])
                : LocaleKeys.swapFundsUncertain.tr(
                    args: [_sellAmount, fromNetwork],
                  ),
        });
    }
    if (snapshot.approvalRemains) {
      lines.add(
        LocaleKeys.swapFundsPermissionRemains.tr(args: [_approvalAmount]),
      );
    }
    return lines.join(' ');
  }

  /// What the finished swap's screen may offer, most useful first.
  List<SwapOutcomeAction> get actions {
    final outcome = snapshot.outcome;
    if (outcome == null) return const [];
    final failure = outcome.failure;
    final hasSourceTx = snapshot.evidence.sourceTxHash != null;
    switch (outcome.kind) {
      case SwapOutcomeKind.completed:
        return const [SwapOutcomeAction.startAnother];
      case SwapOutcomeKind.partialOtherToken:
        return [
          if (outcome.receivedAsset != null) SwapOutcomeAction.followUp,
          SwapOutcomeAction.keepToken,
        ];
      case SwapOutcomeKind.partialBelowMinimum:
        return const [
          SwapOutcomeAction.startAnother,
          SwapOutcomeAction.contactSupport,
        ];
      case SwapOutcomeKind.refunded:
        return const [SwapOutcomeAction.tryAgain];
      case SwapOutcomeKind.cancelled || SwapOutcomeKind.noMatch:
        return const [SwapOutcomeAction.tryAgain];
      case SwapOutcomeKind.failed:
        final reason = failure?.reason ?? SwapFailureReason.unknown;
        if (snapshot.source == SwapLiquiditySource.atomic &&
            snapshot.fundsMovement != SwapFundsMovement.none) {
          return const [
            SwapOutcomeAction.openAdvanced,
            SwapOutcomeAction.contactSupport,
          ];
        }
        return switch (reason) {
          SwapFailureReason.priceMoved => [
            if (failure?.freshQuote != null) SwapOutcomeAction.acceptFreshQuote,
            SwapOutcomeAction.tryAgain,
          ],
          SwapFailureReason.notConfirmed => [
            if (hasSourceTx) SwapOutcomeAction.viewOnExplorer,
            SwapOutcomeAction.contactSupport,
          ],
          SwapFailureReason.routeFailed ||
          SwapFailureReason.unknown => const [SwapOutcomeAction.contactSupport],
          SwapFailureReason.safetyCheck =>
            (failure?.retryable ?? false)
                ? const [SwapOutcomeAction.tryAgain]
                : const [SwapOutcomeAction.contactSupport],
          SwapFailureReason.reverted => [
            SwapOutcomeAction.tryAgain,
            if (hasSourceTx) SwapOutcomeAction.viewOnExplorer,
          ],
          _ =>
            snapshot.fundsMovement == SwapFundsMovement.none ||
                    snapshot.fundsMovement == SwapFundsMovement.feesOnly
                ? const [SwapOutcomeAction.tryAgain]
                : const [SwapOutcomeAction.contactSupport],
        };
    }
  }

  /// A one-line status for an Activity row.
  String get statusLine {
    final outcome = snapshot.outcome;
    if (outcome == null) {
      if (snapshot.stage == SwapProgressStage.actionRequired) {
        return LocaleKeys.swapActivityActionRequired.tr();
      }
      return hero.title;
    }
    return switch (outcome.kind) {
      SwapOutcomeKind.completed => LocaleKeys.swapActivityCompleted.tr(),
      SwapOutcomeKind.partialBelowMinimum =>
        LocaleKeys.swapActivityPartialReceived.tr(),
      SwapOutcomeKind.partialOtherToken =>
        LocaleKeys.swapActivityOtherToken.tr(),
      SwapOutcomeKind.refunded => LocaleKeys.swapActivityRefunded.tr(),
      SwapOutcomeKind.cancelled =>
        snapshot.approvalRemains
            ? LocaleKeys.swapActivityPermissionRemains.tr()
            : LocaleKeys.swapActivityCancelled.tr(),
      SwapOutcomeKind.noMatch => LocaleKeys.swapActivityNoMatch.tr(),
      SwapOutcomeKind.failed => hero.title,
    };
  }

  /// The support hand-off: the facts support needs, as plain text.
  ///
  /// Contains identifiers and hashes the user chooses to share. Never sent
  /// anywhere automatically, and never used for analytics.
  String supportPayload() {
    final evidence = snapshot.evidence;
    final buffer = StringBuffer()
      ..writeln('${LocaleKeys.swapEvidenceExecutionId.tr()}: ${snapshot.id}')
      ..writeln('${LocaleKeys.swapEvidenceRoute.tr()}: $pairLine')
      ..writeln('${LocaleKeys.swapActivityInProgress.tr()}: $statusLine');
    final created = snapshot.createdAt;
    if (created != null) {
      buffer.writeln(
        '${LocaleKeys.swapEvidenceStarted.tr()}: '
        '${created.toUtc().toIso8601String()}',
      );
    }
    final updated = snapshot.updatedAt;
    if (updated != null) {
      buffer.writeln(
        '${LocaleKeys.swapEvidenceUpdated.tr()}: '
        '${updated.toUtc().toIso8601String()}',
      );
    }
    for (final hash in evidence.approvalTxHashes) {
      buffer.writeln('${LocaleKeys.swapEvidenceApprovals.tr()}: $hash');
    }
    if (evidence.sourceTxHash != null) {
      buffer.writeln(
        '${LocaleKeys.swapEvidenceSource.tr()}: ${evidence.sourceTxHash}',
      );
    }
    if (evidence.destinationTxHash != null) {
      buffer.writeln(
        '${LocaleKeys.swapEvidenceDestination.tr()}: '
        '${evidence.destinationTxHash}',
      );
    }
    if (evidence.providerRequestId != null) {
      buffer.writeln(
        '${LocaleKeys.swapEvidenceSupportRef.tr()}: '
        '${evidence.providerRequestId}',
      );
    }
    for (final entry in [
      ('state', evidence.rawState),
      ('error', evidence.errorType),
      ('route', evidence.diagnostic),
      ('route_status', evidence.providerStatus),
    ]) {
      if (entry.$2 != null) buffer.writeln('${entry.$1}: ${entry.$2}');
    }
    return buffer.toString().trim();
  }
}
