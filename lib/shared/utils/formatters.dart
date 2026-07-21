import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

final List<TextInputFormatter> currencyInputFormatters = [
  // Parsing arbitrarily large pasted numerals into Rational/BigInt can block
  // the UI isolate. This comfortably exceeds every supported asset amount
  // while keeping all trading and transfer inputs computationally bounded.
  LengthLimitingTextInputFormatter(128),
  DecimalTextInputFormatter(decimalRange: decimalRange),
  FilteringTextInputFormatter.allow(numberRegExp),
];

class DurationLocalization {
  DurationLocalization({
    required this.milliseconds,
    required this.seconds,
    required this.minutes,
    required this.hours,
  });
  final String milliseconds;
  final String seconds;
  final String minutes;
  final String hours;
}

/// unit test: [testDurationFormat]
String durationFormat(
  Duration duration,
  DurationLocalization durationLocalization,
) {
  final int hh = duration.inHours;
  final int mm = duration.inMinutes.remainder(60);
  final int ss = duration.inSeconds.remainder(60);
  final int ms = duration.inMilliseconds;

  if (ms < 1000) return '$ms${durationLocalization.milliseconds}';

  final StringBuffer output = StringBuffer();
  if (hh > 0) {
    output.write('$hh${durationLocalization.hours} ');
  }
  if (mm > 0 || output.isNotEmpty) {
    output.write('$mm${durationLocalization.minutes} ');
  }
  output.write('$ss${durationLocalization.seconds}');

  return output.toString().trim();
}

/// unit test: [testNumberWithoutExponent]
String getNumberWithoutExponent(String value) {
  try {
    return Rational.parse(
      value,
    ).toDecimal(scaleOnInfinitePrecision: 10).toString();
  } catch (_) {
    return value;
  }
}

/// unit tests: [testTruncateDecimal]
///
/// Suggestion: @DmitriiP:
///
// if (decimalRange < 0) {
//   return value;
// }

// final String withoutExponent = getNumberWithoutExponent(value);
// int dotIndex = withoutExponent.indexOf(".");
// int endIndex = dotIndex + decimalRange + 1;
// endIndex = math.min(endIndex, withoutExponent.length);

// return withoutExponent.substring(0, endIndex);
String truncateDecimal(String value, int decimalRange) {
  if (decimalRange < 0) {
    return value;
  }
  final String withoutExponent = getNumberWithoutExponent(value);
  final List<String> temp = withoutExponent.split('.');
  if (temp.length == 1) {
    return value;
  }
  if (decimalRange == 0) {
    return temp[0];
  }
  final String truncatedDecimals = temp[1].length < decimalRange
      ? temp[1]
      : temp[1].substring(0, decimalRange);

  return '${temp[0]}.$truncatedDecimals';
}

/// unit test: [testDecimalTextInputFormatter]
class DecimalTextInputFormatter extends TextInputFormatter {
  DecimalTextInputFormatter({this.decimalRange = 0}) : assert(decimalRange > 0);
  final int decimalRange;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == newValue.text) {
      return newValue;
    }
    TextSelection newSelection = newValue.selection;
    String truncated = newValue.text.replaceAll(',', '.');

    final String value = newValue.text;

    if (value.contains('.') &&
        value.substring(value.indexOf('.') + 1).length > decimalRange) {
      truncated = oldValue.text.isNotEmpty
          ? oldValue.text
          : truncateDecimal(newValue.text, decimalRange);
      newSelection = oldValue.selection;
    } else if (value == '.' || value == ',') {
      truncated = '0.';

      newSelection = newValue.selection.copyWith(
        baseOffset: math.min(truncated.length, truncated.length + 1),
        extentOffset: math.min(truncated.length, truncated.length + 1),
      );
    }

    return TextEditingValue(text: truncated, selection: newSelection);
  }
}

const _maxTimestampMillisecond = 8640000000000000;
const _minTimestampMillisecond = -8639999999999999;

