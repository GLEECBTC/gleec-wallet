import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_request.dart';
import 'package:web_dex/model/text_error.dart';

class TradePreimageNotSufficientBalanceError implements BaseError {
  TradePreimageNotSufficientBalanceError({
    required this.coin,
    required this.available,
    required this.required,
    required this.lockedBySwaps,
    required this.error,
  });

  factory TradePreimageNotSufficientBalanceError.fromJson(
    Map<String, dynamic> json,
  ) {
    return TradePreimageNotSufficientBalanceError(
      coin: json['error_data']['coin'],
      available: json['error_data']['available'],
      required: json['error_data']['required'],
      lockedBySwaps: json['error_data']['locked_by_swaps'],
      error: json['error'],
    );
  }
  static String type = 'NotSufficientBalance';
  final String coin;
  final String available;
  final String required;
  final String? lockedBySwaps;
  final String error;

  @override
  String get message => error;
}

class TradePreimageNotSufficientBaseCoinBalanceError implements BaseError {
  TradePreimageNotSufficientBaseCoinBalanceError({
    required this.coin,
    required this.available,
    required this.required,
    required this.lockedBySwaps,
    required this.error,
  });

  factory TradePreimageNotSufficientBaseCoinBalanceError.fromJson(
    Map<String, dynamic> json,
  ) {
    return TradePreimageNotSufficientBaseCoinBalanceError(
      coin: json['error_data']['coin'],
      available: json['error_data']['available'],
      required: json['error_data']['required'],
      lockedBySwaps: json['error_data']['locked_by_swaps'],
      error: json['error'],
    );
  }
  static String type = 'NotSufficientBaseCoinBalance';
  final String coin;
  final String available;
  final String required;
  final String lockedBySwaps;
  final String error;

  @override
  String get message => error;
}

class TradePreimageVolumeTooLowError implements BaseError {
  TradePreimageVolumeTooLowError({
    required this.coin,
    required this.volume,
    required this.threshold,
    required this.error,
  });
  factory TradePreimageVolumeTooLowError.fromJson(Map<String, dynamic> json) =>
      TradePreimageVolumeTooLowError(
        coin: json['error_data']['coin'],
        volume: json['error_data']['volume'],
        threshold: json['error_data']['threshold'],
        error: json['error'],
      );

  static String type = 'VolumeTooLow';
  final String coin;
  final String volume;
  final String threshold;
  final String error;
  @override
  String get message => error;
}

class TradePreimageNoSuchCoinError implements BaseError {
  TradePreimageNoSuchCoinError({required this.coin, required this.error});

  factory TradePreimageNoSuchCoinError.fromJson(Map<String, dynamic> json) =>
      TradePreimageNoSuchCoinError(
        coin: json['error_data']['coin'],
        error: json['error'],
      );

  static String type = 'NoSuchCoin';
  final String coin;
  final String error;

  @override
  String get message => error;
}

class TradePreimageCoinIsWalletOnlyError implements BaseError {
  TradePreimageCoinIsWalletOnlyError({required this.coin, required this.error});

  factory TradePreimageCoinIsWalletOnlyError.fromJson(
    Map<String, dynamic> json,
  ) => TradePreimageCoinIsWalletOnlyError(
    coin: json['error_data']['coin'],
    error: json['error'],
  );
  static String type = 'CoinIsWalletOnly';
  final String coin;
  final String error;

  @override
  String get message => error;
}

class TradePreimageBaseEqualRelError implements BaseError {
  TradePreimageBaseEqualRelError({required this.error});

  factory TradePreimageBaseEqualRelError.fromJson(Map<String, dynamic> json) =>
      TradePreimageBaseEqualRelError(error: json['error']);

  static String type = 'BaseEqualRel';
  final String error;

  @override
  String get message => error;
}

class TradePreimageInvalidParamError implements BaseError {
  TradePreimageInvalidParamError({
    required this.param,
    required this.reason,
    required this.error,
  });

  factory TradePreimageInvalidParamError.fromJson(Map<String, dynamic> json) =>
      TradePreimageInvalidParamError(
        param: json['error_data']['param'],
        reason: json['error_data']['reason'],
        error: json['error'],
      );

  static String type = 'InvalidParam';
  final String param;
  final String reason;
  final String error;

  @override
  String get message => error;
}

class TradePreimagePriceTooLowError implements BaseError {
  TradePreimagePriceTooLowError({
    required this.price,
    required this.threshold,
    required this.error,
  });

  factory TradePreimagePriceTooLowError.fromJson(Map<String, dynamic> json) =>
      TradePreimagePriceTooLowError(
        price: json['error_data']['price'],
        threshold: json['error_data']['threshold'],
        error: json['error'],
      );

  static String type = 'PriceTooLow';
  final String price;
  final String threshold;
  final String error;

  @override
  String get message => error;
}

class TradePreimageTransportError implements BaseError {
  TradePreimageTransportError({required this.error});
  factory TradePreimageTransportError.fromJson(Map<String, dynamic> json) =>
      TradePreimageTransportError(error: json['error']);
  static String type = 'Transport';
  final String error;

  @override
  String get message => error;
}

class TradePreimageInternalError implements BaseError {
  TradePreimageInternalError({required this.error});
  factory TradePreimageInternalError.fromJson(Map<String, dynamic> json) =>
      TradePreimageInternalError(error: json['error']);

  static String type = 'InternalError';
  final String error;

  @override
  String get message => error;
}

class TradePreimageErrorFactory implements ErrorFactory<TradePreimageRequest> {
  Map<String, BaseError Function(Map<String, dynamic>)> errors = {
    TradePreimageNotSufficientBalanceError.type: (json) =>
        TradePreimageNotSufficientBalanceError.fromJson(json),
    TradePreimageNotSufficientBaseCoinBalanceError.type: (json) =>
        TradePreimageNotSufficientBaseCoinBalanceError.fromJson(json),
    TradePreimageVolumeTooLowError.type: (json) =>
        TradePreimageVolumeTooLowError.fromJson(json),
    TradePreimageNoSuchCoinError.type: (json) =>
        TradePreimageNoSuchCoinError.fromJson(json),
    TradePreimageCoinIsWalletOnlyError.type: (json) =>
        TradePreimageCoinIsWalletOnlyError.fromJson(json),
    TradePreimageBaseEqualRelError.type: (json) =>
        TradePreimageBaseEqualRelError.fromJson(json),
    TradePreimageInvalidParamError.type: (json) =>
        TradePreimageInvalidParamError.fromJson(json),
    TradePreimagePriceTooLowError.type: (json) =>
        TradePreimagePriceTooLowError.fromJson(json),
    TradePreimageTransportError.type: (json) =>
        TradePreimageTransportError.fromJson(json),
  };

  @override
  BaseError getError(Map<String, dynamic> json, TradePreimageRequest request) {
    final BaseError Function(Map<String, dynamic>)? errorFactory =
        errors[json['error_type']];

    if (errorFactory == null) {
      return TextError(error: 'Something went wrong!');
    }
    final BaseError error = errorFactory(json);
    return error;
  }
}

TradePreimageErrorFactory tradePreimageErrorFactory =
    TradePreimageErrorFactory();
