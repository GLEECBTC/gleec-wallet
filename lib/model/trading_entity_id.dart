final RegExp _canonicalTradingUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
  r'[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Returns the lowercase canonical representation of KDF's hyphenated UUID
/// contract, or `null` for malformed/oversized daemon or route values.
String? normalizeTradingEntityUuid(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim().toLowerCase();
  return _canonicalTradingUuid.hasMatch(normalized) ? normalized : null;
}