/// unit tests: [testFormattedDate]
String getFormattedDate(int timestamp, [bool isUtc = false]) {
  final timestampMilliseconds = timestamp * 1000;
  if (timestampMilliseconds < _minTimestampMillisecond ||
      timestampMilliseconds > _maxTimestampMillisecond) {
    return 'Date is out of the range';
  }
  final dateTime = DateTime.fromMillisecondsSinceEpoch(
    timestampMilliseconds,
    isUtc: isUtc,
  );
  if (dateTime.year < 0) {
    return '${DateFormat('dd MMM yyyy, HH:mm', 'en_US').format(dateTime)} BC';
  }
  return DateFormat('dd MMM yyyy, HH:mm', 'en_US').format(dateTime);
}

/// unit tests: [testCutLeadingZeros]
String cutTrailingZeros(String str) {
  String loop(String input) {
    if (input.length == 1) return input;
    if (!input.contains('.')) return input;

    if (input[input.length - 1] == '0' || input[input.length - 1] == '.') {
      input = input.substring(0, input.length - 1);
      return loop(input);
    } else {
      return input;
    }
  }

  return loop(str);
}

/// unit tests: [testFormatDexAmount]
String formatDexAmt(dynamic amount) {
  if (amount == null) return '';

  switch (amount) {
    case final double value:
      return cutTrailingZeros(value.toStringAsFixed(8));
    case final Rational value:
      return cutTrailingZeros(
        value
            .toDecimal(scaleOnInfinitePrecision: scaleOnInfinitePrecision)
            .toStringAsFixed(8),
      );
    case final String value:
      return cutTrailingZeros(double.parse(value).toStringAsFixed(8));
    case final int value:
      return cutTrailingZeros(value.toDouble().toStringAsFixed(2));
    default:
      return amount.toString();
  }
}

const maxDigits = 12;
const fractionDigits = 2;
const significantDigits = 2;

/// 1e-[maxDigits]
const minNumber = 1e-12;

/// 1e+[maxDigits]
const maxNumber = 1e+12;

/// unit test: [testFormatAmount]
/// We show 11 digits after dot if value in e+ notation
/// We show only 2 digit after zeros if we have small value greater then minNumber
String formatAmt(double value) {
  if (!value.isFinite) return 'infinity';
  if (value == 0) return '0.00';

  final sign = value < 0 ? '-' : '';
  final valueAbs = value.abs();

  if (valueAbs > maxNumber) {
    return sign + valueAbs.toStringAsPrecision(maxDigits);
  }

  if (valueAbs < minNumber) {
    final valueString = '$valueAbs';
    final precisionString = valueAbs.toStringAsPrecision(maxDigits);
    if (valueString.length < precisionString.length) {
      return sign + valueString;
    }
    return sign + precisionString;
  }

  final leadingZeros = getLeadingZeros(valueAbs);

  if (leadingZeros > 0) {
    String result = valueAbs.toStringAsFixed(leadingZeros + significantDigits);
    while (result.endsWith('0') && result.length > 4) {
      result = result.substring(0, result.length - 1);
    }
    return sign + result;
  }

  final String rounded = valueAbs.toStringAsFixed(fractionDigits);

  if (rounded.length <= (maxDigits + 1)) {
    return sign + rounded;
  }
  return sign + valueAbs.toStringAsPrecision(maxDigits);
}

const tenBillion = 1e+10;
const billion = 1e+9;
const lowAmount = 1e-8;
const thousand = 1000;
const one = 1;

final hugeFormatter = NumberFormat.compactLong();
final billionFormatter = NumberFormat.decimalPattern();
final thousandFormatter = NumberFormat('###,###,###,###', 'en_US');
final oneFormatter = NumberFormat('###,###,###,###.00', 'en_US');

