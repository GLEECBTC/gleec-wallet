import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/my_orders/my_order.dart';
import 'package:web_dex/model/trading_entity_id.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:equatable/equatable.dart';

const int _maximumSwapEvents = 512;
const int _maximumEventDefinitions = 128;
const int _maximumShortTextLength = 128;
const int _maximumEvidenceTextLength = 1024;
const int _maximumNumericTextLength = 128;
const int _maximumEpochMilliseconds = 8640000000000;
const int _maximumEpochSeconds = 8640000000;

class Swap extends Equatable {
  const Swap({
    required this.type,
    required this.uuid,
    required this.myOrderUuid,
    required this.events,
    required this.makerAmount,
    required this.makerCoin,
    required this.takerAmount,
    required this.takerCoin,
    required this.gui,
    required this.mmVersion,
    required this.successEvents,
    required this.errorEvents,
    this.myInfo,
    required this.recoverable,
  });

  factory Swap.fromJson(Map<String, dynamic> json) {
    final makerAmount = _positiveRational(
      json['maker_amount_fraction'],
      json['maker_amount'],
      'maker_amount',
    );
    final takerAmount = _positiveRational(
      json['taker_amount_fraction'],
      json['taker_amount'],
      'taker_amount',
    );
    final type = switch (json['type']) {
      'Taker' => TradeSide.taker,
      'Maker' => TradeSide.maker,
      _ => throw const FormatException('Invalid swap side'),
    };
    final uuid = normalizeTradingEntityUuid(json['uuid']);
    if (uuid == null) throw const FormatException('Invalid swap identifier');
    final rawOrderUuid = json['my_order_uuid'];
    final myOrderUuid = rawOrderUuid == null || rawOrderUuid == ''
        ? ''
        : normalizeTradingEntityUuid(rawOrderUuid) ?? '';
    final events = _recoverableSwapEvents(json['events']);
    final successEvents = _recoverableEventDefinitions(json['success_events']);
    final errorEvents = _recoverableEventDefinitions(json['error_events']);
    final recoverableValue = json['recoverable'];
    return Swap(
      type: type,
      uuid: uuid,
      myOrderUuid: myOrderUuid,
      events: events,
      makerAmount: makerAmount,
      makerCoin: _assetSymbol(json['maker_coin'], 'maker_coin'),
      takerAmount: takerAmount,
      takerCoin: _assetSymbol(json['taker_coin'], 'taker_coin'),
      gui: _recoverableShortText(json['gui']),
      mmVersion: _recoverableShortText(json['mm_version']),
      successEvents: successEvents,
      errorEvents: errorEvents,
      myInfo: _recoverableSwapMyInfo(json['my_info']),
      recoverable: recoverableValue is bool ? recoverableValue : false,
    );
  }

