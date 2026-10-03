part of 'routed_swap_source.dart';

typedef _QuoteKey = ({
  AssetId from,
  AssetId to,
  Decimal amount,
  SwapQuoteOrder order,
  double slippage,
});

/// The aggregator's rate limit, as the app has met it.
///
/// The limit belongs to the network address, or to a proxy's key, not to one
/// visit to the swap form. So one instance lives as long as the app: coming
/// back to Swap must not forget a pause and ask straight into the limit again.
class RoutedSwapRateLimit {
  static const firstPause = Duration(seconds: 30);
  static const longestPause = Duration(minutes: 10);

  DateTime? _pausedUntil;
  Duration _nextPause = firstPause;
  var _holding = false;

  /// Until when no request is made at all, as of [now]; null when none waits.
  DateTime? pausedUntil(DateTime now) {
    final until = _pausedUntil;
    return until != null && until.isAfter(now) ? until : null;
  }

  /// Whether the form's own re-pricing waits for a request someone made.
  ///
  /// A refusal can last up to two hours, and a request made meanwhile is
  /// refused too, so only someone acting asks again.
  bool get holdsAutomatic => _holding;

  /// Records a refusal at [now]: waits twice as long as last time, and holds
  /// automatic requests until a price comes back.
  DateTime pause(DateTime now) {
    final until = now.add(_nextPause);
    _pausedUntil = until;
    _holding = true;
    final doubled = _nextPause * 2;
    _nextPause = doubled > longestPause ? longestPause : doubled;
    return until;
  }

  /// Records a price: the limit has lifted.
  void lift() {
    _nextPause = firstPause;
    _holding = false;
  }
}

/// Spends the aggregator's request budget carefully.
///
/// Without an API key the aggregator allows 75 quotes every two hours per
/// network address, and a proxy's key is shared by every user. So an answer
/// is reused while it is fresh, and a rate limit is waited out in
/// [RoutedSwapRateLimit] rather than asked into.
class _QuoteBudget {
  _QuoteBudget(this._now, this._limit);

  final DateTime Function() _now;
  final RoutedSwapRateLimit _limit;

  /// How long an identical request is answered from the last reply.
  static const reuseFor = Duration(seconds: 15);

  /// How long a reply may stand in for a Max probe on the same pair.
  static const gasReuseFor = Duration(seconds: 60);

  final Map<_QuoteKey, (DateTime, RoutedSwapOffer)> _recent = {};

  RoutedSwapOffer? recent(_QuoteKey key) {
    final hit = _recent[key];
    if (hit == null) return null;
    if (_now().difference(hit.$1) > reuseFor) return null;
    return hit.$2;
  }

  /// Records a reply, which also ends any backoff.
  void remember(_QuoteKey key, RoutedSwapOffer offer) {
    final now = _now();
    _recent
      ..removeWhere((_, hit) => now.difference(hit.$1) > gasReuseFor)
      ..[key] = (now, offer);
    _limit.lift();
  }

  RoutedSwapOffer? latestFor(AssetId from, AssetId to) {
    (DateTime, RoutedSwapOffer)? best;
    for (final entry in _recent.entries) {
      if (entry.key.from != from || entry.key.to != to) continue;
      if (best == null || entry.value.$1.isAfter(best.$1)) best = entry.value;
    }
    if (best == null || _now().difference(best.$1) > gasReuseFor) return null;
    return best.$2;
  }

  DateTime? get pausedUntil => _limit.pausedUntil(_now());

  bool get holdsAutomatic => _limit.holdsAutomatic;

  DateTime pause() => _limit.pause(_now());
}
