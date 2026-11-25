part of 'swap_entry_view.dart';

/// Policy lookup failure is different from a positive location restriction.
class _EntryAvailability extends StatelessWidget {
  const _EntryAvailability({required this.state});

  final UnifiedSwapState state;

  @override
  Widget build(BuildContext context) {
    final checking = state.tradingStatusLoading && !state.hardwareWallet;
    final unavailable = state.tradingStatusUnavailable && !state.hardwareWallet;
    final message = state.hardwareWallet
        ? LocaleKeys.trezorWalletOnlyNotice.tr()
        : checking
        ? 'swapAvailabilityChecking'.tr()
        : unavailable
        ? 'swapAvailabilityUnavailable'.tr()
        : LocaleKeys.tradingDisabled.tr();
    return SwapCallout(
      tone: checking ? SwapTone.neutral : SwapTone.warning,
      message: message,
    );
  }
}

/// Everything the form says under the cards, in one block that keeps its
/// height once a pair is chosen: alerts, the selected option, its rate, and
/// the standing hints. An amount typed, and a quote arriving, failing or
/// being checked again, fill the block in; none of them moves the cards or
/// the main action.
///
/// Only the first useful arrival gets an emphasis; a provider poll never
/// causes a new celebration.
class _EntryQuoteArea extends StatefulWidget {
  const _EntryQuoteArea({
    required this.state,
    required this.lines,
    required this.stale,
    required this.onCompare,
  });

  final UnifiedSwapState state;
  final _EntryLines lines;

  /// Whether the open review has replaced the selected option: its figures
  /// are then left to the review, which shows the old against the new.
  final bool stale;
  final VoidCallback onCompare;

  @override
  State<_EntryQuoteArea> createState() => _EntryQuoteAreaState();
}

class _EntryQuoteAreaState extends State<_EntryQuoteArea>
    with SingleTickerProviderStateMixin {
  Timer? _slowTimer;
  bool _slow = false;
  late final AppLifecycleListener _lifecycle;
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: SwapMotion.quote,
  );

  /// The hints on show. They hold while a new estimate is on its way, so a
  /// hint is not taken away on every edit only to come back.
  late List<String> _hints = widget.lines.hints;

  bool get _checking =>
      widget.state.evaluation == SwapEvaluationStatus.checking &&
      widget.state.selectedQuote == null;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _arrival.value = 0;
      },
    );
    _watchWait();
  }

  bool get _canAnimate {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return SwapMotion.enabled(context) &&
        TickerMode.valuesOf(context).enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_canAnimate) _arrival.value = 0;
  }

  @override
  void didUpdateWidget(covariant _EntryQuoteArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.state;
    final after = widget.state;
    if (before.pay != after.pay ||
        before.receive != after.receive ||
        before.inputText != after.inputText ||
        before.evaluation != after.evaluation) {
      _watchWait();
    }
    if (before.selectedQuote == null &&
        after.selectedQuote != null &&
        _canAnimate) {
      _arrival.reverse(from: 1);
    }
    final sameForm =
        before.pay == after.pay &&
        before.receive == after.receive &&
        before.signedIn == after.signedIn &&
        before.maxApplied == after.maxApplied;
    if (!sameForm || !swapAwaitingEstimate(after)) _hints = widget.lines.hints;
  }

  void _watchWait() {
    _slowTimer?.cancel();
    _slow = false;
    if (_checking) {
      _slowTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _checking) setState(() => _slow = true);
      });
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _lifecycle.dispose();
    _arrival.dispose();
    super.dispose();
  }

  /// What the strip says it is waiting for, while it has no option to show.
  String? get _waitingLabel {
    final state = widget.state;
    if (state.selectedQuote != null || !swapAwaitingEstimate(state)) {
      return null;
    }
    if (state.preparingAssets) return 'swapPreparingAssets'.tr();
    return _slow ? 'swapQuoteSlow'.tr() : LocaleKeys.swapHelperChecking.tr();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final pay = state.pay;
    final receive = state.receive;
    final quote = widget.stale ? null : state.selectedQuote;
    // Once a pair is chosen the block is as tall as a priced swap makes it,
    // and where the pair can be priced, the figures to come hold their
    // place: typing, checking, pricing and failing all leave the main
    // action where it is.
    final reserves = state.hasPair || state.selectedQuote != null;
    final placeholder =
        !widget.stale &&
        state.selectedQuote == null &&
        state.hasPair &&
        state.tradingEnabled &&
        state.issue != SwapFormIssue.pairUnsupported &&
        state.issue != SwapFormIssue.noOffers;
    final routed =
        state.selectedQuote?.source == SwapLiquiditySource.routed ||
        (state.pairSupport?.sources.contains(SwapLiquiditySource.routed) ??
            false);

    final summary = quote == null && !placeholder
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: _summaryGap),
              AnimatedBuilder(
                animation: _arrival,
                builder: (context, child) => DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    color: SwapPalette.of(context).selected
                        .withValues(alpha: 0.35 * _arrival.value),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: child,
                ),
                child: SwapQuoteStrip(
                  state: state,
                  onCompare: widget.onCompare,
                  placeholder: placeholder,
                  waitingLabel: _waitingLabel,
                  waitingAnnounced: _slow,
                ),
              ),
              if (quote != null)
                SwapRateLine(quote: quote)
              else if (pay != null && receive != null)
                SwapRatePlaceholder(from: pay, to: receive),
            ],
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final summaryHeight = reserves
            ? _summaryGap +
                  SwapQuoteStrip.reservedHeight(
                    context,
                    width: constraints.maxWidth,
                    receive: receive,
                    routed: routed,
                  ) +
                  SwapRateLine.heightOf(context)
            : 0.0;
        return Column(
          key: const Key('swap-quote-region'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: summaryHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...widget.lines.alerts, ?summary],
              ),
            ),
            // Under the reserved summary, so a hint changing moves nothing
            // above it, and one line of it nothing below.
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: reserves ? SwapHelperLine.heightOf(context) : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final hint in _hints)
                    SwapHelperLine(text: hint, liveRegion: false),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The space between the cards, or the alerts, and the quote strip.
const _summaryGap = 14.0;
