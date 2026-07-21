import 'package:formz/formz.dart';

enum TradeMarginValidationError {
  /// Input is empty
  empty,

  /// Not a valid number
  invalidNumber,

  /// Number is negative
  lessThanMinimum,

  /// Number is greater than 100
  greaterThanMaximum,
}

class TradeMarginInput extends FormzInput<String, TradeMarginValidationError> {
  final double min;
  final double max;

  const TradeMarginInput.pure({this.min = 0, this.max = 1000})
    : super.pure('3');
  const TradeMarginInput.dirty(super.value, {this.min = 0, this.max = 1000})
    : super.dirty();

  double get valueAsDouble {
    final parsed = double.tryParse(value);
    return parsed != null && parsed.isFinite ? parsed : 0;
  }

  @override
  TradeMarginValidationError? validator(String value) {
    if (value.isEmpty) {
      return TradeMarginValidationError.empty;
    }

    if (value.length > 64 || value != value.trim()) {
      return TradeMarginValidationError.invalidNumber;
    }

    final margin = double.tryParse(value);
    if (margin == null || !margin.isFinite) {
      return TradeMarginValidationError.invalidNumber;
    }

    if (margin <= min) {
      return TradeMarginValidationError.lessThanMinimum;
    }

    if (margin > max) {
      return TradeMarginValidationError.greaterThanMaximum;
    }

    return null;
  }
}
