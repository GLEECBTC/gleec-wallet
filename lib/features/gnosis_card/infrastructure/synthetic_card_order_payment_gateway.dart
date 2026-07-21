import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

/// Debug-only physical-card payment simulation.
///
/// This adapter creates a synthetic receipt locally. It never selects a wallet
/// asset, asks KDF to sign, broadcasts a transaction, or moves funds.
class SyntheticCardOrderPaymentGateway implements CardOrderPaymentGateway {
  final Map<String, CardOrderPaymentReceipt> _receipts = {};

  @override
  Future<CardOrderPaymentReceipt?> findPayment({
    required CardOrderPaymentQuote quote,
    required String idempotencyKey,
  }) async {
    final receipt = _receipts[idempotencyKey];
    return receipt?.orderId == quote.orderId ? receipt : null;
  }

  @override
  Future<CardOrderPaymentReceipt> pay(
    CardOrderPaymentQuote quote, {
    required String idempotencyKey,
  }) async {
    if (!kDebugMode) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.paymentFailed,
        message: 'Simulated card payment is available in debug builds only.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }
    if (!quote.isSimulated || quote.assetSymbol != 'EURe') {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.paymentFailed,
        message: 'This gateway accepts simulated EURe card orders only.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }

    final existing = await findPayment(
      quote: quote,
      idempotencyKey: idempotencyKey,
    );
    if (existing != null) return existing;
    final digest = sha256.convert(
      utf8.encode(
        'gnosis-card-payment-mock:'
        '$idempotencyKey:'
        '${quote.orderId}:${quote.amountMinor}:${quote.currency}:'
        '${quote.assetContract}:${quote.recipient}',
      ),
    );
    final receipt = CardOrderPaymentReceipt(
      orderId: quote.orderId,
      transactionHash: '0x$digest',
      amountMinor: quote.amountMinor,
      currency: quote.currency,
      paidAt: DateTime.utc(2026, 7, 10, 12),
      isSimulated: true,
    );
    _receipts[idempotencyKey] = receipt;
    return receipt;
  }
}