/// unit tests: [testToStringAmount]
/// Main idea is to keep length of value less then 13 symbols
/// include dots, commas, space and e-notation
///
/// Reference is https://www.binance.com/en/markets/overview
///
/// Use this sparingly in UIs as it can clutter the UI with too much information.
String toStringAmount(double amount, [int? digits]) {
  switch (amount) {
    case >= tenBillion:
      final billionsAmount = amount / billion;
      final newFormat = billionsAmount.toStringAsFixed(2);
      final billionCount = newFormat.split('.').first.length;
      if (billionCount >= 2) {
        return hugeFormatter.format(amount);
      }
      return billionFormatter.format(amount.round());
    case >= thousand:
      return thousandFormatter.format(amount);
    case >= one:
      return oneFormatter.format(amount);
    case >= lowAmount:
      String pattern = '0.00######';
      if (digits != null) {
        pattern = "0.00${List.filled(digits - 2, "#").join()}";
      }
      return NumberFormat(pattern, 'en_US').format(amount);
  }
  return amount.toStringAsPrecision(4);
}

/// Calculates the number of leading zeros required for the decimal representation of [value].
/// Parameters:
/// - [value] (double): The value for which the number of leading zeros needs to be calculated.
///
/// Return Value:
/// - (int): The number of leading zeros required for the decimal representation of [value].
///
/// Example Usage:
/// ```dart
/// double input = 0.01234;
/// int leadingZeros = getLeadingZeros(input);
/// print(leadingZeros); // Output: 2 (approximately)
/// ```
/// unit test: [testLeadingZeros]
int getLeadingZeros(double value) =>
    ((1 / math.ln10) * math.log(1 / value)).floor();

void formatAmountInput(TextEditingController controller, Rational? value) {
  final String currentText = controller.text;
  if (currentText.isNotEmpty && Rational.parse(currentText) == value) return;

  final newText = value == null
      ? ''
      : cutTrailingZeros(
          value
              .toDecimal(scaleOnInfinitePrecision: scaleOnInfinitePrecision)
              .toStringAsFixed(8),
        );
  controller.value = TextEditingValue(
    text: newText,
    selection: TextSelection.collapsed(offset: newText.length),
  );
}

/// Truncates a given [text] by removing middle characters, retaining start and end characters.
/// Parameters:
/// - [text] (String): The input text to be truncated.
/// - [startSymbolsCount] (int?): The number of characters to retain at the beginning of the [text].
/// - [endCount] (int): The number of characters to retain at the end of the [text]. Default is 7.
///
/// Return Value:
/// - (String): The truncated text with start and end characters retained and middle characters replaced by '...'.
///
/// Example Usage:
/// ```dart
/// String input1 = '0x8f76543210abcdef';
/// String result1 = truncateMiddleSymbols(input1);
/// print(result1); // Output: "0x8f76...cdef"
/// ```
/// ```dart
/// String input2 = '1234567890';
/// String result2 = truncateMiddleSymbols(input2, 2, 3);
/// print(result2); // Output: "12...890"
/// ```
/// unit tests: [testTruncateHash]
String truncateMiddleSymbols(
  String text, [
  int? startSymbolsCount,
  int endCount = 7,
]) {
  final int startCount = startSymbolsCount ?? (text.startsWith('0x') ? 6 : 4);
  if (text.length <= startCount + endCount + 3) return text;
  final String firstPart = text.substring(0, startCount);
  final String secondPart = text.substring(text.length - endCount, text.length);
  return '$firstPart...$secondPart';
}

String formatTransactionDateTime(Transaction tx) {
  if (tx.timestamp == DateTime.fromMillisecondsSinceEpoch(0) &&
      tx.confirmations == 0) {
    return 'Unconfirmed';
  } else if (tx.timestamp == DateTime.fromMillisecondsSinceEpoch(0) &&
      tx.confirmations > 0) {
    return 'Now';
  } else {
    return DateFormat('dd MMM yyyy HH:mm').format(tx.timestamp);
  }
}

/// Will be removed in the near future in favour of a user-configurable
/// currency/asset.
String formatUsdValue(double? value) {
  if (value == null) return '\$0.00';
  return '\$${formatAmt(value)}';
}