  final TradeSide type;
  final String uuid;
  final String myOrderUuid;
  final List<SwapEventItem> events;
  final Rational makerAmount;
  final String makerCoin;
  final Rational takerAmount;
  final String takerCoin;
  final String gui;
  final String mmVersion;
  final List<String> successEvents;
  final List<String> errorEvents;
  final SwapMyInfo? myInfo;
  final bool recoverable;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};

    data['type'] = type == TradeSide.taker ? 'Taker' : 'Maker';
    data['uuid'] = uuid;
    data['my_order_uuid'] = myOrderUuid;
    data['events'] = events.map((e) => e.toJson()).toList();
    data['maker_amount'] = makerAmount.toDouble().toString();
    data['maker_amount_fraction'] = rat2fract(makerAmount);
    data['maker_coin'] = makerCoin;
    data['taker_amount'] = takerAmount.toDouble().toString();
    data['taker_amount_fraction'] = rat2fract(takerAmount);
    data['taker_coin'] = takerCoin;
    data['gui'] = gui;
    data['mm_version'] = mmVersion;
    data['success_events'] = successEvents;
    data['error_events'] = errorEvents;
    data['my_info'] = myInfo?.toJson();
    data['recoverable'] = recoverable;

    return data;
  }

  bool get isCompleted {
    final terminalSuccess = successEvents.isEmpty ? null : successEvents.last;
    return events.any(
      (event) =>
          (terminalSuccess != null && event.event.type == terminalSuccess) ||
          errorEvents.contains(event.event.type),
    );
  }

  bool get isFailed =>
      events.firstWhereOrNull(
        (event) => errorEvents.contains(event.event.type),
      ) !=
      null;
  bool get isSuccessful => isCompleted && !isFailed;
  SwapStatus get status {
    bool started = false, negotiated = false;
    for (SwapEventItem ev in events) {
      if (errorEvents.contains(ev.event.type)) return SwapStatus.failed;
      if (ev.event.type == 'Finished') return SwapStatus.successful;
      if (ev.event.type == 'Started') started = true;
      if (ev.event.type == 'Negotiated') negotiated = true;
    }
    if (negotiated) return SwapStatus.ongoing;
    if (started) return SwapStatus.matched;
    return SwapStatus.matching;
  }

  bool get isTaker => type == TradeSide.taker;

  String get sellCoin => isTaker ? takerCoin : makerCoin;

  Rational get sellAmount => isTaker ? takerAmount : makerAmount;

  String get buyCoin => isTaker ? makerCoin : takerCoin;

  Rational get buyAmount => isTaker ? makerAmount : takerAmount;

  bool get isTheSameTicker => abbr2Ticker(takerCoin) == abbr2Ticker(makerCoin);

  static int get statusSteps => 3;

  int get statusStep {
    switch (status) {
      case SwapStatus.matching:
        return 0;
      case SwapStatus.matched:
        return 1;
      case SwapStatus.ongoing:
        return 2;
      case SwapStatus.successful:
      case SwapStatus.failed:
        return 0;
      case SwapStatus.negotiated:
        return 0;
    }
  }

  static String getSwapStatusString(SwapStatus status) {
    switch (status) {
      case SwapStatus.matching:
        return LocaleKeys.matching.tr();
      case SwapStatus.matched:
        return LocaleKeys.matched.tr();
      case SwapStatus.ongoing:
        return LocaleKeys.ongoing.tr();
      case SwapStatus.successful:
        return LocaleKeys.successful.tr();
      case SwapStatus.failed:
        return LocaleKeys.failed.tr();
      default:
        return '';
    }
  }

  @override
  List<Object?> get props => [
    type,
    uuid,
    myOrderUuid,
    events,
    makerAmount,
    makerCoin,
    takerAmount,
    takerCoin,
    gui,
    mmVersion,
    successEvents,
    errorEvents,
    myInfo,
    recoverable,
  ];
}

class SwapEventItem extends Equatable {
  const SwapEventItem({required this.timestamp, required this.event});
  factory SwapEventItem.fromJson(Map<String, dynamic> json) {
    final timestamp = _boundedNonNegativeInt(
      json['timestamp'],
      maximum: _maximumEpochMilliseconds,
      field: 'timestamp',
    );
    return SwapEventItem(
      timestamp: timestamp,
      event: SwapEvent.fromJson(_stringMap(json['event'], 'event')),
    );
  }
  final int timestamp;
  final SwapEvent event;

  String get eventDateTime => DateFormat(
    'd MMMM y, H:m',
  ).format(DateTime.fromMillisecondsSinceEpoch(timestamp));

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['timestamp'] = timestamp;
    data['event'] = event.toJson();
    return data;
  }

  @override
  List<Object> get props => [timestamp, event];
}

class SwapEvent extends Equatable {
  const SwapEvent({required this.type, required this.data});

  factory SwapEvent.fromJson(Map<String, dynamic> json) {
    final type = _eventName(json['type'], 'event.type');
    return SwapEvent(
      type: type,
      data: (json['data'] != null && type != 'WatcherMessageSent')
          ? SwapEventData.fromJson(_stringMap(json['data'], 'event.data'))
          : null,
    );
  }

  final String type;
  final SwapEventData? data;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['type'] = type;
    data['data'] = this.data?.toJson();
    return data;
  }

  @override
  List<Object?> get props => [type, data];
}

class SwapEventData extends Equatable {
  const SwapEventData({
    required this.takerCoin,
    required this.makerCoin,
    required this.maker,
    required this.myPersistentPub,
    required this.lockDuration,
    required this.makerAmount,
    required this.takerAmount,
    required this.makerPaymentConfirmations,
    required this.makerPaymentRequiresNota,
    required this.takerPaymentConfirmations,
    required this.takerPaymentRequiresNota,
    required this.takerPaymentLock,
    required this.uuid,
    required this.startedAt,
    required this.makerPaymentWait,
    required this.makerCoinStartBlock,
    required this.takerCoinStartBlock,
    required this.feeToSendTakerFee,
    required this.takerPaymentTradeFee,
    required this.makerPaymentSpendTradeFee,
    required this.txHash,
  });

