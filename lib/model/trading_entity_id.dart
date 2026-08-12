final RegExp _canonicalTradingUuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
  r'[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// Returns the lowercase canonical representation of KDF's hyphenated UUID
/// contract, or `null` for malformed/oversized daemon values.
///
/// Trading guards compare order and swap identities across snapshots that
/// arrive from different RPCs, so they must agree on one spelling. Anything
/// that is not a well-formed UUID is rejected rather than normalised, so a
/// malformed identity can never match a real order or swap.
String? normalizeTradingEntityUuid(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim().toLowerCase();
  return _canonicalTradingUuid.hasMatch(normalized) ? normalized : null;
}
