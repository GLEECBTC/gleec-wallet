import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Amounts of the pay asset that one order takes whole, from [min] to [max].
class SwapOfferBand extends Equatable {
  const SwapOfferBand(this.min, this.max);

  final Decimal min;
  final Decimal max;

  bool contains(Decimal amount) => amount >= min && amount <= max;

  @override
  List<Object?> get props => [min, max];
}

/// What other traders on the order book offer for one pair, in pay units.
///
/// A taker order fills against a single maker order, so what an amount needs
/// is one order whose own range holds it, never a sum across orders.
class SwapOrderBookOffers extends Equatable {
  const SwapOrderBookOffers([this.bands = const []]);

  /// Reads the bids of `orderbook(pay, receive)`. The wallet's own orders and
  /// unreadable ones are left out, and no band starts below [floor], the
  /// smallest trade the pay coin allows.
  factory SwapOrderBookOffers.fromBids(List<OrderInfo> bids, {Decimal? floor}) {
    final ranges = <SwapOfferBand>[];
    for (final bid in bids) {
      if (bid.isMine ?? false) continue;
      final price = _decimalOf(bid.price);
      final max = _decimalOf(bid.baseMaxVolume);
      if (price == null || price <= Decimal.zero || max == null) continue;
      var min = _decimalOf(bid.baseMinVolume) ?? Decimal.zero;
      if (floor != null && floor > min) min = floor;
      if (min > max) continue;
      ranges.add(SwapOfferBand(min, max));
    }
    ranges.sort((a, b) => a.min.compareTo(b.min));

    final merged = <SwapOfferBand>[];
    for (final range in ranges) {
      final last = merged.lastOrNull;
      if (last != null && range.min <= last.max) {
        merged[merged.length - 1] = SwapOfferBand(
          last.min,
          range.max > last.max ? range.max : last.max,
        );
      } else {
        merged.add(range);
      }
    }
    return SwapOrderBookOffers(merged);
  }

  /// The amounts some order takes, sorted and never overlapping.
  final List<SwapOfferBand> bands;

  /// Whether no one is offering anything for the pair.
  bool get isEmpty => bands.isEmpty;

  /// The smallest amount any order takes.
  Decimal? get minimum => bands.firstOrNull?.min;

  /// The largest amount any single order takes.
  Decimal? get maximum => bands.lastOrNull?.max;

  /// Whether one order takes [amount] whole.
  bool fits(Decimal amount) => bands.any((band) => band.contains(amount));

  /// The largest amount no more than [amount] that one order takes, with no
  /// more than [scale] decimal places when given.
  Decimal? largestUpTo(Decimal amount, {int? scale}) {
    for (final band in bands.reversed) {
      if (band.min > amount) continue;
      var largest = band.max < amount ? band.max : amount;
      if (scale != null) largest = largest.floor(scale: scale);
      // Rounding down can land under this range's minimum; try a lower one.
      if (largest >= band.min) return largest;
    }
    return null;
  }

  /// The smallest amount no less than [amount] that one order takes.
  Decimal? smallestFrom(Decimal amount) {
    for (final band in bands) {
      if (band.max >= amount) return band.min > amount ? band.min : amount;
    }
    return null;
  }

  static Decimal? _decimalOf(NumericValue? value) =>
      value == null ? null : Decimal.tryParse(value.decimal);

  @override
  List<Object?> get props => [bands];
}

/// A source that can say what the order book offers before pricing a swap.
abstract interface class SwapOfferSource {
  /// What the order book offers for selling [from] for [to]; null when that
  /// cannot be read.
  Future<SwapOrderBookOffers?> offers(AssetId from, AssetId to);

  /// For each of [candidates], whether some order lets the user pay [anchor]
  /// for it (when [anchorPays]) or pay it for [anchor] (otherwise). A
  /// candidate left out could not be checked; null means nothing could be.
  Future<Map<AssetId, bool>?> offered(
    AssetId anchor,
    Iterable<AssetId> candidates, {
    required bool anchorPays,
  });
}

/// Which assets anyone trades against [anchor] on the order book.
class SwapOfferCounts extends Equatable {
  const SwapOfferCounts(this.anchor, this.offered);

  final AssetId anchor;

  /// Per asset, whether any order trades it against [anchor]. An asset left
  /// out is unknown.
  final Map<AssetId, bool> offered;

  /// Whether [asset] is known to have no offers.
  bool lacks(AssetId asset) => offered[asset] == false;

  /// Whether nothing is known to trade against [anchor] at all.
  bool get none => offered.isNotEmpty && !offered.containsValue(true);

  @override
  List<Object?> get props => [anchor, offered];
}

/// What the swap form knows of the order book for its assets.
///
/// Hints only: orders come and go, and a quote stays the answer.
class SwapOrderBookHints extends Equatable {
  const SwapOrderBookHints({
    this.pair,
    this.offers,
    this.payCounts,
    this.receiveCounts,
    this.watching = false,
  });

  /// The pair [offers] were read for.
  final (AssetId, AssetId)? pair;

  /// The offers for [pair], a pair only the order book trades.
  final SwapOrderBookOffers? offers;

  /// What the pay asset can buy on the order book.
  final SwapOfferCounts? payCounts;

  /// What can buy the receive asset on the order book.
  final SwapOfferCounts? receiveCounts;

  /// Whether the form keeps checking a pair no one is offering.
  final bool watching;

  /// The offers for [pay] → [receive], when those were read.
  SwapOrderBookOffers? offersFor(AssetId pay, AssetId receive) =>
      pair == (pay, receive) ? offers : null;

  SwapOrderBookHints copyWith({
    (AssetId, AssetId)? pair,
    SwapOrderBookOffers? offers,
    SwapOfferCounts? payCounts,
    SwapOfferCounts? receiveCounts,
    bool? watching,
    bool clearOffers = false,
  }) => SwapOrderBookHints(
    pair: clearOffers ? null : (pair ?? this.pair),
    offers: clearOffers ? null : (offers ?? this.offers),
    payCounts: payCounts ?? this.payCounts,
    receiveCounts: receiveCounts ?? this.receiveCounts,
    watching: watching ?? this.watching,
  );

  @override
  List<Object?> get props => [pair, offers, payCounts, receiveCounts, watching];
}
