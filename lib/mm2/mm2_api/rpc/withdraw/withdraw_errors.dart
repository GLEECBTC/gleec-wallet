import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/text_error.dart';

abstract class ErrorNeedsSetCoinAbbr {
  void setCoinAbbr(String coinAbbr);
}

class WithdrawNotSufficientBalanceError implements BaseError {
  WithdrawNotSufficientBalanceError({
    required String coin,
    required String availableAmount,
    required String requiredAmount,
  }) : _coin = coin,
       _availableAmount = availableAmount,
       _requiredAmount = requiredAmount;
  factory WithdrawNotSufficientBalanceError.fromJson(
    Map<String, dynamic> json,
  ) {
    return WithdrawNotSufficientBalanceError(
      coin: json['error_data']['coin'],
      availableAmount: json['error_data']['available'],
      requiredAmount: json['error_data']['required'],
    );
  }

  String _coin;
  String _availableAmount;
  String _requiredAmount;

  static const String type = 'NotSufficientBalance';

  @override
  String get message {
    return LocaleKeys.withdrawNotSufficientBalanceError.tr(
      args: [_coin, _availableAmount, _requiredAmount],
    );
  }
}

class WithdrawZeroBalanceToWithdrawMaxError
    implements BaseError, ErrorNeedsSetCoinAbbr {
  WithdrawZeroBalanceToWithdrawMaxError();
  factory WithdrawZeroBalanceToWithdrawMaxError.fromJson(
    Map<String, dynamic> json,
  ) => WithdrawZeroBalanceToWithdrawMaxError();

  late String _coin;

  static const String type = 'ZeroBalanceToWithdrawMax';

  @override
  String get message {
    return LocaleKeys.withdrawZeroBalanceError.tr(args: [_coin]);
  }

  @override
  void setCoinAbbr(String coinAbbr) {
    _coin = coinAbbr;
  }
}

class WithdrawAmountTooLowError implements BaseError, ErrorNeedsSetCoinAbbr {
  WithdrawAmountTooLowError({required String amount, required String threshold})
    : _amount = amount,
      _threshold = threshold;

  factory WithdrawAmountTooLowError.fromJson(Map<String, dynamic> json) =>
      WithdrawAmountTooLowError(
        amount: json['error_data']['amount'],
        threshold: json['error_data']['threshold'],
      );

  static const String type = 'AmountTooLow';
  late String _coin;
  String _amount;
  String _threshold;

  @override
  String get message {
    return LocaleKeys.withdrawAmountTooLowError.tr(
      args: [_amount, _coin, _threshold, _coin],
    );
  }

  @override
  void setCoinAbbr(String coinAbbr) {
    _coin = coinAbbr;
  }
}

class WithdrawInvalidAddressError implements BaseError {
  WithdrawInvalidAddressError({required String error}) : _error = error;

  factory WithdrawInvalidAddressError.fromJson(Map<String, dynamic> json) =>
      WithdrawInvalidAddressError(error: json['error']);

  static const String type = 'InvalidAddress';
  String _error;

  @override
  String get message {
    return _error;
  }
}

class WithdrawInvalidFeePolicyError implements BaseError {
  WithdrawInvalidFeePolicyError({required String error}) : _error = error;
  factory WithdrawInvalidFeePolicyError.fromJson(Map<String, dynamic> json) =>
      WithdrawInvalidFeePolicyError(error: json['error']);

  String _error;
  static const String type = 'InvalidFeePolicy';

  @override
  String get message {
    return _error;
  }
}

class WithdrawNoSuchCoinError implements BaseError {
  WithdrawNoSuchCoinError({required String coin}) : _coin = coin;

  factory WithdrawNoSuchCoinError.fromJson(Map<String, dynamic> json) =>
      WithdrawNoSuchCoinError(coin: json['error_data']['coin']);

  String _coin;

  static const String type = 'NoSuchCoin';

