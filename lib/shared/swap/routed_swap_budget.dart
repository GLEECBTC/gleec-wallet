part of 'routed_swap_source.dart';

typedef _QuoteKey = ({
  AssetId from,
  AssetId to,
  Decimal amount,
  SwapQuoteOrder order,
  double slippage,
});

/// Spends the aggregator's request budget carefully.
///
/// Without an API key the aggregator allows 75 quotes every two hours per
/// network address. So an answer is reused while it is fresh, and a rate
/// limit is waited out here, doubling each time, rather than asked into:
/// every request made while limited is refused and still counts.
class _QuoteBudget {
  _QuoteBudget(this._now);

  final DateTime Function() _now;

  /// How long an identical request is answered from the last reply.
  static const reuseFor = Duration(seconds: 15);

  /// How long a reply may stand in for a Max probe on the same pair.
  static const gasReuseFor = Duration(seconds: 60);

  static const firstPause = Duration(seconds: 30);
  static const longestPause = Duration(minutes: 10);

  final Map<_QuoteKey, (DateTime, RoutedSwapOffer)> _recent = {};
  DateTime? _pausedUntil;
  Duration _nextPause = firstPause;

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
    _nextPause = firstPause;
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

  DateTime? get pausedUntil {
    final until = _pausedUntil;
    return until != null && until.isAfter(_now()) ? until : null;
  }

  DateTime pause() {
    final until = _now().add(_nextPause);
    _pausedUntil = until;
    final doubled = _nextPause * 2;
    _nextPause = doubled > longestPause ? longestPause : doubled;
    return until;
  }
}
