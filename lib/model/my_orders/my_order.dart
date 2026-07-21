import 'package:rational/rational.dart';

class MyOrder {
  MyOrder({
    required this.base,
    required this.orderType,
    required this.rel,
    required this.relAmount,
    required this.uuid,
    required this.baseAmount,
    required this.createdAt,
    required this.cancelable,
    List<String>? startedSwaps,
    this.baseAmountAvailable,
    this.relAmountAvailable,
    this.minVolume,
  }) : startedSwaps = startedSwaps == null
           ? null
           : List<String>.unmodifiable(startedSwaps);

  final String base;
  final Rational baseAmount;
  final Rational? baseAmountAvailable;
  final String rel;
  final TradeSide orderType;
  final Rational relAmount;
  final Rational? relAmountAvailable;
  final String uuid;
  final int createdAt;
  final bool cancelable;
  final double? minVolume;
  final List<String>? startedSwaps;
  int get orderMatchingTime {
    final resetTimeInSeconds =
        30 -
        DateTime.now()
            .subtract(Duration(milliseconds: createdAt * 1000))
            .second;

    return resetTimeInSeconds < 0 ? 0 : resetTimeInSeconds;
  }

  double get price {
    final base = baseAmount.toDouble();
    final rel = relAmount.toDouble();
    if (!base.isFinite || !rel.isFinite || base <= 0 || rel <= 0) return 0;
    final result = base / rel;
    return result.isFinite && result > 0 ? result : 0;
  }
}

enum TradeSide { maker, taker }
