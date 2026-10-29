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
      if (_offerAlternatives(state) case final alternatives
          when alternatives.isNotEmpty)
        SwapOfferAlternatives(
          label: _keepsPay(state)
              ? LocaleKeys.swapOffersSwapFor.tr(args: [SwapFormat.ticker(pay)])
              : LocaleKeys.swapOffersGetWith.tr(
                  args: [SwapFormat.ticker(receive)],
                ),
          assets: alternatives,
          balanceOf: _services.lastKnownBalance,
          networkOf: _services.networks().networkOf,
          onChosen: (asset) => _edit(
            _keepsPay(state)
                ? UnifiedSwapReceiveAssetChanged(asset)
                : UnifiedSwapPayAssetChanged(asset),
          ),
        ),
    ];
  }

  /// Up to three assets someone trades against the asset the pair keeps, one
  /// per ticker: held ones first, by value, then popular ones.
  List<AssetId> _offerAlternatives(UnifiedSwapState state) {
    final keepsPay = _keepsPay(state);
    final kept = keepsPay ? state.pay : state.receive;
    final replaced = keepsPay ? state.receive : state.pay;
    final counts = keepsPay ? state.hints.payCounts : state.hints.receiveCounts;
    if (counts == null || counts.anchor != kept) return const [];

    final balance = <AssetId, Decimal>{};
    Decimal value(AssetId id) =>
        (balance[id] ?? Decimal.zero) *
        (_services.usdPrice(id) ?? Decimal.zero);
    int popularity(AssetId id) {
      final rank = swapPopularTickers.indexOf(
        SwapFormat.ticker(id).toUpperCase(),
      );
      return rank < 0 ? swapPopularTickers.length : rank;
    }

    final offered = [
      for (final MapEntry(key: id, value: offers) in counts.offered.entries)
        if (offers && id != replaced && !_isBlocked(id)) id,
    ];
    for (final id in offered) {
      balance[id] = _services.lastKnownBalance(id) ?? Decimal.zero;
    }
    // As in the picker: a legacy asset only to pay with, while held.
    offered.removeWhere(
      (id) =>
          isLegacySwapAsset(id) && (keepsPay || balance[id]! <= Decimal.zero),
    );
    offered.sort((a, b) {
      final held = (balance[b]! > Decimal.zero ? 1 : 0).compareTo(
        balance[a]! > Decimal.zero ? 1 : 0,
      );
      if (held != 0) return held;
      final byValue = value(b).compareTo(value(a));
      if (byValue != 0) return byValue;
      final byRank = popularity(a).compareTo(popularity(b));
      if (byRank != 0) return byRank;
      final byTicker = SwapFormat.ticker(a).compareTo(SwapFormat.ticker(b));
      return byTicker != 0 ? byTicker : a.id.compareTo(b.id);
    });
    final tickers = <String>{};
    return [
      for (final id in offered)
        if (tickers.add(SwapFormat.ticker(id))) id,
    ].take(3).toList();
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
