part of 'swap_review_view.dart';

/// Where a routed review's documents and the acceptance of them sit. The
/// provider's name always closes the scrolling content.
enum _ReviewLegal {
  /// An order-book swap has none.
  none,

  /// Nothing is asked of the user: the documents close the scrolling content
  /// too, and only the action is pinned.
  content,

  /// Acceptance is asked for and there is room: it sits with the action
  /// that gives it, documents and all.
  footer,

  /// Acceptance is asked for on a small screen or at large text, where that
  /// block would cover the review, or the documents could not be read: one
  /// line or the notice stays with the action, and the documents scroll.
  split;

  /// The smallest screen, and the largest text, that the whole acceptance
  /// still leaves most of to the review.
  static const _roomyHeight = 640.0;
  static const _roomyWidth = 360.0;
  static const _roomyTextScale = 1.3;

  static _ReviewLegal of(
    BuildContext context,
    SwapReview review,
    Size viewport,
  ) {
    if (review.quote.source != SwapLiquiditySource.routed) return none;
    if (!SwapLegalConsentNotice.appliesTo(review)) return content;
    // Documents that could not be read are not offered beside the notice
    // saying so; the notice alone stays with the action it blocks.
    if (review.showLegalFailure) return split;
    final roomy =
        viewport.height >= _roomyHeight &&
        viewport.width >= _roomyWidth &&
        MediaQuery.textScalerOf(context).scale(1) <= _roomyTextScale;
    return roomy ? footer : split;
  }

  /// Whether the documents are linked from the scrolling content.
  bool get linksInContent => this == content || this == split;
}

/// The review's one action for its status, with the consent it gives.
///
/// The actions that commit funds — starting, approving and starting,
/// accepting changed terms — are armed [swapCommitArmingDelay] after they
/// become available, and again whenever what they would commit to changes.
/// Until then they look ready and drop presses.
class _ReviewFooter extends StatefulWidget {
  const _ReviewFooter({
    required this.review,
    required this.legal,
    required this.tradingEnabled,
    required this.tradingStatusLoading,
    required this.tradingStatusUnavailable,
    required this.hardwareWallet,
    this.paused = false,
  });

  final SwapReview review;
  final _ReviewLegal legal;
  final bool paused;
  final bool tradingEnabled;
  final bool tradingStatusLoading;
  final bool tradingStatusUnavailable;
  final bool hardwareWallet;

  /// What a press would commit to; null while the action commits nothing.
  Object? get _offer => !tradingEnabled || !review.canStart
      ? null
      : (review.status, review.quote, review.termsRequired);

  @override
  State<_ReviewFooter> createState() => _ReviewFooterState();
}

class _ReviewFooterState extends State<_ReviewFooter> {
  Timer? _arming;
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(_ReviewFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget._offer != oldWidget._offer) _arm();
  }

  @override
  void dispose() {
    _arming?.cancel();
    super.dispose();
  }

  void _arm() {
    _arming?.cancel();
    _arming = null;
    _armed = false;
    if (widget._offer == null) return;
    _arming = Timer(swapCommitArmingDelay, () => _armed = true);
  }

  void _start() =>
      context.read<UnifiedSwapBloc>().add(const UnifiedSwapStartRequested());

  /// Committing funds gets a firm tap on phones; retries do not.
  void _commit() {
    if (!_armed) return;
    // A second press on its heels is not a second request.
    _arm();
    SwapHaptics.medium();
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    final action = _action(context);
    return switch (widget.legal) {
      _ReviewLegal.none || _ReviewLegal.content => action,
      _ReviewLegal.footer => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SwapLegalConsentNotice(review: review),
          const SizedBox(height: 6),
          action,
        ],
      ),
      _ReviewLegal.split => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SwapLegalConsentNotice(review: review, compact: true),
          const SizedBox(height: 10),
          action,
        ],
      ),
    };
  }

  Widget _action(BuildContext context) {
    final review = widget.review;
    final bloc = context.read<UnifiedSwapBloc>();

    if (!widget.tradingEnabled && !review.startInDoubt) {
      final checking = !widget.hardwareWallet && widget.tradingStatusLoading;
      final retry =
          !widget.hardwareWallet &&
          !widget.tradingStatusLoading &&
          widget.tradingStatusUnavailable;
      return SwapButton(
        key: const Key('swap-start'),
        label: widget.hardwareWallet
            ? LocaleKeys.swapCtaUnavailable.tr()
            : checking
            ? 'swapAvailabilityChecking'.tr()
            : retry
            ? LocaleKeys.tryAgain.tr()
            : LocaleKeys.tradingDisabled.tr(),
        onPressed: retry
            ? () => context.read<TradingStatusBloc>().add(
                TradingStatusCheckRequested(),
              )
            : null,
        busy: checking,
      );
    }

    final action = switch (review.status) {
      SwapReviewStatus.ready => SwapButton(
        key: const Key('swap-start'),
        label: _startLabel(review.quote),
        onPressed: review.legalAllowed ? _commit : null,
      ),
      SwapReviewStatus.materialUpdate => SwapButton(
        key: const Key('swap-start'),
        label: LocaleKeys.swapAcceptUpdated.tr(),
        onPressed: review.legalAllowed ? _commit : null,
      ),
      SwapReviewStatus.expired => SwapButton(
        label: LocaleKeys.swapCtaRefresh.tr(),
        onPressed: _start,
      ),
      SwapReviewStatus.revalidationFailed =>
        switch (review.revalidationRecovery) {
          SwapRevalidationRecovery.backToForm => SwapButton(
            label: LocaleKeys.swapCtaBackToSwap.tr(),
            onPressed: () => bloc.add(const UnifiedSwapReviewClosed()),
          ),
          SwapRevalidationRecovery.waitForSource => SwapButton(
            label: LocaleKeys.tryAgain.tr(),
            onPressed: widget.paused ? null : _start,
          ),
          SwapRevalidationRecovery.tryAgain => SwapButton(
            label: LocaleKeys.tryAgain.tr(),
            onPressed: _start,
          ),
        },
      SwapReviewStatus.rejected => SwapButton(
        label: LocaleKeys.tryAgain.tr(),
        onPressed: _start,
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