  factory SwapEventData.fromJson(Map<String, dynamic> json) {
    final rawUuid = json['uuid'];
    final uuid = rawUuid == null ? null : normalizeTradingEntityUuid(rawUuid);
    if (rawUuid != null && uuid == null) {
      throw const FormatException('Invalid event identifier');
    }
    final transaction = json['transaction'];
    final transactionHash = transaction == null
        ? null
        : _stringMap(transaction, 'transaction')['tx_hash'];
    return SwapEventData(
      takerCoin: _optionalAssetSymbol(json['taker_coin']),
      makerCoin: _optionalAssetSymbol(json['maker_coin']),
      maker: _optionalBoundedString(
        json['maker'],
        maximum: _maximumEvidenceTextLength,
      ),
      myPersistentPub: _optionalBoundedString(
        json['my_persistent_pub'],
        maximum: _maximumEvidenceTextLength,
      ),
      lockDuration: _optionalNonNegativeInt(json['lock_duration']),
      makerAmount: _optionalNonNegativeDouble(json['maker_amount']),
      takerAmount: _optionalNonNegativeDouble(json['taker_amount']),
      makerPaymentConfirmations: _optionalNonNegativeInt(
        json['maker_payment_confirmations'],
      ),
      makerPaymentRequiresNota: _optionalBool(
        json['maker_payment_requires_nota'],
      ),
      takerPaymentConfirmations: _optionalNonNegativeInt(
        json['taker_payment_confirmations'],
      ),
      takerPaymentRequiresNota: _optionalBool(
        json['taker_payment_requires_nota'],
      ),
      takerPaymentLock: _optionalNonNegativeInt(json['taker_payment_lock']),
      uuid: uuid,
      startedAt: _optionalNonNegativeInt(
        json['started_at'],
        maximum: _maximumEpochSeconds,
      ),
      makerPaymentWait: _optionalNonNegativeInt(json['maker_payment_wait']),
      makerCoinStartBlock: _optionalNonNegativeInt(
        json['maker_coin_start_block'],
      ),
      takerCoinStartBlock: _optionalNonNegativeInt(
        json['taker_coin_start_block'],
      ),
      feeToSendTakerFee: json['fee_to_send_taker_fee'] != null
          ? TradeFee.fromJson(_stringMap(json['fee_to_send_taker_fee'], 'fee'))
          : null,
      takerPaymentTradeFee: json['taker_payment_trade_fee'] != null
          ? TradeFee.fromJson(
              _stringMap(json['taker_payment_trade_fee'], 'fee'),
            )
          : null,
      makerPaymentSpendTradeFee: json['maker_payment_spend_trade_fee'] != null
          ? TradeFee.fromJson(
              _stringMap(json['maker_payment_spend_trade_fee'], 'fee'),
            )
          : null,
      txHash: _optionalBoundedString(
        json['tx_hash'] ?? transactionHash,
        maximum: _maximumEvidenceTextLength,
      ),
    );
  }

  final String? takerCoin;
  final String? makerCoin;
  final String? maker;
  final String? myPersistentPub;
  final int? lockDuration;
  final double? makerAmount;
  final double? takerAmount;
  final int? makerPaymentConfirmations;
  final bool? makerPaymentRequiresNota;
  final int? takerPaymentConfirmations;
  final bool? takerPaymentRequiresNota;
  final int? takerPaymentLock;
  final String? uuid;
  final int? startedAt;
  final int? makerPaymentWait;
  final int? makerCoinStartBlock;
  final int? takerCoinStartBlock;
  final TradeFee? feeToSendTakerFee;
  final TradeFee? takerPaymentTradeFee;
  final TradeFee? makerPaymentSpendTradeFee;
  final String? txHash;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['taker_coin'] = takerCoin;
    data['maker_coin'] = makerCoin;
    data['maker'] = maker;
    data['my_persistent_pub'] = myPersistentPub;
    data['lock_duration'] = lockDuration;
    data['maker_amount'] = makerAmount;
    data['taker_amount'] = takerAmount;
    data['maker_payment_confirmations'] = makerPaymentConfirmations;
    data['maker_payment_requires_nota'] = makerPaymentRequiresNota;
    data['taker_payment_confirmations'] = takerPaymentConfirmations;
    data['taker_payment_requires_nota'] = takerPaymentRequiresNota;
    data['taker_payment_lock'] = takerPaymentLock;
    data['uuid'] = uuid;
    data['started_at'] = startedAt;
    data['maker_payment_wait'] = makerPaymentWait;
    data['maker_coin_start_block'] = makerCoinStartBlock;
    data['taker_coin_start_block'] = takerCoinStartBlock;
    data['fee_to_send_taker_fee'] = feeToSendTakerFee?.toJson();
    data['taker_payment_trade_fee'] = takerPaymentTradeFee?.toJson();
    data['maker_payment_spend_trade_fee'] = makerPaymentSpendTradeFee?.toJson();
    data['tx_hash'] = txHash;
    return data;
  }

  @override
  List<Object?> get props => [
    takerCoin,
    makerCoin,
    maker,
    myPersistentPub,
    lockDuration,
    makerAmount,
    takerAmount,
    makerPaymentConfirmations,
    makerPaymentRequiresNota,
    takerPaymentConfirmations,
    takerPaymentRequiresNota,
    takerPaymentLock,
    uuid,
    startedAt,
    makerPaymentWait,
    makerCoinStartBlock,
    takerCoinStartBlock,
    feeToSendTakerFee,
    takerPaymentTradeFee,
    makerPaymentSpendTradeFee,
    txHash,
  ];
}

