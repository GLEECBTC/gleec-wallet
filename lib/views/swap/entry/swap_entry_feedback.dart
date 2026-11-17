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

/// Keeps quote feedback in one stable place. Only the first useful arrival
/// gets an emphasis; a provider poll never causes a new celebration.
class _EntryQuoteArea extends StatefulWidget {
  const _EntryQuoteArea({required this.state, required this.onCompare});

  final UnifiedSwapState state;
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

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final quote = state.selectedQuote;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve the summary, comparison and provider line before they arrive.
        // Narrow widths stack the three facts; large text gets the same space
        // without clipping or scaling the financial figures down.
        final reserved =
            (constraints.maxWidth / scale < 328 ? 410.0 : 320.0) * scale;
        return ConstrainedBox(
          key: const Key('swap-quote-region'),
          constraints: BoxConstraints(minHeight: reserved),
          child: AnimatedBuilder(
            animation: _arrival,
            builder: (context, child) => DecoratedBox(
              decoration: BoxDecoration(
                color: SwapPalette.of(context).selected
                    .withValues(alpha: 0.35 * _arrival.value),
                borderRadius: BorderRadius.circular(16),
              ),
              child: child,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.evaluation == SwapEvaluationStatus.checking)
                  SwapHelperLine(
                    text: _slow
                        ? 'swapQuoteSlow'.tr()
                        : LocaleKeys.swapHelperChecking.tr(),
                  ),
                if (quote != null) ...[
                  SwapQuoteStrip(state: state, onCompare: widget.onCompare),
                  SwapRateLine(quote: quote),
                  if (state.quotesPending)
                    SwapHelperLine(text: 'swapMoreQuotesChecking'.tr()),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
