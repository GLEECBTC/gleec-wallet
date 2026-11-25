import 'package:intl/intl.dart';

/// US dollar values for display, all in one number style.
///
/// `NumberFormat` without a locale reads a process-wide default that differs
/// by device, which is how one wallet row came to show `$60 251,14` beside
/// `$0.041`. Every value here uses the same grouping and decimal separators.
abstract final class FiatFormat {
  static const _locale = 'en_US';

  /// The minus sign, U+2212, which sets at the width of a plus sign.
  static const minus = '−';

  static const _subscriptDigits = '₀₁₂₃₄₅₆₇₈₉';

  /// From this many zeros after the decimal point a price collapses them,
  /// so `0.0000051` reads `0.0₅51`.
  static const collapseZerosFrom = 4;

  static final NumberFormat _grouped = NumberFormat('#,##0.00', _locale);
  static final NumberFormat _compact = NumberFormat.compactSimpleCurrency(
    locale: _locale,
  );

  /// A held value: `$1,234.56`, or `<$0.01` for a positive amount under a cent.
  static String amount(double value, {String symbol = r'$'}) {
    if (!value.isFinite) return '--';
    final rounded = _roundCents(value.abs());
    if (value > 0 && rounded == 0) return '<${symbol}0.01';
    final sign = value < 0 && rounded > 0 ? minus : '';
    return '$sign$symbol${_grouped.format(rounded)}';
  }

  /// A value shown beside its currency's code rather than a symbol, as on
  /// Buy, where the currency may not be the dollar: `1,234.56`.
  static String number(double value) =>
      value.isFinite ? _grouped.format(value) : '--';

  /// [amount] split before the cents, so they can be drawn smaller:
  /// `$1,234` and `.56`. A value under a cent has no fraction part.
  static ({String whole, String fraction}) amountParts(double value) {
    final text = amount(value);
    final point = text.lastIndexOf('.');
    if (text.startsWith('<') || point < 0) return (whole: text, fraction: '');
    return (whole: text.substring(0, point), fraction: text.substring(point));
  }

  /// A change in value with its direction: `+$1.23`, `−$1.23`, `$0.00`.
  static String signedAmount(double value) {
    if (!value.isFinite) return '--';
    final rounded = _roundCents(value.abs());
    if (rounded == 0) return amount(0);
    return '${value > 0 ? '+' : minus}\$${_grouped.format(rounded)}';
  }

  /// A short value for a chart axis: `$950`, `$1.2K`, `−$3.4M`.
  static String compact(double value) {
    if (!value.isFinite) return '--';
    final text = _compact.format(value.abs());
    return value < 0 && text != _compact.format(0) ? '$minus$text' : text;
  }

  /// A change in percent: `+1.23%`, `−0.57%`, `0.00%`.
  static String percent(double value) {
    if (!value.isFinite) return '--';
    final rounded = _roundCents(value.abs());
    final sign = rounded == 0
        ? ''
        : value > 0
        ? '+'
        : minus;
    return '$sign${_grouped.format(rounded)}%';
  }

  /// A market price, with precision that follows its size: `$60,251.14`,
  /// `$0.31`, `$0.0412`, `$0.00052`, and from [collapseZerosFrom] zeros on,
  /// `$0.0₅5123`. Four significant digits are kept below a dollar.
  static String price(double value) => _price(value, spoken: false);

  /// [price] with any collapsed zeros spelt out, for screen readers.
  static String spokenPrice(double value) => _price(value, spoken: true);

  static String _price(double value, {required bool spoken}) {
    if (!value.isFinite) return '--';
    final sign = value < 0 ? (spoken ? '-' : minus) : '';
    final small = _smallFraction(value.abs());
    if (small == null) return '$sign\$${_grouped.format(value.abs())}';

    final (:zeros, :digits) = small;
    if (zeros >= collapseZerosFrom && !spoken) {
      return '$sign\$0.0${_subscript(zeros)}$digits';
    }
    final fraction = '${'0' * zeros}$digits';
    return '$sign\$0.${fraction.padRight(2, '0')}';
  }

  /// The zeros after the decimal point and up to four significant digits of a
  /// value under a dollar, once rounded; null for zero or a value that rounds
  /// to a dollar or more. Exponent form rounds and counts in one step, so
  /// `0.099996` is `0.10` rather than a carry into a lost digit.
  static ({int zeros, String digits})? _smallFraction(double abs) {
    if (abs == 0) return null;
    final parts = abs.toStringAsExponential(3).split('e');
    final exponent = int.parse(parts[1]);
    if (exponent >= 0) return null;
    final digits = parts[0]
        .replaceFirst('.', '')
        .replaceFirst(RegExp(r'0+$'), '');
    return (zeros: -exponent - 1, digits: digits);
  }

  static double _roundCents(double value) => (value * 100).round() / 100;

  static String _subscript(int number) => number
      .toString()
      .split('')
      .map((digit) => _subscriptDigits[int.parse(digit)])
      .join();
}
