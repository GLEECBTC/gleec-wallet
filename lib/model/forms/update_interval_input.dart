import 'package:formz/formz.dart';
import 'package:web_dex/views/market_maker_bot/trade_bot_update_interval.dart';

enum UpdateIntervalValidationError {
  /// Input is empty
  empty,

  /// Not a valid number
  invalid,

  /// Number is negative
  negative,

  /// Number is too low
  tooLow,
}

class UpdateIntervalInput
    extends FormzInput<String, UpdateIntervalValidationError> {
  const UpdateIntervalInput.pure() : super.pure('300');
  const UpdateIntervalInput.dirty([super.value = '300']) : super.dirty();

  TradeBotUpdateInterval get interval =>
      TradeBotUpdateInterval.fromString(value);

  @override
  UpdateIntervalValidationError? validator(String value) {
    if (value.isEmpty) {
      return UpdateIntervalValidationError.empty;
    }

    if (value.length > 16 || value != value.trim()) {
      return UpdateIntervalValidationError.invalid;
    }

    final interval = int.tryParse(value);
    if (interval == null) {
      return UpdateIntervalValidationError.invalid;
    }

    if (interval < 0) {
      return UpdateIntervalValidationError.negative;
    }

    if (interval < 60) {
      return UpdateIntervalValidationError.tooLow;
    }

    if (TradeBotUpdateInterval.tryFromSeconds(interval) == null) {
      return UpdateIntervalValidationError.invalid;
    }

    return null;
  }
}
