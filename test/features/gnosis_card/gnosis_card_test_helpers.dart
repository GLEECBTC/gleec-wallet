import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_models.dart';
import 'package:web_dex/features/gnosis_card/domain/gnosis_card_ports.dart';

class GnosisTestSigner implements SmartAccountSigner {
  Completer<void>? personalSignatureGate;
  final Completer<void> personalSignatureStarted = Completer<void>();
  int personalSignatureCalls = 0;
  int typedDataSignatureCalls = 0;
  final List<String> registeredSafes = [];

  @override
  Future<SmartAccountOwner> owner() async => const SmartAccountOwner(
    address: '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    coin: 'GNO',
  );

  @override
  Future<void> registerSafe(String safeAddress) async {
    registeredSafes.add(safeAddress);
  }

  @override
  Future<String> signPersonalMessage(String message) async {
    personalSignatureCalls += 1;
    if (!personalSignatureStarted.isCompleted) {
      personalSignatureStarted.complete();
    }
    await personalSignatureGate?.future;
    return 'test-eip191-signature';
  }

  @override
  Future<SmartAccountSignature> signTypedData(
    PreparedSmartAccountIntent intent,
  ) async {
    typedDataSignatureCalls += 1;
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

  @override
  Future<CardOrderPaymentReceipt> pay(CardOrderPaymentQuote quote) async {
    calls += 1;
    return CardOrderPaymentReceipt(
      orderId: quote.orderId,
      transactionHash: '0xtest-synthetic-receipt',
      amountMinor: quote.amountMinor,
      currency: quote.currency,
      paidAt: DateTime.utc(2026, 7, 14, 12),
      isSimulated: true,
    );
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
