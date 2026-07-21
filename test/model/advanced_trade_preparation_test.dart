import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:rational/rational.dart';
import 'package:web_dex/mm2/mm2_api/rpc/sell/sell_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/trade_preimage/trade_preimage_request.dart';
import 'package:web_dex/model/advanced_trade_preparation.dart';
import 'package:web_dex/model/trade_preimage.dart';
import 'package:web_dex/model/trade_preimage_extended_fee_info.dart';
import 'package:web_dex/model/trading_entity_id.dart';

void main() {
  const makerOrderId = '123e4567-e89b-12d3-a456-426614174000';
  final baseId = _assetId('KMD');
  final relId = _assetId('BTC');
  final volume = Rational.parse('1.25');
  final price = Rational.parse('0.5');
  final preparedAt = DateTime.utc(2026, 7, 21, 10);

  test('prepared taker request is exact, frozen, and fill-or-kill', () {
    final mutableFees = [_fee('KMD'), _fee('BTC')];
    final prepared = PreparedTakerTrade(
      walletId: 'wallet-a',
      formRevision: 7,
      baseAssetId: baseId,
      relAssetId: relId,
      base: 'KMD',
      rel: 'BTC',
      volume: volume,
      price: price,
      makerOrderId: makerOrderId,
      preimage: _preimage(
        method: 'sell',
        volume: volume,
        price: price,
        max: false,
        fees: mutableFees,
      ),
      preparedAt: preparedAt,
    );

    mutableFees.add(_fee('LTC'));
    expect(prepared.preimage.totalFees, hasLength(2));
    expect(
      () => prepared.preimage.totalFees.add(_fee('BTC')),
      throwsUnsupportedError,
    );

    final request = prepared.toRequest();
    expect(request.base, 'KMD');
    expect(request.rel, 'BTC');
    expect(request.volume, volume);
    expect(request.price, price);
    expect(request.orderType, SellBuyOrderType.fillOrKill);
  });

  test('prepared maker request is exact and wallet-bound', () {
    final prepared = PreparedMakerOrder(
      walletId: 'wallet-a',
      formRevision: 9,
      baseAssetId: baseId,
      relAssetId: relId,
      base: 'KMD',
      rel: 'BTC',
      volume: volume,
      price: price,
      max: true,
      preimage: _preimage(
        method: 'setprice',
        volume: volume,
        price: price,
        max: true,
      ),
      preparedAt: preparedAt,
    );

    final request = prepared.toRequest();
    expect(request.base, 'KMD');
    expect(request.rel, 'BTC');
    expect(request.volume, volume);
    expect(request.price, price);
    expect(request.max, isTrue);
  });

  test('preimage mismatch cannot create a prepared request', () {
    expect(
      () => PreparedTakerTrade(
        walletId: 'wallet-a',
        formRevision: 1,
        baseAssetId: baseId,
        relAssetId: relId,
        base: 'KMD',
        rel: 'BTC',
        volume: volume,
        price: price,
        makerOrderId: makerOrderId,
        preimage: _preimage(
          method: 'sell',
          volume: volume,
          price: Rational.one,
          max: false,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('malformed maker order id cannot create a prepared taker trade', () {
    expect(
      () => PreparedTakerTrade(
        walletId: 'wallet-a',
        formRevision: 1,
        baseAssetId: baseId,
        relAssetId: relId,
        base: 'KMD',
        rel: 'BTC',
        volume: volume,
        price: price,
        makerOrderId: 'not-a-uuid',
        preimage: _preimage(
          method: 'sell',
          volume: volume,
          price: price,
          max: false,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('understated fee totals cannot create a prepared trade', () {
    expect(
      () => PreparedMakerOrder(
        walletId: 'wallet-a',
        formRevision: 1,
        baseAssetId: baseId,
        relAssetId: relId,
        base: 'KMD',
        rel: 'BTC',
        volume: volume,
        price: price,
        max: false,
        preimage: _preimage(
          method: 'setprice',
          volume: volume,
          price: price,
          max: false,
          fees: [_fee('KMD')],
        ),
      ),
      throwsArgumentError,
    );
  });

  test('high-precision repeating fee decimals retain exact authority', () {
    final repeatingBase = _feeWithAmount(
      'KMD',
      '0.33333333333333333333333333333333333333333333333333',
      Rational(BigInt.one, BigInt.from(3)),
    );
    final repeatingRel = _feeWithAmount(
      'BTC',
      '0.33333333333333333333333333333333333333333333333333',
      Rational(BigInt.one, BigInt.from(3)),
    );

    expect(
      () => PreparedMakerOrder(
        walletId: 'wallet-a',
        formRevision: 1,
        baseAssetId: baseId,
        relAssetId: relId,
        base: 'KMD',
        rel: 'BTC',
        volume: volume,
        price: price,
        max: false,
        preimage: _preimage(
          method: 'setprice',
          volume: volume,
          price: price,
          max: false,
          baseFee: repeatingBase,
          relFee: repeatingRel,
        ),
      ),
      returnsNormally,
    );
  });

  test('coarse fee decimal mismatch cannot create a prepared trade', () {
    final mismatchedBase = _feeWithAmount(
      'KMD',
      '0.3',
      Rational(BigInt.one, BigInt.from(3)),
    );

    expect(
      () => PreparedMakerOrder(
        walletId: 'wallet-a',
        formRevision: 1,
        baseAssetId: baseId,
        relAssetId: relId,
        base: 'KMD',
        rel: 'BTC',
        volume: volume,
        price: price,
        max: false,
        preimage: _preimage(
          method: 'setprice',
          volume: volume,
          price: price,
          max: false,
          baseFee: mismatchedBase,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'freshness accepts the boundary and rejects future or stale reviews',
    () {
      final prepared = PreparedTakerTrade(
        walletId: 'wallet-a',
        formRevision: 1,
        baseAssetId: baseId,
        relAssetId: relId,
        base: 'KMD',
        rel: 'BTC',
        volume: volume,
        price: price,
        makerOrderId: makerOrderId,
        preimage: _preimage(
          method: 'sell',
          volume: volume,
          price: price,
          max: false,
        ),
        preparedAt: preparedAt,
      );

      expect(
        prepared.isFreshAt(
          preparedAt.add(const Duration(minutes: 2)),
          maxAge: const Duration(minutes: 2),
        ),
        isTrue,
      );
      expect(
        prepared.isFreshAt(
          preparedAt.add(const Duration(minutes: 2, milliseconds: 1)),
          maxAge: const Duration(minutes: 2),
        ),
        isFalse,
      );
      expect(
        prepared.isFreshAt(
          preparedAt.subtract(const Duration(microseconds: 1)),
          maxAge: const Duration(minutes: 2),
        ),
        isFalse,
      );
      expect(prepared.isFreshAt(preparedAt, maxAge: Duration.zero), isFalse);
    },
  );

  test('trading UUIDs are canonicalized and malformed values are rejected', () {
    expect(
      normalizeTradingEntityUuid(' 123E4567-E89B-12D3-A456-426614174000 '),
      makerOrderId,
    );
    expect(normalizeTradingEntityUuid('maker-order'), isNull);
    expect(normalizeTradingEntityUuid('${makerOrderId}00'), isNull);
    expect(normalizeTradingEntityUuid(null), isNull);
    expect(
      normalizeTradingEntityUuid('00000000-0000-0000-0000-000000000001'),
      '00000000-0000-0000-0000-000000000001',
    );
  });
}

AssetId _assetId(String id) => AssetId(
  id: id,
  name: id,
  symbol: AssetSymbol(assetConfigId: id.toLowerCase()),
  chainId: AssetChainId(chainId: 1),
  derivationPath: null,
  subClass: CoinSubClass.utxo,
);

TradePreimageExtendedFeeInfo _fee(String coin) => TradePreimageExtendedFeeInfo(
  coin: coin,
  amount: '0.01',
  amountRational: Rational.parse('0.01'),
  paidFromTradingVol: false,
);

TradePreimageExtendedFeeInfo _feeWithAmount(
  String coin,
  String amount,
  Rational amountRational,
) => TradePreimageExtendedFeeInfo(
  coin: coin,
  amount: amount,
  amountRational: amountRational,
  paidFromTradingVol: false,
);

TradePreimage _preimage({
  required String method,
  required Rational volume,
  required Rational price,
  required bool max,
  List<TradePreimageExtendedFeeInfo>? fees,
  TradePreimageExtendedFeeInfo? baseFee,
  TradePreimageExtendedFeeInfo? relFee,
}) {
  final resolvedBaseFee = baseFee ?? _fee('KMD');
  final resolvedRelFee = relFee ?? _fee('BTC');
  return TradePreimage(
    baseCoinFee: resolvedBaseFee,
    relCoinFee: resolvedRelFee,
    volume: volume.toString(),
    volumeFract: volume,
    takerFee: null,
    totalFees: fees ?? [resolvedBaseFee, resolvedRelFee],
    feeToSendTakerFee: null,
    request: TradePreimageRequest(
      base: 'KMD',
      rel: 'BTC',
      swapMethod: method,
      price: price,
      volume: volume,
      max: max,
    ),
  );
}
