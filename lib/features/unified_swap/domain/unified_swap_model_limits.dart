/// Defensive limits for values crossing the KDF/provider trust boundary.
///
/// These are intentionally generous enough for opaque forward-compatible
/// identifiers while preventing a hostile journal or provider response from
/// retaining or rendering unbounded strings and nested collections.
abstract final class UnifiedSwapModelLimits {
  static const int discriminatorLength = 128;
  static const int derivationPathLength = 256;
  static const int identifierLength = 512;
  static const int digestLength = 512;
  static const int addressLength = 512;
  static const int textLength = 2048;
  static const int aggregateTextLength = 16384;
  static const int amountDigits = 256;

  static const int generalItems = 100;
  static const int activityItems = 1000;
  static const int routeStages = 32;
  static const int nestedItems = 32;
  static const int changedFields = 32;

  static bool isCanonicalString(
    String value, {
    int maximumLength = identifierLength,
  }) =>
      value.isNotEmpty &&
      value.trim() == value &&
      value.length <= maximumLength;

  static bool isOptionalCanonicalString(
    String? value, {
    int maximumLength = identifierLength,
  }) => value == null || isCanonicalString(value, maximumLength: maximumLength);

  static void requireString(
    String value,
    String name, {
    int maximumLength = identifierLength,
  }) {
    if (!isCanonicalString(value, maximumLength: maximumLength)) {
      throw ArgumentError.value(
        value,
        name,
        'Must be trimmed, non-empty, and at most $maximumLength characters',
      );
    }
  }

  static void requireOptionalString(
    String? value,
    String name, {
    int maximumLength = identifierLength,
  }) {
    if (!isOptionalCanonicalString(value, maximumLength: maximumLength)) {
      throw ArgumentError.value(
        value,
        name,
        'Must be null or trimmed, non-empty, and at most '
        '$maximumLength characters',
      );
    }
  }

  static void requireListLength(
    int length,
    String name, {
    int maximumLength = generalItems,
  }) {
    if (length > maximumLength) {
      throw RangeError.range(length, 0, maximumLength, '$name.length');
    }
  }

  static void requireRawDiscriminator(
    String? value,
    String name, {
    required bool isUnknown,
  }) {
    if (isUnknown) {
      requireString(value ?? '', name, maximumLength: discriminatorLength);
      return;
    }
    if (value != null) {
      throw ArgumentError.value(
        value,
        name,
        'Known variants must not retain a raw discriminator',
      );
    }
  }
}
