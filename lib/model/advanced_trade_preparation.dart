import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/setprice/setprice_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_request.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/model/trade_preimage_extended_fee_info.dart';
import 'package:web_dex/model/trading_entity_id.dart';

const int _maximumWalletIdLength = 512;
const int _maximumAssetSymbolLength = 64;
const int _maximumAmountLength = 128;
const int _maximumFeeEntries = 16;

enum AdvancedTradeSubmissionStatus {
  idle,
  prepared,
  submitting,
  accepted,
  failed,
  uncertain,
}

enum AdvancedTradeSubmissionFailure {
  walletChanged,
  preparationInvalid,
  preparationExpired,
  tradingUnavailable,
  clockInvalid,
  rejected,
  uncertain,
  unknown,
}

/// Immutable, wallet-bound request shown by the Advanced taker confirmation.
@immutable
final class PreparedTakerTrade extends Equatable {
  PreparedTakerTrade({
    required this.walletId,
    required this.formRevision,
    required this.baseAssetId,
    required this.relAssetId,
    required this.base,
    required this.rel,
    required this.volume,
    required this.price,
    required String makerOrderId,
    required TradePreimage preimage,
    DateTime? preparedAt,
  }) : makerOrderId = normalizeTradingEntityUuid(makerOrderId) ?? '',
       preimage = _freezePreimage(preimage),
       preparedAt = (preparedAt ?? DateTime.timestamp()).toUtc() {
    if (!_isCanonicalWalletId(walletId) ||
        !_isCanonicalAssetSymbol(base) ||
        !_isCanonicalAssetSymbol(rel) ||
        this.makerOrderId.isEmpty ||
        formRevision < 0 ||
        volume <= Rational.zero ||
        price <= Rational.zero ||
        !_matchesPreimage(this.preimage) ||
        !_hasValidFeeEvidence(this.preimage, volume)) {
      throw ArgumentError('Invalid prepared taker trade');
    }
  }

  final String walletId;
  final int formRevision;
  final AssetId baseAssetId;
  final AssetId relAssetId;
  final String base;
  final String rel;
  final Rational volume;
  final Rational price;
  final String makerOrderId;
  final TradePreimage preimage;
  final DateTime preparedAt;

  bool isFreshAt(DateTime now, {required Duration maxAge}) {
    final checkedAt = now.toUtc();
    return maxAge > Duration.zero &&
        !preparedAt.isAfter(checkedAt) &&
        checkedAt.difference(preparedAt) <= maxAge;
  }

  bool _matchesPreimage(TradePreimage value) {
    final request = value.request;
    return request.swapMethod == 'sell' &&
        request.base == base &&
        request.rel == rel &&
        request.volume == volume &&
        request.price == price &&
        !request.max;
  }

  SellRequest toRequest() => SellRequest(
    base: base,
    rel: rel,
    volume: volume,
    price: price,
    orderType: SellBuyOrderType.fillOrKill,
  );

  @override
  List<Object?> get props => [
    walletId,
    formRevision,
    baseAssetId,
    relAssetId,
    base,
    rel,
    volume,
    price,
    makerOrderId,
    preparedAt,
    preimage,
  ];
}

/// Immutable, wallet-bound request shown by the Advanced maker confirmation.
@immutable
final class PreparedMakerOrder extends Equatable {
  PreparedMakerOrder({
    required this.walletId,
    required this.formRevision,
    required this.baseAssetId,
    required this.relAssetId,
    required this.base,
    required this.rel,
    required this.volume,
    required this.price,
    required this.max,
    required TradePreimage preimage,
    DateTime? preparedAt,
  }) : preimage = _freezePreimage(preimage),
       preparedAt = (preparedAt ?? DateTime.timestamp()).toUtc() {
    if (!_isCanonicalWalletId(walletId) ||
        !_isCanonicalAssetSymbol(base) ||
        !_isCanonicalAssetSymbol(rel) ||
        formRevision < 0 ||
        volume <= Rational.zero ||
        price <= Rational.zero ||
        !_matchesPreimage(this.preimage) ||
        !_hasValidFeeEvidence(this.preimage, volume)) {
      throw ArgumentError('Invalid prepared maker order');
    }
  }

  final String walletId;
  final int formRevision;
  final AssetId baseAssetId;
  final AssetId relAssetId;
  final String base;
  final String rel;
  final Rational volume;
  final Rational price;
  final bool max;
  final TradePreimage preimage;
  final DateTime preparedAt;

  bool isFreshAt(DateTime now, {required Duration maxAge}) {
    final checkedAt = now.toUtc();
    return maxAge > Duration.zero &&
        !preparedAt.isAfter(checkedAt) &&
        checkedAt.difference(preparedAt) <= maxAge;
  }

