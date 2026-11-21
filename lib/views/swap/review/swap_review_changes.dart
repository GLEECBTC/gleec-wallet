part of 'swap_review_view.dart';

/// One figure a re-price moved: what it was, what it is, and the two as a
/// sentence for a screen reader.
typedef _TermChange = ({
  String id,
  String label,
  String was,
  String now,
  String spoken,
});

/// What the review says about its latest re-price, and the figures a changed
/// quote moved.
extension _ReviewContentStatus on _ReviewContent {
  /// The review's status line or callout; null when it has nothing to add.
  Widget? _status(BuildContext context) {
    switch (review.status) {
      case SwapReviewStatus.ready || SwapReviewStatus.starting:
        return null;
      case SwapReviewStatus.revalidating:
        return SwapHelperLine(
          text: LocaleKeys.swapReviewRevalidatingBody.tr(),
          liveRegion: true,
        );
      case SwapReviewStatus.materialUpdate:
        return _attention(_changedTerms(context));
      case SwapReviewStatus.expired:
        return _attention(
          SwapCallout(
            tone: SwapTone.warning,
            icon: Icons.timer_outlined,
            title: LocaleKeys.swapReviewExpiredTitle.tr(),
            message: LocaleKeys.swapReviewExpiredBody.tr(),
            liveRegion: true,
          ),
        );
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
        return _attention(
          SwapCallout(
            tone: SwapTone.warning,
            title: title,
            message: message,
            liveRegion: true,
          ),
        );
      case SwapReviewStatus.rejected:
        return _attention(
          SwapCallout(
            tone: SwapTone.danger,
            title: LocaleKeys.swapReviewRejectedTitle.tr(),
            message:
                (review.rejectionReason ==
                            SwapStartRejection.signingPolicyUnsupported
                        ? LocaleKeys.swapReviewSigningPolicyBody
                        : LocaleKeys.swapReviewRejectedBody)
                    .tr(),
            liveRegion: true,
          ),
        );
      case SwapReviewStatus.unconfirmed:
        return _attention(
          SwapCallout(
            tone: SwapTone.warning,
            title: LocaleKeys.swapReviewUnconfirmedTitle.tr(),
            message: LocaleKeys.swapReviewUnconfirmedBody.tr(),
            liveRegion: true,
          ),
        );
    }
  }

  Widget _attention(Widget callout) => _ReviewAttention(
    signal: review.status,
    child: Padding(padding: const EdgeInsets.only(top: 12), child: callout),
  );

  /// What the quote now on offer changed, a line for each figure. Without
  /// the quote first agreed to, or when no figure reads differently, it
  /// still says that the quote changed rather than asking to accept nothing.
  Widget _changedTerms(BuildContext context) {
    final previous = review.previous;
    final changes = previous == null
        ? const <_TermChange>[]
        : _changes(previous);
    return SwapCallout(
      key: const Key('swap-review-changed'),
      tone: SwapTone.warning,
      icon: Icons.compare_arrows_rounded,
      title: LocaleKeys.swapReviewUpdatedTitle.tr(),
      message: changes.isEmpty
          ? 'swapReviewUpdatedFallback'.tr()
          : 'swapReviewUpdatedIntro'.tr(),
      action: changes.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, change) in changes.indexed) ...[
                  if (index > 0) const SizedBox(height: 8),
                  _ChangeRow(change),
                ],
              ],
            ),
      liveRegion: true,
    );
  }

  /// Every figure that reads differently from [previous], which the user
  /// agreed to: the expected and minimum receive, the total cost, and each
  /// balance the swap now needs more of.
  List<_TermChange> _changes(SwapQuote previous) {
    final toTicker = SwapFormat.ticker(quote.to);
    _TermChange change(String id, String label, String was, String now) => (
      id: id,
      label: label,
      was: was,
      now: now,
      spoken: 'swapReviewUpdatedSpoken'.tr(args: [label, was, now]),
    );
    final changes = <_TermChange>[];
    void received(String id, String label, Decimal before, Decimal after) {
      if (before == after) return;
      final (was, now) = SwapFormat.tokensApart(
        before,
        after,
        toTicker,
        rounding: SwapRounding.down,
      );
      changes.add(change(id, label, was, now));
    }

    received(
      'expected',
      LocaleKeys.swapYouReceive.tr(),
      previous.expectedReceive,
      quote.expectedReceive,
    );
    received(
      'minimum',
      LocaleKeys.swapMinimumReceived.tr(),
      previous.guaranteedReceive,
      quote.guaranteedReceive,
    );
    final cost = _costChange(previous);
    if (cost != null) {
      final label = LocaleKeys.swapTotalCost.tr();
      changes.add(
        cost.$1 == null
            ? (
                id: 'cost',
                label: label,
                was: _costUnknown,
                now: cost.$2,
                spoken: LocaleKeys.swapReviewUpdatedCostKnown.tr(
                  args: [cost.$2],
                ),
              )
            : change('cost', label, cost.$1!, cost.$2),
      );
    }
    for (final entry in quote.requiredFeeBalances.entries) {
      final before = previous.requiredFeeBalances[entry.key] ?? Decimal.zero;
      if (entry.value <= before) continue;
      final ticker = SwapFormat.ticker(entry.key);
      final (was, now) = SwapFormat.tokensApart(
        before,
        entry.value,
        ticker,
        rounding: SwapRounding.up,
      );
      changes.add(
        change(
          'funding-$ticker',
          'swapReviewRequiredFunding'.tr(args: [ticker]),
          was,
          now,
        ),
      );
    }
    return changes;
  }

  /// The total cost before and now, when the two read differently; the
  /// first is null where the fees had not been read. In dollars when both
  /// are priced, else in the fees' own tokens.
  (String?, String)? _costChange(SwapQuote previous) {
    String usd(Decimal value) =>
        SwapFormat.usd(value, rounding: SwapRounding.up);
    (String?, String)? apart(String was, String now) =>
        was == now ? null : (was, now);
    final before = previous.pricing.totalCostUsd;
    final after = quote.pricing.totalCostUsd;
    if (before != null && after != null) return apart(usd(before), usd(after));
    if (!quote.feesKnown) return null;
    if (!previous.feesKnown) {
      return (null, after == null ? _feeTokens(quote.fees) : usd(after));
    }
    return apart(_feeTokens(previous.fees), _feeTokens(quote.fees));
  }
}

/// A changed figure: its name, then what it was and what it is now.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow(this.change);

  final _TermChange change;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    // Not a node of its own: the sentence joins the callout's, so the live
    // region reads every change out with its title.
    return Semantics(
      key: Key('swap-review-change-${change.id}'),
      label: change.spoken,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change.label,
            style: SwapText.small(context)
                .copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(change.was, style: SwapText.body(context)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: palette.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(change.now, style: SwapText.strong(context)),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Brings what the user must now read into view as it arrives, or as it
/// changes to something else: the callout heads a long scroll, while the
/// action it explains stays pinned whatever is scrolled.
class _ReviewAttention extends StatefulWidget {
  const _ReviewAttention({required this.signal, required this.child});

  /// Differs whenever there is something new to read.
  final Object signal;
  final Widget child;

  @override
  State<_ReviewAttention> createState() => _ReviewAttentionState();
}

class _ReviewAttentionState extends State<_ReviewAttention> {
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_ReviewAttention oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.signal != oldWidget.signal) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only when scrolled past it: a review opening on a notice keeps its
      // heading.
      Scrollable.ensureVisible(
        context,
        duration: SwapMotion.of(context, SwapMotion.feedback),
        curve: SwapMotion.standard,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
