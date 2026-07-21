import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

class GnosisTestSigner implements SmartAccountSigner {
  SmartAccountOwner activeOwner = const SmartAccountOwner(
    address: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    coin: 'GNO',
  );
  Completer<void>? personalSignatureGate;
  final Completer<void> personalSignatureStarted = Completer<void>();
  int personalSignatureCalls = 0;
  int typedDataSignatureCalls = 0;
  final List<String> registeredSafes = [];
  final List<String> personalMessages = [];
  final List<SmartAccountOwner> expectedPersonalOwners = [];
  final List<SmartAccountOwner> expectedRegistrationOwners = [];
  final List<SmartAccountOwner> expectedTypedDataOwners = [];

  @override
  Future<SmartAccountOwner> owner() async => activeOwner;

  @override
  Future<void> registerSafe(
    String safeAddress, {
    required SmartAccountOwner expectedOwner,
  }) async {
    expectedRegistrationOwners.add(expectedOwner);
    registeredSafes.add(safeAddress);
  }

  @override
  Future<String> signPersonalMessage(
    String message, {
    required SmartAccountOwner expectedOwner,
  }) async {
    personalSignatureCalls += 1;
    personalMessages.add(message);
    expectedPersonalOwners.add(expectedOwner);
    if (!personalSignatureStarted.isCompleted) {
      personalSignatureStarted.complete();
    }
    await personalSignatureGate?.future;
    return 'test-eip191-${message.hashCode}';
  }

  @override
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent, {
    required SmartAccountOwner expectedOwner,
  }) async {
    typedDataSignatureCalls += 1;
    expectedTypedDataOwners.add(expectedOwner);
    return const SmartAccountSignature(
      signature: 'test-eip712-signature',
      typedDataHash:
          '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ownerAddress: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  }
}

class RecordingExternalFlowLauncher implements ExternalFlowLauncher {
  RecordingExternalFlowLauncher({this.shouldFail = false});

  final bool shouldFail;
  final List<GnosisExternalFlow> flows = [];

  @override
  Future<void> launch(GnosisExternalFlow flow) async {
    flows.add(flow);
    if (shouldFail) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.unavailable,
        message: 'The external test surface is unavailable.',
        recovery: GnosisCardRecovery.retry,
      );
    }
  }
}

class GnosisTestPaymentGateway implements CardOrderPaymentGateway {
  int calls = 0;
  final Map<String, CardOrderPaymentReceipt> _receipts = {};

  @override
  Future<CardOrderPaymentReceipt?> findPayment({
    required CardOrderPaymentQuote quote,
    required String idempotencyKey,
  }) async => _receipts[idempotencyKey];

  @override
  Future<CardOrderPaymentReceipt> pay(
    CardOrderPaymentQuote quote, {
    required String idempotencyKey,
  }) async {
    final existing = _receipts[idempotencyKey];
    if (existing != null) return existing;
    calls += 1;
    final receipt = CardOrderPaymentReceipt(
      orderId: quote.orderId,
      transactionHash: '0xtest-synthetic-receipt',
      amountMinor: quote.amountMinor,
      currency: quote.currency,
      paidAt: DateTime.utc(2026, 7, 14, 12),
      isSimulated: true,
    );
    _receipts[idempotencyKey] = receipt;
    return receipt;
  }
}

class GnosisTestSecureElementGateway implements CardSecureElementGateway {
  GnosisTestSecureElementGateway({this.cancelProvisioning = false});

  final bool cancelProvisioning;
  int provisioningCalls = 0;

  @override
  Future<void> provisionInitialPin(
    BuildContext context, {
    required CardProvisioningHandle handle,
  }) async {
    provisioningCalls += 1;
    if (cancelProvisioning) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.unavailable,
        message: 'The secure setup handoff was cancelled.',
        recovery: GnosisCardRecovery.retry,
      );
    }
  }

  @override
  Future<void> showCardDetails(
    BuildContext context, {
    required String cardId,
  }) async {}

  @override
  Future<void> showPin(BuildContext context, {required String cardId}) async {}
}
