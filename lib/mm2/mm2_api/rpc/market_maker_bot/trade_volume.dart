import 'package:equatable/equatable.dart';
import 'package:web_dex/views/market_maker_bot/trade_volume_type.dart';

/// The trade volume for the market maker bot.
class TradeVolume extends Equatable {
  factory TradeVolume({
    TradeVolumeType type = TradeVolumeType.usd,
    required double value,
  }) {
    _validate(type, value);
    return TradeVolume._(type: type, value: value);
  }

  const TradeVolume._({required this.type, required this.value});

  /// A deliberately generous ceiling that still rejects values which cannot
  /// represent a plausible order and could overflow downstream arithmetic.
  static const double maximumUsdValue = 1000000000000000;
  static const int maximumEncodedNumberLength = 128;

  /// Creates a trade volume with the [type] set to [TradeVolumeType.percentage]
  /// with the given [value].
  factory TradeVolume.percentage(double value) =>
      TradeVolume(type: TradeVolumeType.percentage, value: value);

  /// The value of the trade volume limit.
  final double value;

  /// The type of the trade volume limit. E.g. percentage or usd.
  final TradeVolumeType type;

  factory TradeVolume.fromJson(Map<String, dynamic> json) {
    final hasPercentage = json['percentage'] != null;
    final hasUsd = json['usd'] != null;

    if (hasPercentage == hasUsd) {
      throw const FormatException(
        'Trade volume must contain exactly one supported value',
      );
    }

    final type = hasPercentage
        ? TradeVolumeType.percentage
        : TradeVolumeType.usd;
    final value = _parseNumber(
      hasPercentage ? json['percentage'] : json['usd'],
    );

    return TradeVolume(type: type, value: value);
  }

  static double _parseNumber(Object? rawValue) {
    final double? parsed;
    if (rawValue is num) {
      parsed = rawValue.toDouble();
    } else if (rawValue is String &&
        rawValue.isNotEmpty &&
        rawValue.length <= maximumEncodedNumberLength &&
        rawValue == rawValue.trim()) {
      parsed = double.tryParse(rawValue);
    } else {
      parsed = null;
    }

    if (parsed == null || !parsed.isFinite) {
      throw const FormatException('Invalid trade volume');
    }
    return parsed;
  }

  static void _validate(TradeVolumeType type, double value) {
    if (!value.isFinite || value <= 0) {
      throw const FormatException('Invalid trade volume');
    }
    if (type == TradeVolumeType.percentage && value > 1) {
      throw const FormatException('Invalid percentage trade volume');
    }
    if (type == TradeVolumeType.usd && value > maximumUsdValue) {
      throw const FormatException('Invalid USD trade volume');
    }
  }

  Map<String, dynamic> toJson() => {
    'percentage': type == TradeVolumeType.percentage ? value.toString() : null,
    'usd': type == TradeVolumeType.usd ? value.toString() : null,
  }..removeWhere((_, value) => value == null);

  TradeVolume copyWith({double? value, TradeVolumeType? type}) {
    return TradeVolume(value: value ?? this.value, type: type ?? this.type);
  }

  @override
  List<Object?> get props => [value, type];
}
