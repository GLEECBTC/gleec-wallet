import 'package:decimal/decimal.dart';

final _thousand = Decimal.fromInt(1000);

/// unit tests: [testFormatListBalance]
///
/// A held balance for a list row: grouped, with precision that follows its
/// magnitude (2 decimals from 1,000, 4 from 1, else 4 past the leading zeros,
/// at most 8), rounded towards zero so a row never shows more than is held.
/// The same rules as the swap screens' amounts.
String formatListBalance(double balance) {
  if (!balance.isFinite) return '--';
  if (balance == 0) return '0';

  // `toString` is the shortest exact round trip, so 0.3 stays 0.3 rather
  // than the 0.29999… that rounding down a wider expansion would show.
  final value = Decimal.parse(balance.toString());
  final abs = value.abs();
  final decimals = abs >= _thousand
      ? 2
      : abs >= Decimal.one
      ? 4
      : (_leadingFractionZeros(abs) + 4).clamp(0, 8);
  final rounded = value >= Decimal.zero
      ? value.floor(scale: decimals)
      : value.ceil(scale: decimals);
  if (rounded == Decimal.zero) {
    return '< ${_trim(Decimal.one.shift(-decimals).toStringAsFixed(decimals))}';
  }
  return _group(_trim(rounded.toStringAsFixed(decimals)));
}

int _leadingFractionZeros(Decimal abs) {
  var zeros = 0;
  var probe = abs;
  while (probe < Decimal.one && zeros < 18) {
    probe = probe * Decimal.ten;
    if (probe < Decimal.one) zeros++;
  }
  return zeros;
}

String _trim(String fixed) {
  if (!fixed.contains('.')) return fixed;
  var result = fixed.replaceFirst(RegExp(r'0+$'), '');
  if (result.endsWith('.')) result = result.substring(0, result.length - 1);
  return result;
}

String _group(String plain) {
  final negative = plain.startsWith('-');
  final unsigned = negative ? plain.substring(1) : plain;
  final parts = unsigned.split('.');
  final digits = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  final grouped = parts.length > 1 ? '$buffer.${parts[1]}' : buffer.toString();
  return negative ? '-$grouped' : grouped;
}
