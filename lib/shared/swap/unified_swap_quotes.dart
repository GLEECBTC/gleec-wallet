part of 'unified_swap_repository.dart';

/// Everything one pricing attempt produced.
class UnifiedSwapQuotes extends Equatable {
  const UnifiedSwapQuotes({
    required this.ranked,
    required this.unrankable,
    required this.failures,
  });

  /// Options that could be compared on net return, best first.
  final List<SwapQuote> ranked;

  /// Options missing a price for some cost, so they cannot be compared
  /// honestly. Kept apart: a user may still choose one, deliberately.
  final List<SwapQuote> unrankable;

  /// Sources that could not price this swap, and why.
  ///
  /// Kept rather than discarded: when nothing can be priced, *why* is the only
  /// useful thing to tell the user, and "no aggregator lists this asset" needs
  /// very different copy from "no one is trading it right now".
  final List<SwapQuoteFailure> failures;

  /// Every option, ranked ones first.
  List<SwapQuote> get options => [...ranked, ...unrankable];

  /// Whether any option exists.
  bool get isEmpty => ranked.isEmpty && unrankable.isEmpty;

  /// The option to preselect, or null when the user must choose.
  ///
  /// The best ranked option; a lone unrankable option when it is the only
  /// one; and nothing when several options exist and none can be ranked —
  /// picking one silently would be a ranking by another name.
  SwapQuote? get preselected {
    if (ranked.isNotEmpty) return ranked.first;
    if (unrankable.length == 1) return unrankable.first;
    return null;
  }

  /// Whether "best net return" may be claimed for the top option: only when
  /// at least two options were comparable.
  bool get canClaimBestNetReturn => ranked.length >= 2;

  /// Whether several options exist, so comparison is worth offering.
  bool get hasAlternatives => options.length > 1;

  /// The failure that best explains an empty result, preferring the one with
  /// the most useful next step.
  SwapQuoteFailure? get primaryFailure {
    if (failures.isEmpty) return null;
    const priority = [
      SwapQuoteFailureKind.tradingBlocked,
      SwapQuoteFailureKind.clockInvalid,
      SwapQuoteFailureKind.assetInactive,
      SwapQuoteFailureKind.insufficientFunds,
      SwapQuoteFailureKind.belowMinimum,
      SwapQuoteFailureKind.aboveMaximum,
      SwapQuoteFailureKind.invalidAmount,
      // A source that looked and found nothing is a firmer answer than one
      // that could not look; the copy adds the other's failure to it.
      SwapQuoteFailureKind.noRoute,
      SwapQuoteFailureKind.rateLimited,
      SwapQuoteFailureKind.timeout,
      SwapQuoteFailureKind.serviceError,
      SwapQuoteFailureKind.notConfigured,
      SwapQuoteFailureKind.pairUnsupported,
      SwapQuoteFailureKind.unknown,
      // Whatever a source that was asked said explains more.
      SwapQuoteFailureKind.signedOut,
    ];
    final sorted = [...failures]
      ..sort((a, b) {
        final byKind = priority
            .indexOf(a.kind)
            .compareTo(priority.indexOf(b.kind));
        return byKind != 0 ? byKind : _moreHelpful(a, b);
      });
    return sorted.first;
  }

  /// Between two failures of one kind, the one whose next step reaches a swap
  /// soonest: the lower minimum, the higher maximum, a miss that names
  /// amounts that do fill, then one that says why.
  static int _moreHelpful(SwapQuoteFailure a, SwapQuoteFailure b) {
    int nullsLast(Decimal? x, Decimal? y, {bool highFirst = false}) {
      if (x == null || y == null) return x == null ? (y == null ? 0 : 1) : -1;
      return highFirst ? y.compareTo(x) : x.compareTo(y);
    }

    int rank(SwapQuoteFailure f) => !(f.offers?.isEmpty ?? true)
        ? 0
        : f.reasons.isNotEmpty
        ? 1
        : 2;

    return switch (a.kind) {
      SwapQuoteFailureKind.belowMinimum => nullsLast(a.minimum, b.minimum),
      SwapQuoteFailureKind.aboveMaximum => nullsLast(
        a.maximum,
        b.maximum,
        highFirst: true,
      ),
      SwapQuoteFailureKind.noRoute => rank(a).compareTo(rank(b)),
      _ => 0,
    };
  }

  /// Whether every source agrees this pair simply cannot be traded here.
  bool get isPermanentlyUnsupported =>
      isEmpty && failures.isNotEmpty && failures.every((f) => f.isPermanent);

  /// The option with [id], if it is still on offer.
  SwapQuote? byId(String id) {
    for (final option in options) {
      if (option.id == id) return option;
    }
    return null;
  }

  @override
  List<Object?> get props => [ranked, unrankable, failures];
}
