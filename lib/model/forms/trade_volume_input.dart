import 'package:formz/formz.dart';

enum TradeVolumeValidationError {
  /// The percentage is invalid
  invalidPercentage,
}

/// Formz input for the trade volume limit.
class TradeVolumeInput extends FormzInput<double, TradeVolumeValidationError> {
  const TradeVolumeInput.pure(super.value) : super.pure();
  const TradeVolumeInput.dirty(super.value) : super.dirty();

  @override
  TradeVolumeValidationError? validator(double value) {
    if (!value.isFinite || value <= 0.0 || value > 1.0) {
      return TradeVolumeValidationError.invalidPercentage;
    }
    return null;
  }
}
