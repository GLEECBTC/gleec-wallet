part of 'atomic_swap_source.dart';

// KDF's swap gas limits for a network's own coin whose config sets none: to
// send the payment, and to refund it. Read at 4872ef2e (eth.rs `gas_limit`);
// a test fails when KDF is repinned, so they are checked again.
const _defaultPaymentGas = 155000;
const _defaultRefundGas = 125000;

/// What a failed order-book swap needs left in the coin sold.
extension _AtomicSwapRefund on AtomicSwapQuoteSource {
  /// The gas to refund [base]'s payment if the swap fails, beyond what
  /// [preimage] counts: KDF keeps it back only for Max.
  ///
  /// Priced as the preimage prices the payment. A swap that is refunded
  /// claims nothing, so a claim [base] already pays covers as much of it.
  /// Null unless [base] is an EVM network's own coin; a token's preimage
  /// counts its refund gas already.
  Decimal? _refundReserve(AssetId base, TradePreimageResponse preimage) {
    final payment = preimage.baseCoinFee;
    if (payment == null ||
        payment.coin != base.id ||
        SwapNetworks.evmChainIdOf(base) == null) {
      return null;
    }
    final paid = Decimal.tryParse(payment.amount);
    if (paid == null || paid <= Decimal.zero) return null;

    final limits = _gasLimitsOf?.call(base);
    int gasOf(String key, int fallback) => switch (limits?[key]) {
      final num value when value > 0 => value.toInt(),
      _ => fallback,
    };
    final refund =
        (paid *
                Decimal.fromInt(gasOf('eth_sender_refund', _defaultRefundGas)) /
                Decimal.fromInt(gasOf('eth_payment', _defaultPaymentGas)))
            .toDecimal(
              scaleOnInfinitePrecision: 18,
              toBigInt: (value) => value.ceil(),
            );

    final claim = preimage.relCoinFee;
    final claimed =
        claim != null && claim.coin == base.id && !claim.paidFromTradingVol
        ? Decimal.tryParse(claim.amount) ?? Decimal.zero
        : Decimal.zero;
    final reserve = refund - claimed;
    return reserve > Decimal.zero ? reserve : null;
  }
}