  bool _matchesPreimage(TradePreimage value) {
    final request = value.request;
    return request.swapMethod == 'setprice' &&
        request.base == base &&
        request.rel == rel &&
        request.volume == volume &&
        request.price == price &&
        request.max == max;
  }

  SetPriceRequest toRequest() => SetPriceRequest(
    base: base,
    rel: rel,
    volume: volume,
    price: price,
    max: max,
  );

  @override
  List<Object?> get props => [
    walletId,
    formRevision,
    baseAssetId,
    relAssetId,
    base,
    rel,
    volume,
    price,
    max,
    preparedAt,
    preimage,
  ];
}

TradePreimage _freezePreimage(TradePreimage source) {
  final request = source.request;
  return TradePreimage(
    baseCoinFee: source.baseCoinFee,
    relCoinFee: source.relCoinFee,
    volume: source.volume,
    volumeFract: source.volumeFract,
    takerFee: source.takerFee,
    totalFees: List.unmodifiable(source.totalFees),
    feeToSendTakerFee: source.feeToSendTakerFee,
    request: TradePreimageRequest(
      base: request.base,
      rel: request.rel,
      swapMethod: request.swapMethod,
      price: request.price,
      volume: request.volume,
      max: request.max,
    ),
  );
}

bool _isCanonicalWalletId(String value) {
  return value.isNotEmpty &&
      value.length <= _maximumWalletIdLength &&
      value.trim() == value;
}

bool _isCanonicalAssetSymbol(String value) {
  return value.isNotEmpty &&
      value.length <= _maximumAssetSymbolLength &&
      value.trim() == value &&
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value);
}

bool _hasValidFeeEvidence(TradePreimage preimage, Rational expectedVolume) {
  if (preimage.totalFees.isEmpty ||
      preimage.totalFees.length > _maximumFeeEntries) {
    return false;
  }
  final decimalVolume = preimage.volume;
  if (decimalVolume != null) {
    if (decimalVolume.length > _maximumAmountLength ||
        Rational.tryParse(decimalVolume) != expectedVolume) {
      return false;
    }
  }
  final fractionalVolume = preimage.volumeFract;
  if (fractionalVolume != null && fractionalVolume != expectedVolume) {
    return false;
  }
  final components = <TradePreimageExtendedFeeInfo?>[
    preimage.baseCoinFee,
    preimage.relCoinFee,
    preimage.takerFee,
    preimage.feeToSendTakerFee,
  ].whereType<TradePreimageExtendedFeeInfo>().toList(growable: false);
  if (![...components, ...preimage.totalFees].every(_isValidFee)) {
    return false;
  }

  final componentTotals = <String, Rational>{};
  for (final fee in components) {
    final coin = fee.coin.toUpperCase();
    componentTotals[coin] =
        (componentTotals[coin] ?? Rational.zero) + fee.amountRational;
  }
  final declaredTotals = <String, Rational>{};
  for (final fee in preimage.totalFees) {
    final coin = fee.coin.toUpperCase();
    declaredTotals[coin] =
        (declaredTotals[coin] ?? Rational.zero) + fee.amountRational;
  }
  return componentTotals.entries.every(
    (entry) => (declaredTotals[entry.key] ?? Rational.zero) >= entry.value,
  );
}

bool _isValidFee(TradePreimageExtendedFeeInfo fee) {
  if (!_isCanonicalAssetSymbol(fee.coin) ||
      fee.amount.isEmpty ||
      fee.amount.length > _maximumAmountLength ||
      fee.amount.trim() != fee.amount ||
      fee.amountRational < Rational.zero) {
    return false;
  }
  final decimalAmount = Rational.tryParse(fee.amount);
  if (decimalAmount == null || decimalAmount < Rational.zero) return false;
  if (decimalAmount == fee.amountRational) return true;

  // KDF serializes repeating rationals as long, truncated decimal evidence
  // (for example 1/7770). Accept at most one final decimal unit of that
  // high-precision representation; short/coarse mismatches remain invalid.
  final separator = fee.amount.indexOf('.');
  final fractionalDigits = separator < 0
      ? 0
      : fee.amount.length - separator - 1;
  if (fractionalDigits < 16 ||
      !RegExp(r'^[0-9]+\.[0-9]+$').hasMatch(fee.amount)) {
    return false;
  }
  final difference = (decimalAmount - fee.amountRational).abs();
  final finalDecimalUnit = Rational(
    BigInt.one,
    BigInt.from(10).pow(fractionalDigits),
  );
  return difference < finalDecimalUnit;
}
