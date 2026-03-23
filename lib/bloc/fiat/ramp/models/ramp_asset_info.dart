import 'package:decimal/decimal.dart';

/// Represents information about a cryptocurrency asset available for purchase
/// through a ramp service.
///
/// Contains details about the asset such as its name, symbol, pricing information,
/// purchase limits, and network-specific attributes.
class RampAssetInfo {
  /// The full name of the cryptocurrency asset.
  final String name;

  /// The ticker symbol of the cryptocurrency asset.
  final String symbol;

  /// The number of decimal places used in the asset's smallest unit.
  final int decimals;

  /// Price information for the asset in various currencies.
  final Map<String, dynamic> price;

  /// Minimum amount that can be purchased, if applicable.
  /// Null or -1 indicates no minimum limit.
  final Decimal? minPurchaseAmount;

  /// Maximum amount that can be purchased, if applicable.
  /// Null or -1 indicates no maximum limit.
  final Decimal? maxPurchaseAmount;

  /// Blockchain address for the asset, if applicable.
  final String? address;

  /// The blockchain network on which this asset exists.
  final String chain;

  /// The currency code identifying this asset.
  final String currencyCode;

  /// Whether this asset is currently enabled for purchase.
  final bool enabled;

  /// Whether this asset should be hidden in user interfaces.
  final bool hidden;

  /// URL to the asset's logo image.
  final String logoUrl;

  /// Minimum cryptocurrency amount that can be purchased, expressed as a string.
  final String minPurchaseCryptoAmount;

  /// Network fee associated with transactions for this asset.
  final Decimal networkFee;

  /// Asset type classification (e.g., "crypto", "token").
  final String type;

  RampAssetInfo({
    required this.name,
    required this.symbol,
    required this.decimals,
    required this.price,
    required this.chain,
    required this.currencyCode,
    required this.enabled,
    required this.hidden,
    required this.logoUrl,
    required this.minPurchaseCryptoAmount,
    required this.networkFee,
    required this.type,
    this.minPurchaseAmount,
    this.maxPurchaseAmount,
    this.address,
  });

  /// Returns true if this asset has a valid minimum purchase amount.
  /// A value of -1 indicates no limit.
  bool hasValidMinPurchaseAmount() {
    if (minPurchaseAmount == null) return false;
    return minPurchaseAmount! > Decimal.fromInt(-1);
  }

  /// Returns true if this asset has a valid maximum purchase amount.
  /// A value of -1 indicates no limit.
  bool hasValidMaxPurchaseAmount() {
    if (maxPurchaseAmount == null) return false;
    return maxPurchaseAmount! > Decimal.fromInt(-1);
  }

  /// Creates a [RampAssetInfo] from a JSON object.
  ///
  /// Validates essential fields and parses values appropriately.
  ///
  /// Throws [ArgumentError] if required fields are missing or of incorrect type.
  /// Throws [FormatException] if decimal parsing fails.
  factory RampAssetInfo.fromJson(Map<String, dynamic> json) {
    // Validate required fields
    const requiredFields = [
      'name',
      'symbol',
      'decimals',
      'price',
      'chain',
      'currencyCode',
      'enabled',
      'hidden',
      'logoUrl',
      'minPurchaseCryptoAmount',
      'networkFee',
      'type',
    ];

    for (final field in requiredFields) {
      if (json[field] == null) {
        throw ArgumentError.notNull(field);
      }
    }

    // Validate types for critical fields
    if (json['price'] is! Map<String, dynamic>) {
      throw ArgumentError.value(
        json['price'],
        'price',
        'Must be a JSON object',
      );
    }

    if (json['decimals'] is! num) {
      throw ArgumentError.value(
        json['decimals'],
        'decimals',
        'Must be an integer',
      );
    }

    return RampAssetInfo(
      name: json['name'] as String,
      symbol: json['symbol'] as String,
      decimals: (json['decimals'] as num).toInt(),
      price: json['price'] as Map<String, dynamic>,
      minPurchaseAmount: json['minPurchaseAmount'] != null
          ? Decimal.tryParse(json['minPurchaseAmount'].toString())
          : null,
      maxPurchaseAmount: json['maxPurchaseAmount'] != null
          ? Decimal.tryParse(json['maxPurchaseAmount'].toString())
          : null,
      address: json['address'] as String?,
      chain: json['chain'] as String,
      currencyCode: json['currencyCode'] as String,
      enabled: json['enabled'] as bool,
      hidden: json['hidden'] as bool,
      logoUrl: json['logoUrl'] as String,
      minPurchaseCryptoAmount: json['minPurchaseCryptoAmount'] as String,
      networkFee: Decimal.parse(json['networkFee'].toString()),
      type: json['type'] as String,
    );
  }
}
