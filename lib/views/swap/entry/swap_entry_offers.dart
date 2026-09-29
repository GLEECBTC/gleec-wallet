part of 'swap_entry_view.dart';

/// A pair no one offers on the order book, and what offers take when some
/// do.
extension _SwapEntryOffers on _SwapEntryViewState {
  /// Whether the pay asset is the one only the order book trades. A pair no
  /// one offers keeps that asset; the receive side when both are.
  bool _keepsPay(UnifiedSwapState state) {
    final routed = state.catalog.of(SwapLiquiditySource.routed);
    return (routed?.supports(state.receive!) ?? false) &&
        !(routed?.supports(state.pay!) ?? false);
  }

  /// Whether nothing at all trades against the asset the pair keeps.
  bool _noMarket(UnifiedSwapState state) {
    final keepsPay = _keepsPay(state);
    final kept = keepsPay ? state.pay : state.receive;
    final counts = keepsPay ? state.hints.payCounts : state.hints.receiveCounts;
    return counts != null && counts.anchor == kept && counts.none;
  }

  /// The side to change: the one not kept, or the kept one when nothing
  /// trades against it.
  SwapPickerSide _offerSideToChange(UnifiedSwapState state) =>
      _keepsPay(state) == _noMarket(state)
      ? SwapPickerSide.pay
      : SwapPickerSide.receive;

  List<Widget> _noOffersLines(UnifiedSwapState state) {
    final pay = state.pay!;
    final receive = state.receive!;
    final orderBookOnly = _keepsPay(state) ? pay : receive;
    final detail = LocaleKeys.swapHelperOffersDetail.tr(
      args: [SwapFormat.ticker(orderBookOnly)],
    );
    final watching = state.hints.watching;
    return [
      SwapHelperLine(
        text: _noMarket(state)
            ? LocaleKeys.swapErrorNoMarket.tr(
                args: [SwapFormat.ticker(orderBookOnly)],
              )
            : LocaleKeys.swapErrorNoOffers.tr(
                args: [SwapFormat.ticker(receive), SwapFormat.ticker(pay)],
              ),
      ),
      SwapHelperLine(
        text: watching
            ? '$detail ${LocaleKeys.swapHelperOffersWatching.tr()}'
            : detail,
      ),
      if (!watching)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SwapLinkButton(
            label: LocaleKeys.swapCtaCheckAgain.tr(),
            onPressed: () =>
                _bloc.add(const UnifiedSwapOffersRequested(recount: true)),
          ),
        ),
    ];
  }

  /// What the pair's offers take, before the pair is priced.
  SwapHelperLine? _offerRange(UnifiedSwapState state) {
    final pay = state.pay;
    final receive = state.receive;
    if (pay == null || receive == null || state.quotes != null) return null;
    final offers = state.hints.offersFor(pay, receive);
    final minimum = offers?.minimum;
    final maximum = offers?.maximum;
    if (minimum == null || maximum == null) return null;
    final ticker = SwapFormat.ticker(pay);
    return SwapHelperLine(
      text: LocaleKeys.swapHelperOffersRange.tr(
        args: [
          SwapFormat.tokens(minimum, ticker, rounding: SwapRounding.up),
          SwapFormat.tokens(maximum, ticker, rounding: SwapRounding.down),
        ],
      ),
    );
  }
}