  @override
  String get message {
    return LocaleKeys.withdrawNoSuchCoinError.tr(args: [_coin]);
  }
}

class WithdrawTransportError
    with ErrorWithDetails
    implements BaseError, ErrorNeedsSetCoinAbbr {
  WithdrawTransportError({required String error, String? feeCoin})
    : _error = error,
      _feeCoin = feeCoin;

  factory WithdrawTransportError.fromJson(Map<String, dynamic> json) {
    return WithdrawTransportError(error: json['error'] ?? '');
  }

  final String _error;
  String? _feeCoin;

  static const String type = 'Transport';

  @override
  String get message {
    final hasFeeCoin = _feeCoin != null && _feeCoin!.isNotEmpty;

    if (isGasPaymentError && hasFeeCoin) {
      return '${LocaleKeys.withdrawNotEnoughBalanceForGasError.tr(args: [_feeCoin!])}.';
    }

    if (_error.isNotEmpty &&
        _error.contains('insufficient funds for transfer') &&
        hasFeeCoin) {
      return LocaleKeys.withdrawNotEnoughBalanceForGasError.tr(
        args: [_feeCoin!],
      );
    }

    return LocaleKeys.somethingWrong.tr();
  }

  bool get isGasPaymentError {
    return _error.isNotEmpty &&
        (_error.contains('gas required exceeds allowance') ||
            _error.contains('insufficient funds for transfer'));
  }

  @override
  String get details {
    if (isGasPaymentError) {
      return '';
    }
    return _error;
  }

  @override
  void setCoinAbbr(String coinAbbr) {
    final maybeCoin = GetIt.I<KomodoDefiSdk>().assets
        .findAssetsByConfigId(coinAbbr)
        .singleOrNull;

    if (maybeCoin == null) {
      return;
    }
    final maybePlatform = maybeCoin.id.parentId?.id;

    _feeCoin = maybePlatform ?? coinAbbr;
  }
}

class WithdrawInternalError with ErrorWithDetails implements BaseError {
  WithdrawInternalError({required String error}) : _error = error;

  factory WithdrawInternalError.fromJson(Map<String, dynamic> json) =>
      WithdrawInternalError(error: json['error']);

  String _error;

  static const String type = 'InternalError';

  @override
  String get message {
    return LocaleKeys.somethingWrong.tr();
  }

  @override
  String get details {
    return _error;
  }
}

class WithdrawErrorFactory implements ErrorFactory<String> {
  @override
  BaseError getError(Map<String, dynamic> json, String coinAbbr) {
    final BaseError error = _parseError(json);
    if (error is ErrorNeedsSetCoinAbbr) {
      (error as ErrorNeedsSetCoinAbbr).setCoinAbbr(coinAbbr);
    }
    return error;
  }

  BaseError _parseError(Map<String, dynamic> json) {
    switch (json['error_type']) {
      case WithdrawNotSufficientBalanceError.type:
        return WithdrawNotSufficientBalanceError.fromJson(json);
      case WithdrawZeroBalanceToWithdrawMaxError.type:
        return WithdrawZeroBalanceToWithdrawMaxError.fromJson(json);
      case WithdrawAmountTooLowError.type:
        return WithdrawAmountTooLowError.fromJson(json);
      case WithdrawInvalidAddressError.type:
        return WithdrawInvalidAddressError.fromJson(json);
      case WithdrawInvalidFeePolicyError.type:
        return WithdrawInvalidFeePolicyError.fromJson(json);
      case WithdrawNoSuchCoinError.type:
        return WithdrawNoSuchCoinError.fromJson(json);
      case WithdrawTransportError.type:
        return WithdrawTransportError.fromJson(json);
      case WithdrawInternalError.type:
        return WithdrawInternalError.fromJson(json);
    }
    return TextError(error: LocaleKeys.somethingWrong.tr());
  }
}

WithdrawErrorFactory withdrawErrorFactory = WithdrawErrorFactory();