/// Normalizes a decimal string to use dot as decimal separator, handling
/// locale-specific formats (comma as decimal separator, various grouping
/// separators).
///
/// This function:
/// - Trims whitespace
/// - Removes grouping separators (spaces, NBSP, NNBSP, apostrophes, underscores)
/// - Handles mixed separators (last occurrence of comma/dot is decimal separator)
/// - Converts leading comma/dot to "0."
/// - Validates the result contains only digits and at most one decimal separator
///
/// Examples:
/// - "1,23" -> "1.23"
/// - "1.234,56" -> "1234.56" (European format)
/// - "1,234.56" -> "1234.56" (US format)
/// - "1 234,56" -> "1234.56" (French format with space grouping)
/// - ",5" -> "0.5"
/// - ".5" -> "0.5"
///
/// Returns normalized string or throws FormatException if invalid.
String normalizeDecimalString(String raw) {
  if (raw.isEmpty) {
    throw const FormatException('Empty string cannot be normalized');
  }

  // Trim whitespace
  String normalized = raw.trim();

  // Remove grouping separators: regular space, NBSP (U+00A0), NNBSP (U+202F),
  // apostrophe, underscore
  normalized = normalized
      .replaceAll(' ', '')
      .replaceAll('\u00A0', '') // NBSP
      .replaceAll('\u202F', '') // NNBSP
      .replaceAll("'", '')
      .replaceAll('_', '');

  // Handle negative numbers (reject them for now as amounts should be positive)
  if (normalized.startsWith('-')) {
    throw const FormatException('Negative numbers are not allowed');
  }

  // Find positions of comma and dot
  final lastCommaIndex = normalized.lastIndexOf(',');
  final lastDotIndex = normalized.lastIndexOf('.');

  // If both comma and dot exist, the last one is the decimal separator
  if (lastCommaIndex != -1 && lastDotIndex != -1) {
    if (lastCommaIndex > lastDotIndex) {
      // Comma is decimal separator, remove all dots (thousands separators)
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else {
      // Dot is decimal separator, remove all commas (thousands separators)
      normalized = normalized.replaceAll(',', '');
    }
  } else if (lastCommaIndex != -1) {
    // Only comma exists, treat it as decimal separator
    normalized = normalized.replaceAll(',', '.');
  }
  // If only dot exists or neither exists, no change needed

  // Handle leading decimal separator: ",5" or ".5" -> "0.5"
  if (normalized.startsWith('.')) {
    normalized = '0$normalized';
  }

  // Validate: should only contain digits and at most one dot
  final dotCount = '.'.allMatches(normalized).length;
  if (dotCount > 1) {
    throw const FormatException('Multiple decimal separators found');
  }

  // Check if all characters are digits or a single dot
  final validPattern = RegExp(r'^\d+\.?\d*$');
  if (!validPattern.hasMatch(normalized)) {
    throw FormatException('Invalid number format: $normalized');
  }

  return normalized;
}

/// Parses a locale-aware decimal string to a Decimal, handling comma as
/// decimal separator and various grouping separators.
///
/// This is a convenience wrapper around [normalizeDecimalString] and
/// [Decimal.parse].
///
/// Examples:
/// - "1,23" -> Decimal(1.23)
/// - "1.234,56" -> Decimal(1234.56)
/// - "1,234.56" -> Decimal(1234.56)
///
/// Throws FormatException if the string cannot be parsed.
Decimal parseLocaleAwareDecimal(String raw) {
  final normalized = normalizeDecimalString(raw);
  return Decimal.parse(normalized);
}

/// Parses a locale-aware decimal string to a Rational, handling comma as
/// decimal separator and various grouping separators.
///
/// This is a convenience wrapper around [normalizeDecimalString] and
/// [Rational.parse].
///
/// Examples:
/// - "1,23" -> Rational(123, 100)
/// - "1.234,56" -> Rational(123456, 100)
///
/// Throws FormatException if the string cannot be parsed.
Rational parseLocaleAwareRational(String raw) {
  final normalized = normalizeDecimalString(raw);
  return Rational.parse(normalized);
}