enum SwapStatus { successful, negotiated, ongoing, matched, matching, failed }

class TradeFee extends Equatable {
  const TradeFee({
    required this.coin,
    required this.amount,
    required this.paidFromTradingVol,
  });

  factory TradeFee.fromJson(Map<String, dynamic> json) {
    return TradeFee(
      coin: _assetSymbol(json['coin'], 'fee.coin'),
      amount: _optionalNonNegativeDouble(json['amount']),
      paidFromTradingVol: _requiredBool(
        json['paid_from_trading_vol'],
        'fee.paid_from_trading_vol',
      ),
    );
  }

  final String coin;
  final double? amount;
  final bool paidFromTradingVol;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['coin'] = coin;
    data['amount'] = amount;
    data['paid_from_trading_vol'] = paidFromTradingVol;
    return data;
  }

  @override
  List<Object?> get props => [coin, amount, paidFromTradingVol];
}

class SwapMyInfo extends Equatable {
  const SwapMyInfo({
    required this.myCoin,
    required this.otherCoin,
    required this.myAmount,
    required this.otherAmount,
    required this.startedAt,
  });

  factory SwapMyInfo.fromJson(Map<String, dynamic> json) {
    final myAmount = _requiredPositiveDouble(json['my_amount'], 'my_amount');
    final otherAmount = _requiredPositiveDouble(
      json['other_amount'],
      'other_amount',
    );
    return SwapMyInfo(
      myCoin: _assetSymbol(json['my_coin'], 'my_coin'),
      otherCoin: _assetSymbol(json['other_coin'], 'other_coin'),
      myAmount: myAmount,
      otherAmount: otherAmount,
      startedAt: _boundedNonNegativeInt(
        json['started_at'],
        maximum: _maximumEpochSeconds,
        field: 'started_at',
      ),
    );
  }

  final String myCoin;
  final String otherCoin;
  final double myAmount;
  final double otherAmount;
  final int startedAt;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['my_coin'] = myCoin;
    data['other_coin'] = otherCoin;
    data['my_amount'] = myAmount;
    data['other_amount'] = otherAmount;
    data['started_at'] = startedAt;
    return data;
  }

  @override
  List<Object?> get props => [
    myCoin,
    otherCoin,
    myAmount,
    otherAmount,
    startedAt,
  ];
}

Map<String, dynamic> _stringMap(Object? value, String field) {
  if (value is! Map) throw FormatException('Invalid $field');
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    throw FormatException('Invalid $field');
  }
}

List<SwapEventItem> _recoverableSwapEvents(Object? value) {
  if (value is! List) return const [];
  final events = <SwapEventItem>[];
  var lastTimestamp = -1;
  for (final raw in value.take(_maximumSwapEvents)) {
    if (raw is! Map) continue;
    try {
      final event = SwapEventItem.fromJson(Map<String, dynamic>.from(raw));
      if (event.timestamp < lastTimestamp) continue;
      events.add(event);
      lastTimestamp = event.timestamp;
    } on Object {
      // Auxiliary evidence must not hide a valid recoverable swap record.
    }
  }
  return List<SwapEventItem>.unmodifiable(events);
}

