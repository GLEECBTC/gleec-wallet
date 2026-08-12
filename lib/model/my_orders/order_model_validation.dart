import 'package:rational/rational.dart';
import 'package:web_dex/model/trading_entity_id.dart';

/// Bounded, throwing parsers for the `my_orders` payload.
///
/// The order list feeds the cancellation guard, so a field that survives
/// parsing is a field the client will act on. Every helper below rejects
/// rather than coerces: an order carrying a malformed UUID or a nonsense
/// amount is dropped by the caller instead of being shown as cancellable.
/// The bounds also stop a hostile or corrupted daemon reply from allocating
/// unbounded memory while it is being decoded.
const int maximumOrderRecords = 1000;
const int maximumOrderRelationships = 512;
const int maximumOrderTextLength = 128;
const int maximumOrderNumericLength = 128;

/// Upper bound on epoch values, in either seconds or milliseconds.
const int maximumOrderEpochMilliseconds = 8640000000000;

Map<String, dynamic> orderStringMap(Object? value, String field) {
  if (value is! Map) throw FormatException('Invalid $field');
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    throw FormatException('Invalid $field');
  }
}

/// A ticker or asset symbol. Rejects whitespace padding so that two spellings
/// of the same asset cannot compare unequal downstream.
String orderAssetSymbol(Object? value, String field) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 64 ||
      value.trim() != value ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value)) {
    throw FormatException('Invalid $field');
  }
  return value;
}

String orderBoundedText(
  Object? value,
  String field, {
  int maximum = maximumOrderTextLength,
  bool allowEmpty = true,
}) {
  if (value is! String ||
      (!allowEmpty && value.isEmpty) ||
      value.length > maximum ||
      value.trim() != value) {
    throw FormatException('Invalid $field');
  }
  return value;
}

/// A canonical trading UUID. [allowEmpty] covers optional relationship fields
/// that KDF omits or sends blank.
String orderUuid(Object? value, String field, {bool allowEmpty = false}) {
  if (allowEmpty && (value == null || value == '')) return '';
  final normalized = normalizeTradingEntityUuid(value);
  if (normalized == null) throw FormatException('Invalid $field');
  return normalized;
}

/// Prefers KDF's exact `*_fraction` form and falls back to the lossy decimal
/// string, rejecting either if it is unparseable or out of range.
Rational orderRational(
  Object? fraction,
  Object? decimal,
  String field, {
  bool allowZero = false,
}) {
  Rational? result;
  if (fraction is Map) {
    final values = orderStringMap(fraction, '$field fraction');
    final numerator = values['numer']?.toString();
    final denominator = values['denom']?.toString();
    if (_boundedInteger(numerator) && _boundedInteger(denominator)) {
      try {
        final parsedDenominator = BigInt.parse(denominator!);
        if (parsedDenominator != BigInt.zero) {
          result = Rational(BigInt.parse(numerator!), parsedDenominator);
        }
      } catch (_) {
        result = null;
      }
    }
  }
  if (result == null) {
    final value = decimal?.toString();
    if (value == null || value.length > maximumOrderNumericLength) {
      throw FormatException('Invalid $field');
    }
    result = Rational.tryParse(value);
  }
  if (result == null ||
      (allowZero ? result < Rational.zero : result <= Rational.zero)) {
    throw FormatException('Invalid $field');
  }
  return result;
}

int orderNonNegativeInt(
  Object? value,
  String field, {
  int maximum = maximumOrderEpochMilliseconds,
}) {
  final text = value?.toString();
  if (text == null ||
      text.isEmpty ||
      text.length > 20 ||
      !RegExp(r'^[0-9]+$').hasMatch(text)) {
    throw FormatException('Invalid $field');
  }
  final parsed = int.tryParse(text);
  if (parsed == null || parsed < 0 || parsed > maximum) {
    throw FormatException('Invalid $field');
  }
  return parsed;
}

bool orderBool(Object? value, String field) {
  if (value is! bool) throw FormatException('Invalid $field');
  return value;
}

Map<String, dynamic> boundedOrderMap(Object? value, String field) {
  if (value is! Map || value.length > maximumOrderRelationships) {
    throw FormatException('Invalid $field');
  }
  return orderStringMap(value, field);
}

List<dynamic> boundedOrderList(Object? value, String field) {
  if (value is! List || value.length > maximumOrderRelationships) {
    throw FormatException('Invalid $field');
  }
  return value;
}

bool _boundedInteger(String? value) {
  return value != null &&
      value.isNotEmpty &&
      value.length <= maximumOrderNumericLength &&
      RegExp(r'^-?[0-9]+$').hasMatch(value);
}
