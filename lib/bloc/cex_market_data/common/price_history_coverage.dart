import 'package:decimal/decimal.dart';

/// Whether [prices] is only a remnant of the daily history asked for with
/// [requestedDates].
///
/// When its providers fail, the SDK's `fiatPriceHistory` answers with the
/// days it already knows, down to the current price alone, and has no way to
/// say that it did. Two things tell such a remnant from a history:
///
/// - it is a single day of a longer range, or
/// - from its first priced day on, more than half the requested days are
///   missing.
///
/// Days before the first priced one do not count against it: providers keep
/// a limited history, and an asset can be held before anyone priced it.
///
/// No prices at all is not a remnant. The SDK throws when it knows nothing
/// because of a failure, so an empty answer means the asset has no price.
bool isPartialPriceHistory(
  Map<DateTime, Decimal> prices,
  Iterable<DateTime> requestedDates, {
  DateTime? now,
}) {
  if (prices.isEmpty) return false;

  final today = _utcDay(now ?? DateTime.now());
  final pricedDays = {for (final date in prices.keys) _utcDay(date)};
  final requested = {
    for (final date in requestedDates)
      if (!_utcDay(date).isAfter(today)) _utcDay(date),
  };
  final priced = requested.where(pricedDays.contains).toList();
  if (priced.length == requested.length) return false;
  if (priced.length < 2) return true;

  final firstPriced = priced.reduce((a, b) => a.isBefore(b) ? a : b);
  final spanned = requested.where((day) => !day.isBefore(firstPriced)).length;
  return priced.length * 2 < spanned;
}

/// The day the SDK keys a price by.
DateTime _utcDay(DateTime date) {
  final utc = date.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

/// Too little of [assetId]'s price history is known to chart it.
class PartialPriceHistoryException implements Exception {
  const PartialPriceHistoryException(this.assetId);

  final String assetId;

  @override
  String toString() => 'Price history incomplete for $assetId';
}