List<String> _recoverableEventDefinitions(Object? value) {
  if (value is! List) return const [];
  final definitions = <String>[];
  final seen = <String>{};
  for (final raw in value.take(_maximumEventDefinitions)) {
    try {
      final definition = _eventName(raw, 'event definition');
      if (seen.add(definition)) definitions.add(definition);
    } on Object {
      // Invalid auxiliary lifecycle labels are inert and never terminal.
    }
  }
  return List<String>.unmodifiable(definitions);
}

String _recoverableShortText(Object? value) {
  try {
    return _optionalBoundedString(value, maximum: _maximumShortTextLength) ??
        '';
  } on Object {
    return '';
  }
}

SwapMyInfo? _recoverableSwapMyInfo(Object? value) {
  if (value == null) return null;
  try {
    return SwapMyInfo.fromJson(_stringMap(value, 'my_info'));
  } on Object {
    return null;
  }
}

String _eventName(Object? value, String field) {
  if (value is! String ||
      value.isEmpty ||
      value.length > _maximumShortTextLength ||
      !RegExp(r'^[A-Za-z][A-Za-z0-9_:-]*$').hasMatch(value)) {
    throw FormatException('Invalid $field');
  }
  return value;
}

String _assetSymbol(Object? value, String field) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 64 ||
      value.trim() != value ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value)) {
    throw FormatException('Invalid $field');
  }
  return value;
}

String? _optionalAssetSymbol(Object? value) {
  return value == null ? null : _assetSymbol(value, 'asset');
}

String? _optionalBoundedString(Object? value, {required int maximum}) {
  if (value == null) return null;
  if (value is! String || value.length > maximum || value.trim() != value) {
    throw const FormatException('Invalid text value');
  }
  return value;
}

Rational _positiveRational(Object? fraction, Object? decimal, String field) {
  Rational? result;
  if (fraction is Map) {
    final values = _stringMap(fraction, field);
    final numerator = values['numer']?.toString();
    final denominator = values['denom']?.toString();
    if (_isBoundedInteger(numerator) && _isBoundedInteger(denominator)) {
      try {
        final parsedDenominator = BigInt.parse(denominator!);
        if (parsedDenominator != BigInt.zero) {
          result = Rational(BigInt.parse(numerator!), parsedDenominator);
        }
      } catch (_) {
        result = null;
      }
    }
  }
  if (result == null) {
    final value = decimal?.toString();
    if (value == null || value.length > _maximumNumericTextLength) {
      throw FormatException('Invalid $field');
    }
    result = Rational.tryParse(value);
  }
  if (result == null || result <= Rational.zero) {
    throw FormatException('Invalid $field');
  }
  return result;
}

bool _isBoundedInteger(String? value) {
  return value != null &&
      value.isNotEmpty &&
      value.length <= _maximumNumericTextLength &&
      RegExp(r'^-?[0-9]+$').hasMatch(value);
}

int _boundedNonNegativeInt(
  Object? value, {
  required int maximum,
  required String field,
}) {
  final text = value?.toString();
  if (text == null ||
      text.isEmpty ||
      text.length > 20 ||
      !RegExp(r'^[0-9]+$').hasMatch(text)) {
    throw FormatException('Invalid $field');
  }
  final parsed = int.tryParse(text);
  if (parsed == null || parsed < 0 || parsed > maximum) {
    throw FormatException('Invalid $field');
  }
  return parsed;
}

int? _optionalNonNegativeInt(
  Object? value, {
  int maximum = 0x7fffffffffffffff,
}) {
  return value == null
      ? null
      : _boundedNonNegativeInt(value, maximum: maximum, field: 'integer');
}

double _requiredPositiveDouble(Object? value, String field) {
  final result = _optionalNonNegativeDouble(value);
  if (result == null || result <= 0) throw FormatException('Invalid $field');
  return result;
}

double? _optionalNonNegativeDouble(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  if (text.isEmpty || text.length > _maximumNumericTextLength) {
    throw const FormatException('Invalid numeric value');
  }
  final parsed = double.tryParse(text);
  if (parsed == null || !parsed.isFinite || parsed < 0) {
    throw const FormatException('Invalid numeric value');
  }
  return parsed;
}

bool? _optionalBool(Object? value) {
  if (value == null) return null;
  if (value is! bool) throw const FormatException('Invalid boolean value');
  return value;
}

bool _requiredBool(Object? value, String field) {
  if (value is! bool) throw FormatException('Invalid $field');
  return value;
}
