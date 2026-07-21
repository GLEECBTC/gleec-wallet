import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/trade_preimage_extended_fee_info.dart';
import 'package:web_dex/shared/utils/utils.dart';

class TradePreimageResponse
    implements BaseResponse<TradePreimageResponseResult> {
  TradePreimageResponse({required this.result, required this.mmrpc});
  factory TradePreimageResponse.fromJson(Map<String, dynamic> json) {
    final mmrpc = json['mmrpc'];
    if (mmrpc is! String || mmrpc.isEmpty || mmrpc.length > 16) {
      throw const FormatException('Invalid trade preimage RPC version');
    }
    return TradePreimageResponse(
      result: TradePreimageResponseResult.fromJson(
        _stringMap(json['result'], 'result'),
      ),
      mmrpc: mmrpc,
    );
  }
  @override
  final TradePreimageResponseResult result;
  @override
  final String mmrpc;
}

class TradePreimageResponseResult {
  TradePreimageResponseResult({
    required this.baseCoinFee,
    required this.relCoinFee,
    required this.volume,
    required this.volumeRat,
    required this.volumeFraction,
    required this.takerFee,
    required this.feeToSendTakerFee,
    required this.totalFees,
  });
  factory TradePreimageResponseResult.fromJson(Map<String, dynamic> json) {
    final volume = json['volume'];
    if (volume != null &&
        (volume is! String ||
            volume.isEmpty ||
            volume.length > 128 ||
            volume.trim() != volume ||
            Rational.tryParse(volume) == null)) {
      throw const FormatException('Invalid trade preimage volume');
    }
    final rawTotalFees = json['total_fees'];
    if (rawTotalFees is! List ||
        rawTotalFees.isEmpty ||
        rawTotalFees.length > 16) {
      throw const FormatException('Invalid total trade fees');
    }
    final totalFees = rawTotalFees
        .map(
          (value) => TradePreimageExtendedFeeInfo.fromJson(
            _stringMap(value, 'total fee'),
          ),
        )
        .toList(growable: false);
    final volumeFraction = json['volume_fraction'] == null
        ? null
        : fract2rat(
            _stringMap(json['volume_fraction'], 'volume fraction'),
            false,
          );
    if (json['volume_fraction'] != null || volumeFraction != null) {
      if (volumeFraction == null || volumeFraction <= Rational.zero) {
        throw const FormatException('Invalid trade preimage volume fraction');
      }
    }
    return TradePreimageResponseResult(
      baseCoinFee: TradePreimageExtendedFeeInfo.fromJson(
        _stringMap(json['base_coin_fee'], 'base coin fee'),
      ),
      relCoinFee: TradePreimageExtendedFeeInfo.fromJson(
        _stringMap(json['rel_coin_fee'], 'rel coin fee'),
      ),
      volume: volume as String?,
      volumeRat: _boundedVolumeRat(json['volume_rat']),
      volumeFraction: volumeFraction,
      takerFee: json['taker_fee'] == null
          ? null
          : TradePreimageExtendedFeeInfo.fromJson(
              _stringMap(json['taker_fee'], 'taker fee'),
            ),
      feeToSendTakerFee: json['fee_to_send_taker_fee'] == null
          ? null
          : TradePreimageExtendedFeeInfo.fromJson(
              _stringMap(
                json['fee_to_send_taker_fee'],
                'fee to send taker fee',
              ),
            ),
      totalFees: List<TradePreimageExtendedFeeInfo>.unmodifiable(totalFees),
    );
  }
  final TradePreimageExtendedFeeInfo baseCoinFee;
  final TradePreimageExtendedFeeInfo relCoinFee;
  final String? volume;
  final List<List<dynamic>> volumeRat;
  final Rational? volumeFraction;
  final TradePreimageExtendedFeeInfo? takerFee;
  final TradePreimageExtendedFeeInfo? feeToSendTakerFee;
  final List<TradePreimageExtendedFeeInfo> totalFees;
}

Map<String, dynamic> _stringMap(Object? value, String field) {
  if (value is! Map) throw FormatException('Invalid $field');
  try {
    return Map<String, dynamic>.from(value);
  } catch (_) {
    throw FormatException('Invalid $field');
  }
}

List<List<dynamic>> _boundedVolumeRat(Object? value) {
  if (value == null) return const [];
  if (value is! List || value.length > 4) {
    throw const FormatException('Invalid volume rational evidence');
  }
  final result = <List<dynamic>>[];
  for (final part in value) {
    if (part is! List || part.length > 4) {
      throw const FormatException('Invalid volume rational evidence');
    }
    for (final component in part) {
      if (component is List && component.length > 64) {
        throw const FormatException('Invalid volume rational evidence');
      }
    }
    result.add(List<dynamic>.unmodifiable(part));
  }
  return List<List<dynamic>>.unmodifiable(result);
}
